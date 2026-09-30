#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 6 ]; then
  echo "usage: $0 ARCHIVE EXPECTED_BUNDLE_ID EXPECTED_FAMILY EXPECTED_VERSION EXPECTED_BUILD EXPECTED_TEAM" >&2
  exit 2
fi

archive=$1
expected_bundle_id=$2
expected_family=$3
expected_version=$4
expected_build=$5
expected_team=$6
app="$archive/Products/Applications/WicketTally.app"
info_plist="$app/Info.plist"

[ -d "$app" ] || {
  echo "FAIL: archived app not found at $app" >&2
  exit 1
}
[ -f "$info_plist" ] || {
  echo "FAIL: archived Info.plist not found" >&2
  exit 1
}

python3 - \
  "$info_plist" \
  "$expected_bundle_id" \
  "$expected_family" \
  "$expected_version" \
  "$expected_build" <<'PY'
import plistlib
import sys
from pathlib import Path

plist_path, bundle_id, family, version, build = sys.argv[1:]
with Path(plist_path).open("rb") as handle:
    info = plistlib.load(handle)

expected_family = [int(family)]
checks = {
    "CFBundleIdentifier": bundle_id,
    "UIDeviceFamily": expected_family,
    "CFBundleShortVersionString": version,
    "CFBundleVersion": build,
}
for key, expected in checks.items():
    actual = info.get(key)
    if actual != expected:
        raise SystemExit(f"FAIL: {key} expected {expected!r}, got {actual!r}")
PY

codesign --verify --deep --strict "$app"
signature_details=$(codesign -dvvv "$app" 2>&1)
if printf '%s\n' "$signature_details" | grep -q '^Signature=adhoc$'; then
  echo "FAIL: archive has an ad hoc signature, not an App Store distribution signature" >&2
  exit 1
fi
actual_team=$(printf '%s\n' "$signature_details" | awk -F= '/^TeamIdentifier=/ { print $2 }')
[ -n "$actual_team" ] && [ "$actual_team" = "$expected_team" ] || {
  echo "FAIL: archive signing team does not match ASC_TEAM_ID" >&2
  exit 1
}

echo "Signed archive verification: PASS"
echo "Bundle identifier: $expected_bundle_id"
echo "UIDeviceFamily: [$expected_family]"
echo "Version/build: $expected_version ($expected_build)"
