#!/usr/bin/env bash
# Tests for lint-commit-subject.sh.
set -uo pipefail

LINT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lint-commit-subject.sh"
unset GITHUB_ACTIONS

pass=0
fail=0

# check EXPECTED_EXIT DESCRIPTION ARGS...
check() {
  local expected="$1" desc="$2"
  shift 2
  "$LINT" "$@" >/dev/null 2>&1
  local actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    pass=$((pass + 1))
    printf 'ok   - %s\n' "$desc"
  else
    fail=$((fail + 1))
    printf 'FAIL - %s (exit %d, expected %d)\n' "$desc" "$actual" "$expected"
  fi
}

# --- the rule ----------------------------------------------------------------
check 0 "plain type"               "feat: add break reminder"
check 0 "scope"                    "fix(timer): correct sleep handling"
check 0 "breaking marker"          "feat!: redesign overlay API"
check 0 "scope and breaking"       "refactor(menu bar)!: own the status item"
check 1 "unknown type"             "feature: add break reminder"
check 1 "missing space"            "fix:correct sleep handling"
check 1 "capitalised type"         "Fix: correct sleep handling"
check 1 "uppercase scope"          "fix(Timer): correct sleep handling"
check 1 "empty description"        "fix: "
check 1 "free text"                "WIP"
check 1 "one bad among good"       "feat: a" "oops" "fix: b"
check 2 "no subjects"
check 1 "-- keeps a subject from being an option" -- "-h"
check 1 "-- keeps a flag-like subject a subject"  -- "--git-workflow"

# --- git-generated subjects --------------------------------------------------
check 1 "fixup! strict"            "fixup! feat: add break reminder"
check 0 "fixup! --git-workflow"    --git-workflow "fixup! feat: add break reminder"
check 0 "squash! --git-workflow"   --git-workflow "squash! fix: x"
check 0 "amend! --git-workflow"    --git-workflow "amend! fix: x"
check 0 "Revert --git-workflow"    --git-workflow 'Revert "feat: add break reminder"'
check 0 "Merge --git-workflow"     --git-workflow "Merge branch 'main' into ci/x"
check 1 "free text --git-workflow" --git-workflow "WIP"

# --- --file (commit-msg hook input) --------------------------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf '# Please enter the commit message\n\nfix(timer): x\n\nbody\n' >"$tmp/ok"
check 0 "file: skips comments and blanks" --file "$tmp/ok"

printf 'WIP\n# comment\n' >"$tmp/bad"
check 1 "file: bad subject" --file "$tmp/bad"

printf '# only a comment\n\n' >"$tmp/empty"
check 0 "file: empty message left to git" --file "$tmp/empty"

printf 'fixup! fix: x\n' >"$tmp/fixup"
check 0 "file: fixup with --git-workflow" --git-workflow --file "$tmp/fixup"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
