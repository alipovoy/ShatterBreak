#!/usr/bin/env bash
set -euo pipefail

# Re-sign a built ShatterBreak.app so the Screen Recording grant survives updates.
# Certificate setup and reasoning: RELEASING.md — "Signing so permissions survive updates".
#
#   Scripts/sign-release.sh path/to/ShatterBreak.app           self-signed certificate
#   Scripts/sign-release.sh --adhoc path/to/ShatterBreak.app   ad-hoc, not update-stable

IDENTITY="ShatterBreak Self-Signed"
SRCROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTITLEMENTS="$SRCROOT/ShatterBreak/ShatterBreak.entitlements"

ADHOC=""
if [[ "${1:-}" == "--adhoc" ]]; then
  ADHOC=1
  shift
fi
APP_PATH="${1:-}"

if [[ -z "$APP_PATH" ]]; then
  echo "usage: Scripts/sign-release.sh [--adhoc] path/to/ShatterBreak.app" >&2
  exit 2
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: not a bundle: $APP_PATH" >&2
  exit 2
fi

if [[ -n "$ADHOC" ]]; then
  echo "warning: ad-hoc signing — the Screen Recording grant will NOT survive updates" >&2
  SIGN_ARGS=(--sign - --timestamp=none)
else
  # Without -v an expired certificate is listed too, which tells it apart from a missing one.
  listed="$(security find-identity -p codesigning | grep -F -- "\"$IDENTITY\"" || true)"
  usable="$(security find-identity -v -p codesigning | grep -F -- "\"$IDENTITY\"" || true)"
  if [[ -z "$listed" ]]; then
    echo "error: no code-signing certificate named '$IDENTITY' (see RELEASING.md)" >&2
    exit 1
  elif [[ -z "$usable" ]]; then
    echo "error: certificate '$IDENTITY' is not valid (expired or untrusted):" >&2
    echo "$listed" >&2
    exit 1
  elif [[ "$(wc -l <<<"$usable")" -gt 1 ]]; then
    echo "error: several certificates named '$IDENTITY'; delete the old ones:" >&2
    echo "$usable" >&2
    exit 1
  fi
  # The secure timestamp keeps the signature valid after the certificate expires.
  SIGN_ARGS=(--sign "$IDENTITY" --timestamp)
fi

echo "Signing $APP_PATH"
# No --deep: nothing is nested in this bundle. Nested code added later must be signed
# inside-out; --verify --strict catches it.
codesign --force --options runtime "${SIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"

echo
echo "Designated Requirement:"
# Ad-hoc carries no requirements blob, so codesign comments the implicit rule out.
codesign --display --requirements - "$APP_PATH" 2>&1 | sed -n 's/^# *designated => /  /p; s/^designated => /  /p'
