#!/bin/bash
set -euo pipefail
JR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$JR_ROOT"
if ! xcodebuild -version >/dev/null 2>&1; then
  if [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    echo 'Full Xcode is required. Install it from the Mac App Store, launch it, and complete its first-run setup.' >&2
    exit 1
  fi
fi
for jr_tool in xcodegen pod; do
  if ! command -v "$jr_tool" >/dev/null 2>&1; then
    echo "Missing $jr_tool. Run: brew install xcodegen cocoapods" >&2
    exit 1
  fi
done
JR_MODEL=iOS/JaagteRaho/Resources/face_landmarker.task
if [ ! -f "$JR_MODEL" ]; then
  curl -fL --retry 2 https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task -o "$JR_MODEL"
fi
JR_HASH="$(shasum -a 256 "$JR_MODEL" | awk '{print $1}')"
if [ "$JR_HASH" != '64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff' ]; then
  echo 'The face model checksum does not match the pinned release.' >&2
  exit 1
fi
xcodegen generate --spec iOS/project.yml --project iOS
cd iOS
pod install
printf '%s\n' 'Open iOS/JaagteRaho.xcworkspace, select your signing team and iPhone, then Run.'
