#!/usr/bin/env bash
# Tests for compute-version.sh. Each baseline-dependent case runs in a throwaway
# git repo so tag history is deterministic and isolated from the real checkout.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPUTE="$SCRIPT_DIR/compute-version.sh"

pass=0
fail=0

# assert_eq DESCRIPTION EXPECTED ACTUAL
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass=$((pass + 1))
    printf 'ok   - %s\n' "$desc"
  else
    fail=$((fail + 1))
    printf 'FAIL - %s\n      expected: %q\n      actual:   %q\n' "$desc" "$expected" "$actual"
  fi
}

# assert_fail DESCRIPTION CMD...  — expects a non-zero exit
assert_fail() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail=$((fail + 1))
    printf 'FAIL - %s (expected non-zero exit)\n' "$desc"
  else
    pass=$((pass + 1))
    printf 'ok   - %s\n' "$desc"
  fi
}

# Spin up an isolated git repo seeded with the given tags (each on its own
# commit, tagged in order) and echo its path. Caller runs the script with cwd
# inside it; the script resolves its repo root from BASH_SOURCE, so copy it in.
make_repo() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/Scripts"
  cp "$COMPUTE" "$dir/Scripts/compute-version.sh"
  (
    cd "$dir"
    git init -q
    git config user.email t@t.test
    git config user.name test
    git config commit.gpgsign false
    git commit -q --allow-empty -m "chore: init"
    for tag in "$@"; do
      git commit -q --allow-empty -m "feat: $tag"
      git tag -a "$tag" -m "$tag"
    done
  )
  echo "$dir"
}

run() { "$1/Scripts/compute-version.sh" "${@:2}"; }

# Echo just the MARKETING_VERSION from a --export run (modes ci-test/ci-release
# emit nothing on stdout otherwise). Args: COMPUTE_PATH MODE-ARGS...
marketing() {
  local compute="$1"
  shift
  "$compute" "$@" --export | sed -n 's/^MARKETING_VERSION=//p'
}

export GITHUB_RUN_NUMBER=7

# --- Strict release path (no regression) ------------------------------------
out="$(marketing "$COMPUTE" --mode ci-release --tag v1.4.5)"
assert_eq "ci-release strict vX.Y.Z -> marketing string" "1.4.5" "$out"

# --- Pre-release release build ----------------------------------------------
out="$(marketing "$COMPUTE" --mode ci-release --tag v1.3.0-rc.1)"
assert_eq "ci-release v1.3.0-rc.1 -> 1.3.0-rc.1" "1.3.0-rc.1" "$out"

out="$(marketing "$COMPUTE" --mode ci-release --tag v2.0.0-beta.2)"
assert_eq "ci-release v2.0.0-beta.2 -> 2.0.0-beta.2" "2.0.0-beta.2" "$out"

# --- ci-release rejects malformed tags --------------------------------------
assert_fail "ci-release rejects trailing hyphen" \
  env GITHUB_RUN_NUMBER=7 "$COMPUTE" --mode ci-release --tag v1.3.0-
assert_fail "ci-release rejects empty pre-release identifier" \
  env GITHUB_RUN_NUMBER=7 "$COMPUTE" --mode ci-release --tag v1.3.0-rc..1
assert_fail "ci-release rejects missing v prefix" \
  env GITHUB_RUN_NUMBER=7 "$COMPUTE" --mode ci-release --tag 1.3.0-rc.1

# --- Pre-release vs final precedence (baseline selection) -------------------
# A pre-release tag must NOT become a baseline: the final release still wins,
# and dev/CI builds never report the pre-release as the last released version.
repo="$(make_repo v1.2.3 v1.3.0-rc.1)"
out="$(marketing "$repo/Scripts/compute-version.sh" --mode ci-test)"
assert_eq "pre-release does not override last final release" "1.2.3-test" "$out"
rm -rf "$repo"

repo="$(make_repo v1.3.0-rc.1 v1.3.0)"
out="$(marketing "$repo/Scripts/compute-version.sh" --mode ci-test)"
assert_eq "final release after its pre-release becomes baseline" "1.3.0-test" "$out"
rm -rf "$repo"

# A repo whose only tag is a pre-release falls back to DEFAULT_SEMVER baseline.
repo="$(make_repo v1.3.0-rc.1)"
out="$(marketing "$repo/Scripts/compute-version.sh" --mode ci-test)"
assert_eq "lone pre-release tag falls back to default baseline" "1.0.0-test" "$out"
rm -rf "$repo"

# --- next-tag --pre ----------------------------------------------------------
repo="$(make_repo v1.2.3)"
out="$(run "$repo" --mode next-tag --bump minor --pre rc.1)"
assert_eq "next-tag --bump minor --pre rc.1" "v1.3.0-rc.1" "$out"

out="$(run "$repo" --mode next-tag --bump patch)"
assert_eq "next-tag --bump patch (no --pre unchanged)" "v1.2.4" "$out"

assert_fail "next-tag rejects invalid --pre" \
  run "$repo" --mode next-tag --pre "rc 1"
rm -rf "$repo"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
