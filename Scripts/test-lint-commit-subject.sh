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
check 0 "plain type"             "feat: add break reminder"
check 0 "scope"                  "fix(timer): correct sleep handling"
check 0 "breaking marker"        "feat!: redesign overlay API"
check 0 "scope and breaking"     "refactor(menu bar)!: own the status item"
check 0 "revert type"            'revert: "feat: add break reminder"'
check 1 "unknown type"           "feature: add break reminder"
check 1 "missing space"          "fix:correct sleep handling"
check 1 "capitalised type"       "Fix: correct sleep handling"
check 1 "uppercase scope"        "fix(Timer): correct sleep handling"
check 1 "empty description"      "fix: "
check 1 "blank description"      "fix:   "
check 1 "free text"              "WIP"
check 1 "one bad among good"     "feat: a" "oops" "fix: b"
check 1 "second line is ignored" -- $'WIP\nfix: x'
check 1 "no trailing lines"      -- $'fix: x\nWIP'

# --- git-generated subjects are held to the same rule ------------------------
check 1 "fixup!"                 "fixup! feat: add break reminder"
check 1 "Revert"                 'Revert "feat: add break reminder"'
check 1 "Reapply"                'Reapply "feat: add break reminder"'
check 1 "Merge"                  "Merge branch 'main' into ci/x"

# --- usage -------------------------------------------------------------------
check 2 "no subjects"
check 1 "-- keeps a subject from being an option" -- "-h"
check 1 "-- keeps --file a subject"               -- "--file"
check 2 "--file without a path"                   --file
check 2 "--file with extra arguments"             --file x "WIP"
check 2 "--file on a missing file"                --file /nonexistent

# --- --file (commit-msg hook input) ------------------------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf '# Please enter the commit message\n\nfix(timer): x\n\nbody\n' >"$tmp/ok"
check 0 "file: skips comments and blanks" --file "$tmp/ok"

printf 'WIP\n# comment\n' >"$tmp/bad"
check 1 "file: bad subject" --file "$tmp/bad"

printf '# only a comment\n\n' >"$tmp/empty"
check 0 "file: empty message left to git" --file "$tmp/empty"

printf '\n# ------------------------ >8 ------------------------\n# Do not modify.\ndiff --git a/a b/a\n' >"$tmp/verbose-empty"
check 0 "file: empty commit -v message left to git" --file "$tmp/verbose-empty"

printf 'fix: x\n# ------------------------ >8 ------------------------\ndiff --git a/a b/a\n' >"$tmp/verbose"
check 0 "file: commit -v diff ignored" --file "$tmp/verbose"

printf 'fix:  \n' >"$tmp/trailing"
check 1 "file: trailing spaces stripped as git will" --file "$tmp/trailing"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
