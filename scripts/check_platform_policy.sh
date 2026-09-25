#!/usr/bin/env bash
# Platform policy gate (issue #1, binding project contract).
#
# Asserts:
# 1. Native Swift only: no Flutter / React Native / Expo / Kotlin Multiplatform /
#    .NET MAUI / Unity references in app sources, package sources, or project config.
# 2. Bundle identifier prefix: all bundle identifiers must use the registered
#    `com.infinityball.` prefix.
# 3. iPhone-only policy: TARGETED_DEVICE_FAMILY = 1 in every build configuration.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "--- 1. Prohibited cross-platform / hybrid framework grep gate ---"
PROHIBITED_PATTERNS=(
  'Flutter'
  'ReactNative'
  'React[[:space:]]+Native'
  'Expo'
  'KotlinMultiplatform'
  'Kotlin[[:space:]]+Multiplatform'
  '\.NET[[:space:]]+MAUI'
  '\bMaui\b'
  '\bMAUI\b'
  '\bUnity\b'
)

SEARCH_ROOTS=("WicketTally" "Packages" "WicketTally.xcodeproj" ".github")
prohibited_matches=""
for root in "${SEARCH_ROOTS[@]}"; do
  [ -d "$root" ] || continue
  for pat in "${PROHIBITED_PATTERNS[@]}"; do
    hits=$(grep -RnEI --exclude-dir=.build "$pat" "$root" 2>/dev/null || true)
    [ -n "$hits" ] && prohibited_matches+="$hits"$'\n'
  done
done

if [ -n "$prohibited_matches" ]; then
  echo "PLATFORM POLICY GATE FAILED — prohibited cross-platform references found:"
  printf '%s' "$prohibited_matches"
  exit 1
fi
echo "Prohibited cross-platform frameworks check: PASS"

echo "--- 2. Bundle identifier prefix gate ---"
# Check project.pbxproj
bad_bundle_ids=$(grep -E 'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;' WicketTally.xcodeproj/project.pbxproj \
  | grep -v 'com\.infinityball\.' || true)
if [ -n "$bad_bundle_ids" ]; then
  echo "BUNDLE ID GATE FAILED — non-com.infinityball bundle identifiers found in project:"
  echo "$bad_bundle_ids"
  exit 1
fi

# Check toolchain.json
toolchain_bundle_id=$(python3 -c "import json; print(json.load(open('toolchain.json'))['bundle_identifier'])")
if [[ "$toolchain_bundle_id" != com.infinityball.* ]]; then
  echo "BUNDLE ID GATE FAILED — toolchain.json bundle_identifier $toolchain_bundle_id does not start with com.infinityball."
  exit 1
fi
echo "Bundle identifier prefix check: PASS (com.infinityball.*)"

echo "--- 3. iPhone-only TARGETED_DEVICE_FAMILY gate ---"
grep -q "TARGETED_DEVICE_FAMILY = 1;" WicketTally.xcodeproj/project.pbxproj \
  || { echo "TARGETED_DEVICE_FAMILY = 1 missing from project"; exit 1; }

if grep -q "TARGETED_DEVICE_FAMILY = 1,2;" WicketTally.xcodeproj/project.pbxproj; then
  echo "iPad family (1,2) found — iPhone-only directive violated"
  exit 1
fi

bad_family=$(grep -E "TARGETED_DEVICE_FAMILY = [^1;]" WicketTally.xcodeproj/project.pbxproj || true)
if [ -n "$bad_family" ]; then
  echo "Non-iPhone TARGETED_DEVICE_FAMILY values found:"
  echo "$bad_family"
  exit 1
fi
family_count=$(grep -c "TARGETED_DEVICE_FAMILY = 1;" WicketTally.xcodeproj/project.pbxproj)
echo "iPhone-only TARGETED_DEVICE_FAMILY = 1: PASS ($family_count configurations verified)"
