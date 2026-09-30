#!/usr/bin/env bash
set -euo pipefail

mkdir -p evidence/diagnostics
trap 'status=$?; if [ "$status" -ne 0 ]; then python3 scripts/run_bounded.py 30 evidence/diagnostics/available-devices.txt xcrun simctl list devices available || true; python3 scripts/run_bounded.py 60 evidence/diagnostics/simctl-diagnose.log xcrun simctl diagnose -f evidence/diagnostics || true; fi; exit "$status"' EXIT

python3 scripts/run_bounded.py 30 evidence/diagnostics/devices.json xcrun simctl list devices available -j || {
    cat evidence/diagnostics/devices.json
    exit 1
}
python3 - <<'PY' > evidence/selected-device.txt
import json, re

data = json.load(open('evidence/diagnostics/devices.json'))
candidates = []
for runtime, devices in data['devices'].items():
    if not re.search(r'iOS[-.]26(?:[-.]|$)', runtime):
        continue
    for device in devices:
        name = device['name']
        if not name.startswith('iPhone') or not device.get('isAvailable', False):
            continue
        # Logical display dimensions for supported compact iPhones.
        if 'SE' in name: width, height = 375, 667
        elif 'mini' in name: width, height = 375, 812
        elif re.search(r'\b(16e|17e)\b', name): width, height = 390, 844
        elif 'Air' in name: width, height = 420, 912
        elif '14 Pro' in name: width, height = 393, 852
        elif '16 Pro' in name: width, height = 402, 874
        elif re.search(r'\b(12|13|14)\b', name): width, height = 390, 844
        elif re.search(r'\b(15|16)\b', name): width, height = 393, 852
        elif re.search(r'\b17\b', name): width, height = 402, 874
        else: width, height = 999, 999
        if 'Plus' in name or 'Max' in name: width += 100
        candidates.append((width, height, name, device['udid'], runtime, device['state']))
if not candidates:
    raise SystemExit('No available iOS 26 iPhone simulator under the pinned Xcode')
width, height, name, udid, runtime, state = min(candidates)
print(udid)
print(state)
print(f'{name} ({width}x{height} pt class), {runtime}', file=__import__('sys').stderr)
PY
device_id=$(head -1 evidence/selected-device.txt)
echo "Selected simulator: $device_id"

if [ "$(sed -n '2p' evidence/selected-device.txt)" != "Booted" ]; then
    python3 scripts/run_bounded.py 180 evidence/diagnostics/boot.log xcrun simctl boot "$device_id" || {
        cat evidence/diagnostics/boot.log
        exit 1
    }
fi
python3 scripts/run_bounded.py 300 evidence/diagnostics/bootstatus.log xcrun simctl bootstatus "$device_id" -b || {
    cat evidence/diagnostics/bootstatus.log
    exit 1
}

xcodebuild -project WicketTally.xcodeproj -scheme WicketTally \
  -destination "platform=iOS Simulator,id=$device_id" \
  -configuration Debug -derivedDataPath DerivedData \
  -resultBundlePath evidence/ScorerUITests.xcresult \
  CODE_SIGNING_ALLOWED=NO test > evidence/diagnostics/xcodebuild-test.log 2>&1 || {
    tail -100 evidence/diagnostics/xcodebuild-test.log
    exit 1
}
xcrun xcresulttool export attachments --path evidence/ScorerUITests.xcresult \
  --output-path evidence/screenshots > evidence/diagnostics/attachments.log 2>&1 || {
    cat evidence/diagnostics/attachments.log
    exit 1
}
test -n "$(find evidence/screenshots -type f -print -quit)" || {
    echo 'No UI test screenshot attachments were exported'
    exit 1
}
