#!/usr/bin/env bash
# The single source of the Conventional Commits rule, shared by the commit-msg
# hook (.githooks/commit-msg) and the PR Conventions workflow.
set -uo pipefail

TYPES="feat fix perf refactor docs style test build ci chore revert"
# <type>[optional (scope)][optional !]: <description>
PATTERN="^(${TYPES// /|})(\([a-z0-9 ._-]+\))?!?: .+"
# Subjects git writes itself: `commit --fixup/--squash`, `revert`, `merge`.
GIT_WORKFLOW_PATTERN='^((fixup|squash|amend)! |Revert "|Merge )'

usage() {
  cat <<'EOF'
Usage: lint-commit-subject.sh [--git-workflow] SUBJECT...
       lint-commit-subject.sh [--git-workflow] --file MESSAGE_FILE

Checks each SUBJECT against Conventional Commits and exits non-zero if any fails.

  --git-workflow  Also accept subjects git generates itself (fixup!, squash!,
                  amend!, Revert "…", Merge …). For branch commits only — a PR
                  title becomes the squash commit on main and must be strict.
  --file PATH     Read the subject from a commit message file, as a commit-msg
                  hook receives it: the first line that is neither blank nor a
                  comment.
EOF
}

git_workflow=0
file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --git-workflow) git_workflow=1; shift ;;
    --file) file="${2:?--file needs a path}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

subjects=("$@")
if [[ -n "$file" ]]; then
  subject="$(grep -v -E '^[[:space:]]*(#|$)' "$file" | head -n 1)"
  # An empty message is git's to reject, with its own clearer error.
  [[ -z "$subject" ]] && exit 0
  subjects=("$subject")
fi

if [[ ${#subjects[@]} -eq 0 ]]; then
  usage >&2
  exit 2
fi

failed=0
for subject in "${subjects[@]}"; do
  if printf '%s' "$subject" | grep -qE "$PATTERN" ||
     { [[ "$git_workflow" -eq 1 ]] && printf '%s' "$subject" | grep -qE "$GIT_WORKFLOW_PATTERN"; }; then
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
