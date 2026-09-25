#!/usr/bin/env bash
# Fail closed unless WicketKit pure-domain sources meet the issue #2 coverage floor.
set -euo pipefail

cd "$(dirname "$0")/../Packages/WicketKit"

minimum="${WICKETKIT_COVERAGE_MINIMUM:-90}"
binary=$(find .build -type f -name 'WicketKitPackageTests.xctest' -print -quit)
profile=$(find .build -path '*/debug/codecov/default.profdata' -print -quit)

if [ -z "$binary" ] || [ -z "$profile" ]; then
  echo "WicketKit coverage gate: FAIL (run swift test --enable-code-coverage first)"
  exit 1
fi

report=$(llvm-cov report "$binary" -instr-profile "$profile" -sources Sources/WicketKit)
printf '%s\n' "$report"

line_coverage=$(printf '%s\n' "$report" | awk '$1 == "TOTAL" { gsub("%", "", $10); print $10 }')
if [ -z "$line_coverage" ]; then
  echo "WicketKit coverage gate: FAIL (could not parse TOTAL line coverage)"
  exit 1
fi

if ! awk -v actual="$line_coverage" -v required="$minimum" 'BEGIN { exit !(actual + 0 >= required + 0) }'; then
  echo "WicketKit coverage gate: FAIL (${line_coverage}% < ${minimum}% line coverage)"
  exit 1
fi

echo "WicketKit coverage gate: PASS (${line_coverage}% >= ${minimum}% line coverage)"
