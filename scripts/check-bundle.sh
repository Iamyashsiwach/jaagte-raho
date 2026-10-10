#!/bin/bash
set -euo pipefail
JR_APP="${1:?Pass the built JaagteRaho.app path}"
test -s "$JR_APP/face_landmarker.task"
test -s "$JR_APP/Assets.car"
test -s "$JR_APP/Audio/alarm.wav"
for jr_language in hi pa en; do
  for jr_prompt in checkin acknowledged critical; do
    test -s "$JR_APP/Audio/${jr_language}_${jr_prompt}.wav"
  done
done
printf '%s\n' 'Bundle verified: face model, asset catalog, alarm, and all nine voice clips present.'
