#!/usr/bin/env bash
set -euo pipefail

# Sign a built ShatterBreak.app with a STABLE code-signing identity so the macOS
# Screen Recording permission survives app updates.
#
# Why this exists
# ---------------
# macOS ties the Screen Recording (TCC) grant to the app's code-signing
# Designated Requirement (DR). Ad-hoc signatures (`codesign --sign -`) have a DR
# that is just the binary's cdhash, which changes on every build — so every
# updated version looks like a brand-new app and the user must re-add it under
# System Settings > Privacy & Security > Screen Recording.
#
# Signing with a self-signed certificate that you create once and REUSE gives a
# stable DR (`identifier "<bundle id>" and certificate leaf = H"<cert hash>"`).
# Because that requirement is identical across versions, TCC keeps the grant when
# the app is replaced (at most a one-click "ShatterBreak was updated — keep
# allowing?" prompt). No paid Apple Developer account and no Apple secrets are
# required; the app is still un-notarized, so the existing
# `xattr -dr com.apple.quarantine` step on first download is unchanged.
#
# One-time setup (create the reusable certificate)
# ------------------------------------------------
# Keychain Access > Certificate Assistant > Create a Certificate…
#   Name:              ShatterBreak Self-Signed   (must match SIGN_IDENTITY)
#   Identity Type:     Self Signed Root
#   Certificate Type:  Code Signing
# Leave it in the login keychain. Never delete or recreate it, or the DR (and the
# permission grant) changes. Back it up by exporting a password-protected .p12.
#
# Usage
# -----
#   Scripts/sign-release.sh path/to/ShatterBreak.app
#
# Environment:
#   SIGN_IDENTITY   codesign identity to use (default: "ShatterBreak Self-Signed").
#                   Set to "-" to fall back to ad-hoc signing (NOT update-stable).
#   ENTITLEMENTS    entitlements plist (default: ShatterBreak/ShatterBreak.entitlements)
#   SIGN_OPTIONAL   when set (any value), a missing identity is a no-op (exit 0)
#                   instead of an error. Used by the Xcode Archive post-action so a
#                   machine without the cert (or CI) still archives cleanly.

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

# Guard against the silent failure mode: signing ad-hoc here would build, upload,
# and look fine — but reintroduce the exact bug this script exists to fix.
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  if ! security find-identity -v -p codesigning | grep -qF "$SIGN_IDENTITY"; then
    if [[ -n "${SIGN_OPTIONAL:-}" ]]; then
      echo "note: stable signing identity '$SIGN_IDENTITY' not found — skipping stable re-sign." >&2
      echo "      The app keeps its existing signature; the Screen Recording grant will NOT" >&2
      echo "      survive updates until it is signed with a stable identity (issue #43)." >&2
      exit 0
    fi
    echo "error: code-signing identity not found in keychain: $SIGN_IDENTITY" >&2
    echo "       create it once (see header of this script) or pass SIGN_IDENTITY=-" >&2
    echo "       to ad-hoc sign (which does NOT survive updates)." >&2
    exit 1
  fi
else
  echo "warning: ad-hoc signing — the Screen Recording grant will NOT survive updates" >&2
fi

echo "Signing $APP_PATH"
echo "  identity: $SIGN_IDENTITY"
codesign \
  --force \
  --deep \
  --options runtime \
  --sign "$SIGN_IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  "$APP_PATH"

echo
echo "Verifying signature…"
codesign --verify --strict --verbose=2 "$APP_PATH"

echo
echo "Designated Requirement (stable across versions if the identity is reused):"
DR="$(codesign --display --requirements - "$APP_PATH" 2>&1 | sed -n 's/^designated => //p')"
if [[ -n "$DR" ]]; then
  echo "  $DR"
else
  echo "  (none — ad-hoc signature; DR is the cdhash and changes every build)"
fi
