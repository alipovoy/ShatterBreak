#!/usr/bin/env bash
set -euo pipefail

DEFAULT_SEMVER="1.0.0"
MODE=""
TAG=""
BUMP=""
PRE=""
WRITE_XCCONFIG=""
EXPORT=0

# SemVer §9 pre-release identifier: one or more dot-separated identifiers, each a
# non-empty run of ASCII alphanumerics and hyphens (e.g. rc.1, beta, alpha.2).
PRERELEASE_RE='[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*'

usage() {
  cat <<'EOF'
Usage: compute-version.sh --mode MODE [options]

Modes:
  local-auto    Detect suffix from Xcode build context (dev/test/local)
  ci-test       CI PR/push: last-release semver with -test suffix
  ci-release    CI release: semver taken verbatim from the release tag
                (accepts a SemVer pre-release tag, e.g. v1.3.0-rc.1)
  next-tag      Print the git tag to create for the next release, then exit

Versioning:
  Dev and CI builds report the LAST released version — the latest vX.Y.Z tag
  (or 1.0.0 before any tag) — so the version stays stable as PRs land on main; it
  does not move until you cut a release.

  The bump happens only at release time. `next-tag` derives it from the
  Conventional Commit subjects merged since the latest tag: `feat:` bumps the
  minor, `fix:`/`perf:`/other types bump the patch, and a `!` marker or
  `BREAKING CHANGE` footer bumps the major. Creating that vX.Y.Z tag becomes the
  new baseline that dev/CI builds then report.

Options:
  --tag TAG             Release tag (e.g. v1.0.0 or v1.3.0-rc.1); used with
                        ci-release
  --bump LEVEL          For next-tag: force patch, minor, or major instead of
                        the auto-detected bump
  --pre IDENTIFIER      For next-tag: append a SemVer pre-release identifier to
                        the computed tag (e.g. --pre rc.1 -> v1.3.0-rc.1)
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
    --pre)
      PRE="$2"
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
# vMAJOR.MINOR.PATCH, optionally followed by a SemVer §9 pre-release identifier
# (e.g. v1.3.0-rc.1, v2.0.0-beta.2). The leading `v` is required: the baseline
# lookup below only matches `v*` tags, so a tag without it (e.g. `1.4.5`) would be
# silently ignored afterwards and dev versions would regress.
#
# A pre-release tag passes through verbatim as the marketing version (1.3.0-rc.1)
# but is intentionally NOT a baseline (see latest_baseline_tag): it never raises
# the version that dev/CI builds report, so its final release (v1.3.0) still wins.
resolve_release_semver() {
  if [[ -z "$TAG" ]]; then
    echo "ci-release requires --tag" >&2
    exit 1
  fi
  if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-${PRERELEASE_RE})?$ ]]; then
    echo "Invalid release tag '$TAG'; expected vMAJOR.MINOR.PATCH or a SemVer" >&2
    echo "pre-release (e.g. v1.4.5 or v1.3.0-rc.1)." >&2
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

# Marketing semver for the NEXT release tag. X.Y.Z come from the latest vX.Y.Z
# tag; the bump is derived from the Conventional Commit messages merged since
# that tag. Before the first tag exists, the next release is simply
# DEFAULT_SEMVER. Only `next-tag` uses this — dev/CI builds report the baseline
# (the last release) so the displayed version does not move as PRs land.
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
    marketing_version="$(baseline_semver)-${suffix}"
    project_version="$(git rev-list --count HEAD)"
    ;;
  ci-test)
    marketing_version="$(baseline_semver)-test"
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
    # with --bump it is forced relative to that tag's baseline. An optional --pre
    # appends a SemVer pre-release identifier (e.g. --pre rc.1 -> v1.3.0-rc.1).
    if [[ -z "$BUMP" ]]; then
      next_semver="$(resolve_next_semver)"
    else
      case "$BUMP" in
        patch | minor | major)
          next_semver="$(apply_bump "$(baseline_semver)" "$BUMP")"
          ;;
        *)
          echo "Unknown --bump: $BUMP (expected patch, minor, or major)" >&2
          exit 1
          ;;
      esac
    fi
    if [[ -n "$PRE" ]]; then
      if [[ ! "$PRE" =~ ^${PRERELEASE_RE}$ ]]; then
        echo "Invalid --pre '$PRE'; expected dot-separated SemVer identifiers" >&2
        echo "of ASCII alphanumerics and hyphens (e.g. rc.1, beta, alpha.2)." >&2
        exit 1
      fi
      next_semver="${next_semver}-${PRE}"
    fi
    echo "v${next_semver}"
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
