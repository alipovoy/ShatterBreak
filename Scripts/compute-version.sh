#!/usr/bin/env bash
set -euo pipefail

DEFAULT_SEMVER="1.0.0"
MODE=""
TAG=""
BUMP=""
WRITE_XCCONFIG=""
EXPORT=0

usage() {
  cat <<'EOF'
Usage: compute-version.sh --mode MODE [options]

Modes:
  local-auto    Detect suffix from Xcode build context (dev/test/local)
  ci-test       CI PR/push: derived semver with -test suffix
  ci-release    CI release: semver taken verbatim from the release tag
  next-tag      Print the git tag to create for the next release, then exit

Versioning:
  X.Y.Z come from the latest vX.Y.Z tag. The next version is derived from the
  Conventional Commit subjects merged since that tag: `feat:` bumps the minor,
  `fix:`/`perf:`/other types bump the patch, and a `!` marker or `BREAKING
  CHANGE` footer bumps the major. Creating a new vX.Y.Z tag resets the baseline.

Options:
  --tag TAG             Release tag (e.g. v1.0.0); used with ci-release
  --bump LEVEL          For next-tag: force patch, minor, or major instead of
                        the auto-detected bump
  --write-xcconfig PATH Write MARKETING_VERSION and CURRENT_PROJECT_VERSION to xcconfig
  --export              Print shell assignments to stdout (for eval in CI)
  -h, --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    --bump)
      BUMP="$2"
      shift 2
      ;;
    --write-xcconfig)
      WRITE_XCCONFIG="$2"
      shift 2
      ;;
    --export)
      EXPORT=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "Missing required --mode" >&2
  usage >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

strip_v_prefix() {
  local value="$1"
  value="${value#v}"
  echo "$value"
}

# Marketing semver for an explicit release tag. The tag must be a fully pinned
# vMAJOR.MINOR.PATCH. The leading `v` is required: the baseline lookup below
# only matches `v*` tags, so a tag without it (e.g. `1.4.5`) would be silently
# ignored afterwards and dev versions would regress.
resolve_release_semver() {
  if [[ -z "$TAG" ]]; then
    echo "ci-release requires --tag" >&2
    exit 1
  fi
  if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid release tag '$TAG'; expected vMAJOR.MINOR.PATCH (e.g. v1.4.5)." >&2
    echo "Get the right tag with: Scripts/compute-version.sh --mode next-tag" >&2
    exit 1
  fi
  strip_v_prefix "$TAG"
}

# Highest-version `v*` tag reachable from HEAD, or empty if none. We pick by
# version order rather than `git describe`'s topological "nearest", because two
# tags can sit on the same commit (e.g. v1.2.3 then v1.4) and `git describe`'s
# tie-break between them is unreliable. Highest-reachable is deterministic and,
# since versions only move up, always the latest baseline.
# The grep filter keeps only strict vMAJOR.MINOR.PATCH tags, so partial or
# pre-release tags (v1, v1.4, v1.3.0-rc.1, v2-beta) are ignored rather than
# chosen as the baseline — they aren't releases in this project's model. This
# also guarantees apply_bump only ever receives a clean three-component version,
# instead of silently drifting (v1.4 -> 1.4.1) or crashing its arithmetic.
# The trailing `|| true` keeps a no-match grep (no conforming tags) from tripping
# `set -o pipefail` and aborting the DEFAULT_SEMVER fallback.
latest_baseline_tag() {
  git tag --merged HEAD --sort=-v:refname --list 'v[0-9]*' 2>/dev/null \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true
}

# The baseline version: the latest vX.Y.Z tag, or DEFAULT_SEMVER when no tag
# exists. latest_baseline_tag guarantees a strict three-component tag here.
baseline_semver() {
  local tag
  tag="$(latest_baseline_tag)"
  if [[ -z "$tag" ]]; then
    echo "$DEFAULT_SEMVER"
    return
  fi
  strip_v_prefix "$tag"
}

