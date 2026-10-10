#!/bin/bash
set -euo pipefail
JR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$JR_ROOT"
if [ -d /Applications/Xcode.app ]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
if ! xcodebuild -version >/dev/null 2>&1; then
  echo 'Full Xcode is required; complete scripts/bootstrap.sh first.' >&2; exit 1
fi
if [ -z "${TEAM_ID:-}" ]; then
  echo 'Set TEAM_ID to your Apple signing team ID, or choose a team and Run in Xcode.' >&2; exit 1
fi
if [ ! -d iOS/JaagteRaho.xcworkspace ]; then "$JR_ROOT/scripts/bootstrap.sh"; fi
if [ -z "${DEVICE_ID:-}" ]; then
  if command -v idevice_id >/dev/null 2>&1; then DEVICE_ID="$(idevice_id -l | head -n 1)"; fi
fi
if [ -z "${DEVICE_ID:-}" ]; then
  echo 'Connect and unlock one trusted iPhone, then set DEVICE_ID from xcrun devicectl list devices.' >&2; exit 1
fi
xcodebuild -workspace iOS/JaagteRaho.xcworkspace -scheme JaagteRaho -configuration Debug \
  -destination "id=$DEVICE_ID" -derivedDataPath build/DerivedData -jobs 2 COMPILER_INDEX_STORE_ENABLE=NO \
  DEVELOPMENT_TEAM="$TEAM_ID" -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
./scripts/check-bundle.sh build/DerivedData/Build/Products/Debug-iphoneos/JaagteRaho.app
xcrun devicectl device install app --device "$DEVICE_ID" build/DerivedData/Build/Products/Debug-iphoneos/JaagteRaho.app
xcrun devicectl device process launch --device "$DEVICE_ID" com.jaagteraho.driver
