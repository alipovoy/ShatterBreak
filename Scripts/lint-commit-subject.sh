#!/usr/bin/env bash
# The Conventional Commits rule for commit subjects and PR titles, shared by the
# commit-msg hook (.githooks/commit-msg) and the PR Conventions workflow.
set -uo pipefail

TYPES="feat fix perf refactor docs style test build ci chore revert"
# <type>[optional (scope)][optional !]: <description>
PATTERN="^(${TYPES// /|})(\([a-z0-9 ._-]+\))?!?: [^[:space:]][^[:cntrl:]]*$"

usage() {
  cat <<'EOF'
Usage: lint-commit-subject.sh [--] SUBJECT...
       lint-commit-subject.sh --file MESSAGE_FILE

Checks each SUBJECT against Conventional Commits and exits 1 if any fails, 2 on
bad usage. Pass -- before untrusted subjects so one starting with - is not read
as an option.

  --file PATH  Read the subject from a commit message file, as a commit-msg hook
               receives it: the first line left after git's own comment cleanup.
EOF
}

file=""
case "${1:-}" in
  --file) file="${2:-}"; [[ -n "$file" && $# -eq 2 ]] || { usage >&2; exit 2; } ;;
  -h|--help) usage; exit 0 ;;
  --) shift ;;
esac

if [[ -n "$file" ]]; then
  [[ -f "$file" && -r "$file" ]] || { echo "error: cannot read $file" >&2; exit 2; }
  # Cut `commit -v`'s diff at the scissors line, then let git strip comments
  # with the repo's own comment character.
  subject="$(sed '/ >8 /,$d' "$file" | git stripspace --strip-comments | head -n 1)"
  # An empty message is git's to reject, with its own clearer error.
  [[ -z "$subject" ]] && exit 0
  set -- "$subject"
fi

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 2
fi

failed=0
for subject in "$@"; do
  if [[ "$subject" =~ $PATTERN ]]; then
    echo "OK:   $subject"
  else
    failed=1
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
      echo "::error::Not a Conventional Commit: $subject"
    else
      echo "FAIL: $subject" >&2
    fi
  fi
done

if [[ "$failed" -ne 0 ]]; then
  cat >&2 <<EOF

Expected:  <type>[(scope)][!]: <description>
Types:     $TYPES
Scope:     lowercase letters, digits, space . _ -
Examples:  feat: add break reminder
           fix(timer): correct sleep handling
           feat!: redesign overlay API
EOF
  exit 1
fi
