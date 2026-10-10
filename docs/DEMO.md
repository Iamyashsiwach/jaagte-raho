# Parked iPhone demo

The demonstration shows a heuristic signal and the resulting intervention. It does not establish fatigue detection accuracy or permission to use the prototype while driving.

## Prepare the phone

1. Build and install through full Xcode using the connected iPhone and your signing team.
2. Enable iPhone Developer Mode if needed. Grant camera access, and microphone/speech access if testing replies.
3. Park, mount the phone securely, and keep both eyes visible to the front camera in good light.
4. Choose Hindi, Punjabi, or English. Run the voice test and set a clearly audible speaker volume.
5. Check the app's offline-reply capability status for that language. If unavailable, demonstrate prompts and the alarm without claiming offline speech recognition.

## Real camera demonstration

1. Start live monitoring and follow the parked calibration: open eyes for approximately three stable seconds, then close them for approximately two seconds.
2. Wait for the monitoring state, then keep the eyes normally open. Ordinary brief blinks should not trigger a check-in.
3. Close both eyes continuously. At roughly 1.5 seconds, a bundled voice prompt should begin.
4. Keep both eyes closed. At roughly 3 seconds, the alarm should interrupt the prompt and remain latched.
5. Open the eyes. The critical event should remain visible; a reply must not dismiss it.
6. Use the parked/end-session action to stop the session.

To demonstrate acknowledgment separately, begin a new session, trigger the check-in, reopen the eyes, and say a supported short acknowledgment after the prompt finishes. Confirm the displayed tracking and response state. A new prolonged closure must still trigger escalation.

## Labeled synthetic demo

Use the app's demo/replay controls for predictable screen presentations or simulator use. The demo uses generated facial measurements and displays its simulation status. Its events remain local. State clearly that this demonstrates application behavior rather than a live camera result.

## Offline verification

- With airplane mode enabled and Wi-Fi disabled, run the voice test and repeat the real camera closure demonstration.
- Confirm prompts and the alarm remain available.
- Test replies only if the selected recognizer reports on-device support; check actual recognition on the phone in airplane mode.
- Confirm any live fleet event is shown as queued rather than delivered.
- Restore connectivity and confirm the queue advances through the configured backend.

## Optional fleet and cloud demonstration

Start the Mac backend from the ignored `.env` file. Pair the iPhone using the Mac's `.local` hostname and `APP_TOKEN` on the same network. Keep provider keys on the Mac. Enable optional online voice only for the conversation demonstration.

A real fleet demonstration requires a configured HTTPS webhook and an observable recipient endpoint. Trigger a live event, then verify both the server's status and the receiving endpoint. The “webhook accepted” label describes an HTTP response, not proof that a fleet owner read the message. The synthetic demo must not notify a real recipient.

## Device acceptance checks

Record the tested iPhone model, iOS version, build revision, language, lighting, mount position, and observations. Before calling the device flow verified, check:

- Normal blinking and sustained closure after calibration.
- Face loss, poor lighting, glasses, permission denial, and a covered camera.
- Background/resume and audio interruptions; unavailable tracking must be visible.
- Missed replies and unavailable speech recognition; escalation must remain active.
- Event history after app restart and offline queue recovery.
- At least a sustained monitoring session with inference latency, battery change, and thermal state recorded.
- Alarm audibility with the actual phone mount and speaker route.

If the iPhone build is blocked by missing full Xcode, available disk space, dependency installation, or signing, report that explicitly. Core tests, a replay demo, or generated voice clips do not replace physical-device verification.
