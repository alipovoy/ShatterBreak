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

# Marketing semver for an explicit release tag. The tag may be vMAJOR.MINOR
# (a baseline whose patch starts at 0 and climbs afterwards) or a fully pinned
# vMAJOR.MINOR.PATCH. The leading `v` is required: the baseline lookup below
# only matches `v*` tags, so a tag without it (e.g. `1.4.5`) would be silently
# ignored afterwards and dev versions would regress.
resolve_release_semver() {
  if [[ -z "$TAG" ]]; then
    echo "ci-release requires --tag" >&2
    exit 1
  fi
  if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Invalid release tag '$TAG'; expected vMAJOR.MINOR or vMAJOR.MINOR.PATCH (e.g. v1.2 or v1.4.5)." >&2
    echo "Get the right tag with: Scripts/compute-version.sh --mode next-tag" >&2
    exit 1
  fi
  local semver
  semver="$(strip_v_prefix "$TAG")"
  # Normalize a two-part baseline (1.2) to a full three-component version (1.2.0)
  # so the release build matches what the bump logic produces from here on.
  if [[ "$semver" =~ ^[0-9]+\.[0-9]+$ ]]; then
    semver="${semver}.0"
  fi
  echo "$semver"
}

# Highest-version `v*` tag reachable from HEAD, or empty if none. We pick by
# version order rather than `git describe`'s topological "nearest", because two
# tags can sit on the same commit (e.g. v1.2.3 then v1.4) and `git describe`'s
# tie-break between them is unreliable. Highest-reachable is deterministic and,
# since versions only move up, always the latest baseline.
latest_baseline_tag() {
  git tag --merged HEAD --sort=-v:refname --list 'v[0-9]*' 2>/dev/null | head -n1
}

# The baseline version: the latest vX.Y[.Z] tag normalized to three components,
# or DEFAULT_SEMVER when no tag exists. A two-part baseline (v1.2 -> 1.2.0) gets
# a `.0` patch so it lines up with what the bump logic produces from here on.
baseline_semver() {
  local tag base
  tag="$(latest_baseline_tag)"
  if [[ -z "$tag" ]]; then
    echo "$DEFAULT_SEMVER"
    return
  fi
  base="$(strip_v_prefix "$tag")"
  if [[ "$base" =~ ^[0-9]+\.[0-9]+$ ]]; then
    base="${base}.0"
  fi
  echo "$base"
}

# Inspect the Conventional Commit messages in a git range and echo the implied
# SemVer bump: major | minor | patch | none. Any `!` marker (e.g. `feat!:`) or a
# `BREAKING CHANGE` footer wins as major; a `feat:` subject is minor; any other
# commits are patch; an empty range is none. We squash-merge, so each commit
# subject is the PR title and drives the decision.
detect_bump() {
  local range="$1" subjects bodies
  subjects="$(git log --format='%s' "$range" 2>/dev/null)"
  bodies="$(git log --format='%B' "$range" 2>/dev/null)"
  if [[ -z "$subjects" ]]; then
    echo "none"
    return
  fi
  if printf '%s\n' "$subjects" | grep -qE '^[a-z]+(\([^)]+\))?!:' \
    || printf '%s\n' "$bodies" | grep -qE 'BREAKING[ -]CHANGE'; then
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
  major="${major:-1}"
  minor="${minor:-0}"
  patch="${patch:-0}"
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
