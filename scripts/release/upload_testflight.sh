#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 ARCHIVE_PATH API_KEY_PATH" >&2
  exit 2
fi

archive_path=$1
api_key_path=$2
script_directory=$(cd "$(dirname "$0")" && pwd)
options_path="$RUNNER_TEMP/app-store-upload-options.plist"
trap 'rm -f "$options_path"' EXIT

cat > "$options_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>upload</string>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>${ASC_TEAM_ID}</string>
  <key>uploadMethod</key>
  <string>app-store-connect</string>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
PLIST
chmod 600 "$options_path"

"$script_directory/run_secure.sh" "$RUNNER_TEMP/upload.log" -- \
  xcodebuild -quiet \
    -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$RUNNER_TEMP/WicketTallyTestFlightExport" \
    -exportOptionsPlist "$options_path" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$api_key_path" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
