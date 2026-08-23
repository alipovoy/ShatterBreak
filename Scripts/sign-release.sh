#!/usr/bin/env bash
set -euo pipefail

# Re-sign a built ShatterBreak.app with a stable identity, so the Screen Recording
# grant survives updates. Certificate setup, the three signing modes and the reasoning
# are in RELEASING.md — "Signing so permissions survive updates".
#
# Usage
# -----
#   Scripts/sign-release.sh path/to/ShatterBreak.app
#
# Environment:
#   SIGN_IDENTITY   codesign identity (default: "ShatterBreak Self-Signed").
#                   "-" is ad-hoc: not update-stable.
#   ENTITLEMENTS    entitlements plist (default: ShatterBreak/ShatterBreak.entitlements)
#   SIGN_OPTIONAL   when set, a missing identity is a no-op (exit 0) instead of an error.
#                   Used by the Xcode Archive post-action.
#   SIGN_TIMESTAMP  "none" to sign offline, or an http:// RFC3161 URL. Defaults to
#                   Apple's, so signing needs the network. Ignored for ad-hoc.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_PATH="${1:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:-ShatterBreak Self-Signed}"
ENTITLEMENTS="${ENTITLEMENTS:-$SRCROOT/ShatterBreak/ShatterBreak.entitlements}"

if [[ -z "$APP_PATH" ]]; then
  echo "error: missing path to .app bundle" >&2
  echo "usage: Scripts/sign-release.sh path/to/ShatterBreak.app" >&2
  exit 2
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: not a bundle: $APP_PATH" >&2
  exit 2
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "error: entitlements not found: $ENTITLEMENTS" >&2
  exit 2
fi

# Fail before signing: an unnoticed ad-hoc fallback here ships a build that looks fine
# and silently breaks the grant.
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  if ! security find-identity -v -p codesigning | grep -qF -- "$SIGN_IDENTITY"; then
    if [[ -n "${SIGN_OPTIONAL:-}" ]]; then
      echo "note: stable signing identity '$SIGN_IDENTITY' not found — skipping stable re-sign." >&2
      echo "      The app keeps its existing signature (issue #43)." >&2
      exit 0
    fi
    echo "error: code-signing identity not found in keychain: $SIGN_IDENTITY" >&2
    echo "       create it once (see RELEASING.md) or pass SIGN_IDENTITY=- for ad-hoc." >&2
    exit 1
  fi
else
  echo "warning: ad-hoc signing — the Screen Recording grant will NOT survive updates" >&2
fi

# Without a timestamp the signature expires with the certificate, dropping the grant
# from an installed build. Ad-hoc has no chain to stamp.
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  TIMESTAMP_ARG="--timestamp=none"
elif [[ -n "${SIGN_TIMESTAMP:-}" ]]; then
  # codesign reads any unknown value as a URL, so a typo fails as a network error.
  if [[ "$SIGN_TIMESTAMP" != "none" && "$SIGN_TIMESTAMP" != http://* ]]; then
    echo "error: SIGN_TIMESTAMP must be \"none\" or an http:// RFC3161 URL: $SIGN_TIMESTAMP" >&2
    exit 2
  fi
  TIMESTAMP_ARG="--timestamp=$SIGN_TIMESTAMP"
else
  TIMESTAMP_ARG="--timestamp"
fi

echo "Signing $APP_PATH"
echo "  identity:  $SIGN_IDENTITY"
echo "  timestamp: $TIMESTAMP_ARG"
# No --deep: nothing is nested in this bundle, and it is deprecated since macOS 13.
# Nested code added later must be signed inside-out; --verify --strict catches it.
codesign \
  --force \
  --options runtime \
  "$TIMESTAMP_ARG" \
  --sign "$SIGN_IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  "$APP_PATH"

echo
echo "Verifying signature…"
codesign --verify --strict --verbose=2 "$APP_PATH"

if [[ "$SIGN_IDENTITY" != "-" && "$TIMESTAMP_ARG" != "--timestamp=none" ]]; then
  echo
  # codesign writes this to stderr; keep its status so a read failure is not reported
  # as a missing timestamp.
  if SIGNATURE_INFO="$(codesign --display --verbose=2 "$APP_PATH" 2>&1)"; then
    if [[ "$SIGNATURE_INFO" == *$'\n'Timestamp=* ]]; then
      echo "Secure timestamp: present (signature outlives the certificate)."
    else
      echo "warning: no secure timestamp — this signature stops validating when the" >&2
      echo "         signing certificate expires, dropping the Screen Recording grant." >&2
    fi
  else
    echo "warning: could not read the signature back:" >&2
    echo "$SIGNATURE_INFO" >&2
  fi
fi

echo
echo "Designated Requirement (stable across versions if the identity is reused):"
# Ad-hoc carries no requirements blob, so codesign comments the implicit rule out
# ("# designated => cdhash H\"…\""); a real identity prints it uncommented.
if ! REQUIREMENTS="$(codesign --display --requirements - "$APP_PATH" 2>&1)"; then
  echo "error: could not read the designated requirement:" >&2
  echo "$REQUIREMENTS" >&2
  exit 1
fi
DR="$(sed -n 's/^designated => //p' <<<"$REQUIREMENTS")"
if [[ -n "$DR" ]]; then
  echo "  $DR"
else
  echo "  (implicit — ad-hoc signature; the DR is the cdhash and changes every build)"
  sed -n 's/^# designated => /  /p' <<<"$REQUIREMENTS"
fi
