#!/bin/bash
set -euo pipefail
JR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$JR_ROOT"
if [ -d /Applications/Xcode.app ]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
if [ ! -d iOS/JaagteRaho.xcworkspace ]; then ./scripts/bootstrap.sh; fi
JR_SIM_ID="${SIMULATOR_ID:-$(xcrun simctl list devices available --json | /usr/bin/python3 -c 'import json,sys; ds=[d for group in json.load(sys.stdin)["devices"].values() for d in group if d.get("isAvailable") and "iPhone" in d["name"]]; ds.sort(key=lambda d: d.get("state") != "Booted"); print(ds[0]["udid"] if ds else "")')}"
if [ -z "$JR_SIM_ID" ]; then
  echo 'No iPhone simulator is installed. Add an iOS simulator runtime in Xcode Settings > Components, then retry.' >&2
  exit 1
fi
xcrun simctl boot "$JR_SIM_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$JR_SIM_ID" -b
xcodebuild -workspace iOS/JaagteRaho.xcworkspace -scheme JaagteRaho -configuration Debug \
  -destination "id=$JR_SIM_ID" -derivedDataPath build/DerivedData -jobs 2 \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- COMPILER_INDEX_STORE_ENABLE=NO build
./scripts/check-bundle.sh build/DerivedData/Build/Products/Debug-iphonesimulator/JaagteRaho.app
xcrun simctl install "$JR_SIM_ID" build/DerivedData/Build/Products/Debug-iphonesimulator/JaagteRaho.app
if [ "${SAARTHI_GRANT_PERMISSIONS:-0}" = "1" ]; then
  for JR_PERMISSION in camera microphone location media-library; do
    xcrun simctl privacy "$JR_SIM_ID" grant "$JR_PERMISSION" com.jaagteraho.driver
  done
fi
if [ -f .env ] && command -v node >/dev/null 2>&1; then
  node --env-file=.env --input-type=module - "$JR_SIM_ID" <<'JS'
import {spawnSync} from 'node:child_process';
const env = {...process.env};
if ((process.env.APP_TOKEN ?? '').length >= 24) {
  env.SIMCTL_CHILD_SAARTHI_BACKEND_URL = `http://127.0.0.1:${process.env.PORT || 8787}`;
  env.SIMCTL_CHILD_SAARTHI_BACKEND_TOKEN = process.env.APP_TOKEN;
}
const result = spawnSync('xcrun',['simctl','launch','--terminate-running-process',process.argv[2],'com.jaagteraho.driver'],{env,stdio:'inherit'});
process.exit(result.status ?? 1);
JS
else
  xcrun simctl launch --terminate-running-process "$JR_SIM_ID" com.jaagteraho.driver
fi
JR_DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [ -d "$JR_DEVELOPER_DIR/../Applications/DeviceHub.app" ]; then
  open "$JR_DEVELOPER_DIR/../Applications/DeviceHub.app"
elif [ -d "$JR_DEVELOPER_DIR/Applications/Simulator.app" ]; then
  open "$JR_DEVELOPER_DIR/Applications/Simulator.app" --args -CurrentDeviceUDID "$JR_SIM_ID"
else
  printf '%s\n' 'App built, installed and launched. No simulator GUI was found in the selected Xcode installation; the simulator device is running headlessly.'
fi
