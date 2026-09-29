#!/usr/bin/env bash
# Tests for sign-release.sh. Needs no certificate: only the ad-hoc path signs.
set -uo pipefail

SIGN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sign-release.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

APP="$WORK/Test.app"
mkdir -p "$APP/Contents/MacOS"
cp /usr/bin/true "$APP/Contents/MacOS/Test"
cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Test</string>
<key>CFBundleIdentifier</key><string>dev.test</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST

pass=0
fail=0

# check EXPECTED_EXIT DESCRIPTION ARGS...  (output stays in $OUTPUT)
check() {
  local expected="$1" desc="$2"
  shift 2
  OUTPUT="$("$SIGN" "$@" 2>&1)"
  local actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    pass=$((pass + 1))
    printf 'ok   - %s\n' "$desc"
  else
    fail=$((fail + 1))
    printf 'FAIL - %s (exit %d, expected %d)\n%s\n' "$desc" "$actual" "$expected" "$OUTPUT"
  fi
}

check 2 "no arguments"
check 2 "missing bundle" "$WORK/Nope.app"
check 2 "--adhoc without a bundle" --adhoc

check 0 "ad-hoc signs" --adhoc "$APP"
if [[ "$OUTPUT" == *cdhash* ]]; then
  pass=$((pass + 1))
  echo "ok   - ad-hoc reports a cdhash requirement"
else
  fail=$((fail + 1))
  printf 'FAIL - ad-hoc reports a cdhash requirement\n%s\n' "$OUTPUT"
fi

if security find-identity -p codesigning | grep -qF '"ShatterBreak Self-Signed"'; then
  echo "skip - missing certificate (one is installed)"
else
  check 1 "missing certificate fails" "$APP"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
