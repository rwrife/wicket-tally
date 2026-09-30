#!/usr/bin/env bash
# Indica design-system token gate (issue #9).
#
# Enforces that every feature view consumes Indica tokens only — no
# hardcoded SwiftUI colour literals, including in newly added screens.
#
# Exit codes: 0 = clean, 1 = a feature view contains a hardcoded colour.
set -euo pipefail

cd "$(dirname "$0")/.."

# The root view is checked explicitly, including if the file goes missing.
ENFORCED=(
  "WicketTally/ContentView.swift"
)

# Every other feature view is discovered automatically below.

# The design system itself is the one place colours may be authored.
THEME_DIR="WicketTally/Theme"

# Hardcoded-colour signatures. `IndicaColor(hexRGB:)` is deliberately absent:
# it is only legal inside THEME_DIR, which is never scanned.
PATTERNS=(
  'Color\.(red|green|blue|orange|yellow|pink|purple|indigo|teal|mint|cyan|brown|gray|grey|black|white|primary|secondary)\b'
  'Color\(red:'
  'Color\(hexRGB:'
  'Color\(\.sRGB'
  'UIColor'
  '\.(foregroundStyle|foregroundColor|tint|background|fill|stroke|strokeBorder|shadow)\(\s*\.(red|green|blue|orange|yellow|pink|purple|indigo|teal|mint|cyan|brown|gray|grey|black|white|secondary|primary)\b'
)

scan() {
  local file="$1"
  local hits=""
  for pat in "${PATTERNS[@]}"; do
    local found
    found=$(grep -nE "$pat" "$file" 2>/dev/null || true)
    [ -n "$found" ] && hits+="$(printf '%s\n' "$found" | sed "s|^|  $file:|")"$'\n'
  done
  printf '%s' "$hits"
}

echo "--- Indica token gate: enforced views ---"
failed=0
for file in "${ENFORCED[@]}"; do
  if [ ! -f "$file" ]; then
    echo "MISSING enforced file: $file"
    failed=1
    continue
  fi
  hits=$(scan "$file")
  if [ -n "$hits" ]; then
    echo "FAIL $file uses hardcoded colours instead of Indica tokens:"
    printf '%s' "$hits"
    failed=1
  else
    echo "OK   $file (tokens only)"
  fi
done

echo
echo "--- Indica token gate: design system source ---"
if [ -d "$THEME_DIR" ]; then
  count=$(find "$THEME_DIR" -name '*.swift' | wc -l | tr -d ' ')
  echo "OK   $THEME_DIR ($count token source files, colour authoring allowed here)"
else
  echo "FAIL missing $THEME_DIR"
  failed=1
fi

echo
echo "--- Indica token gate: all feature views ---"
# Discover every SwiftUI feature view under WicketTally/, excluding the design
# system itself and anything already enforced above.
is_enforced() {
  local candidate="$1"
  for e in "${ENFORCED[@]}"; do
    [ "$e" = "$candidate" ] && return 0
  done
  return 1
}

clean_files=0
while IFS= read -r file; do
  case "$file" in
    "$THEME_DIR"/*) continue ;;
  esac
  is_enforced "$file" && continue
  # Only consider SwiftUI views, not view models or plain types.
  grep -qE '(: *View *\{|import SwiftUI)' "$file" 2>/dev/null || continue

  hits=$(scan "$file")
  n=$(printf '%s' "$hits" | grep -c . || true)
  if [ "$n" -eq 0 ]; then
    clean_files=$((clean_files + 1))
    echo "OK   $file (tokens only)"
  else
    failed=1
    echo "FAIL $file — $n hardcoded colour reference(s)"
    printf '%s\n' "${hits%$'\n'}"
  fi
done < <(find WicketTally -name '*.swift' | sort)

echo
echo "Feature views clean: $clean_files"

echo
if [ "$failed" -ne 0 ]; then
  echo "INDICA TOKEN GATE FAILED"
  exit 1
fi
echo "INDICA TOKEN GATE PASSED"