# Inspect the Conventional Commit messages in a git range and echo the implied
# SemVer bump: major | minor | patch | none. Any `!` marker (e.g. `feat!:`) or a
# `BREAKING CHANGE:` footer wins as major; a `feat:` subject is minor; any other
# commits are patch; an empty range is none. Every subject in the range drives
# the decision: with squash-merge that is one subject (the PR title); with
# rebase-merge it is one per replayed commit. The footer match is anchored to a
# line start (per the Conventional Commits spec) so a commit that merely mentions
# the phrase in prose does not trigger a spurious major bump.
detect_bump() {
  local range="$1" subjects bodies
  subjects="$(git log --format='%s' "$range" 2>/dev/null)"
  bodies="$(git log --format='%B' "$range" 2>/dev/null)"
  if [[ -z "$subjects" ]]; then
    echo "none"
    return
  fi
  if printf '%s\n' "$subjects" | grep -qE '^[a-z]+(\([^)]+\))?!:' \
    || printf '%s\n' "$bodies" | grep -qE '^BREAKING[ -]CHANGE:'; then
    echo "major"
  elif printf '%s\n' "$subjects" | grep -qE '^feat(\([^)]+\))?:'; then
    echo "minor"
  else
    echo "patch"
  fi
}

# Apply a bump level (major|minor|patch|none) to a three-component base version.
apply_bump() {
  local base="$1" level="$2" major minor patch
  IFS=. read -r major minor patch <<<"$base"
  case "$level" in
    major) echo "$(( major + 1 )).0.0" ;;
    minor) echo "${major}.$(( minor + 1 )).0" ;;
    patch) echo "${major}.${minor}.$(( patch + 1 ))" ;;
    none) echo "${major}.${minor}.${patch}" ;;
    *)
      echo "Unknown bump level: $level" >&2
      exit 1
      ;;
  esac
}

# Marketing semver for dev/CI builds and for the next release tag. X.Y.Z come
# from the latest vX.Y[.Z] tag; the bump is derived from the Conventional Commit
# messages merged since that tag. Before the first tag exists, the next release
# is simply DEFAULT_SEMVER.
resolve_next_semver() {
  local tag
  tag="$(latest_baseline_tag)"
  if [[ -z "$tag" ]]; then
    baseline_semver
    return
  fi
  apply_bump "$(baseline_semver)" "$(detect_bump "${tag}..HEAD")"
}

resolve_hash() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git rev-parse --short=7 HEAD
  else
    echo "unknown"
  fi
}

resolve_local_suffix() {
  if [[ "${ACTION:-}" == "install" ]]; then
    echo "local"
  elif [[ "${BUILD_FOR_TESTING:-}" == "YES" ]]; then
    echo "test"
  else
    echo "dev"
  fi
}

hash="$(resolve_hash)"

case "$MODE" in
  local-auto)
    suffix="$(resolve_local_suffix)"
    marketing_version="$(resolve_next_semver)-${suffix}"
    project_version="$(git rev-list --count HEAD)"
    ;;
  ci-test)
    marketing_version="$(resolve_next_semver)-test"
    project_version="$GITHUB_RUN_NUMBER"
    ;;
  ci-release)
    if [[ -z "${GITHUB_RUN_NUMBER:-}" ]]; then
      echo "ci-release requires GITHUB_RUN_NUMBER (must run in CI)" >&2
      exit 1
    fi
    marketing_version="$(resolve_release_semver)"
    project_version="$GITHUB_RUN_NUMBER"
    ;;
  next-tag)
    # Print the tag to create for the next release, then exit. Without --bump the
    # level is auto-detected from the Conventional Commits since the last tag;
    # with --bump it is forced relative to that tag's baseline.
    if [[ -z "$BUMP" ]]; then
      echo "v$(resolve_next_semver)"
    else
      case "$BUMP" in
        patch | minor | major)
          echo "v$(apply_bump "$(baseline_semver)" "$BUMP")"
          ;;
        *)
          echo "Unknown --bump: $BUMP (expected patch, minor, or major)" >&2
          exit 1
          ;;
      esac
    fi
    exit 0
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    exit 1
    ;;
esac

if [[ -n "$WRITE_XCCONFIG" ]]; then
  mkdir -p "$(dirname "$WRITE_XCCONFIG")"
  cat >"$WRITE_XCCONFIG" <<EOF
// Generated by Scripts/compute-version.sh — do not edit manually.
MARKETING_VERSION = $marketing_version
CURRENT_PROJECT_VERSION = $project_version
APP_BUILD_HASH = $hash
EOF
fi

if [[ "$EXPORT" -eq 1 ]]; then
  printf 'MARKETING_VERSION=%q\n' "$marketing_version"
  printf 'CURRENT_PROJECT_VERSION=%q\n' "$project_version"
  printf 'APP_BUILD_HASH=%q\n' "$hash"
fi
