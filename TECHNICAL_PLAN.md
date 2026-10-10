# Jaagte Raho — proposed mobile implementation

Prepared 10 October 2026. The initial proposal below is superseded by the confirmed native iOS build: SwiftUI + official MediaPipe, bundled Hindi/Punjabi audio, capability-checked Apple on-device speech, GPT-5-nano/Smallest through a server, and an atomic JSON event outbox. See README.md and docs for the current implementation and validation status. Flutter, whisper.cpp, SQLite, and Android are deferred.

## Recommendation

Build a Flutter app for iOS and Android, with a small native vision plugin in Swift and Kotlin. Use the official MediaPipe Face Landmarker SDKs rather than making the core detection depend on a community Flutter wrapper. Flutter provides the shared driver interface, fatigue rules, trip state, settings, and event history. Native code owns the camera and face inference. Flutter supports this integration through platform channels. [Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels)

For an exclusively iPhone demo, SwiftUI is a reasonable smaller alternative. Flutter is the proposed default because the product should eventually work on drivers' existing Android phones too.

## End-to-end flow

```text
Front camera -> native MediaPipe -> timestamped facial measurements
                                         |
                                  Dart fatigue engine
                                         |
                         short Hindi/Punjabi voice check-in
                                         |
                       offline recognition of a short response
                                         |
                     continued eye closure / no response -> alarm
                                         |
                            durable fleet-alert outbox
                                         |
                    connectivity -> authenticated alert service
```

## Camera and vision

- Bundle `face_landmarker.task` in the app; no model download is required during a trip.
- Use AVFoundation on iOS and CameraX on Android. Native code exposes a preview texture to Flutter and sends compact metrics through an event channel. Raw camera frames stay native and are discarded after processing.
- Configure one face, live-stream inference, blendshapes, and facial transformation matrices. Google's SDKs provide asynchronous live-stream processing and these facial outputs. [iOS guide](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker/ios), [Android guide](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker/android)
- Initially target a 640x480 camera feed and 10–15 inference frames/second. Measure latency and thermal behavior on the actual demo phone before choosing the final rates. Keep preview rendering separate from inference.
- Use monotonic timestamps, correct rotation/mirroring, and drop old frames instead of building up a queue.
- Require a short calibration while parked: eyes open, eyes closed, and normal head position. Calibration collects only samples with stable tracking; a partial or invalid calibration cannot start monitoring.

## Fatigue engine

MediaPipe measures face geometry; it does not directly diagnose fatigue. Implement a deterministic, inspectable temporal engine over those measurements.

| Signal | Implementation |
| --- | --- |
| Prolonged eye closure | Calibrated eye aspect ratio from eyelid landmarks, checked against left/right blink blendshapes; require both eyes and persistence rather than reacting to one frame. |
| Closure trend | Calculate a time-weighted closure fraction over a rolling 60-second window. Display tracking coverage and suppress this metric when coverage is insufficient. This is a PERCLOS-inspired proxy, not a validated pupil-occlusion measurement. |
| Yawn candidate | Sustained mouth opening relative to the calibrated baseline, using mouth geometry and jaw opening. Debounce events and treat talking as a possible confounder. |
| Head nod | Pitch displacement and recovery relative to the calibration baseline, using the facial transformation matrix. A glance down alone is insufficient. |
| Tracking quality | Face presence, usable geometry, frame freshness, and image illumination. Missing/occluded eyes produce an unavailable state rather than an alert-driver reading. |

Eye aspect ratio is an established blink-detection feature. PERCLOS research measures the proportion of time with substantial eyelid closure; our landmark approximation needs validation before field use. [Soukupová and Čech](https://cmp.felk.cvut.cz/ftp/articles/cech/Soukupova-TR-2016-05.pdf), [US DOT PERCLOS report](https://ntlsearch.bts.gov/ntl/md.do?id=51369)

Use named states: `idle`, `calibrating`, `monitoring`, `checkIn`, `critical`, `recovery`, and `trackingUnavailable`. Track the fleet outbox separately from the detector state.

Proposed demo defaults, to be tuned rather than presented as validated safety thresholds:

1. Around 1.5 seconds of continuous bilateral closure triggers a brief voice check-in.
2. Continued closure around 3 seconds triggers the alarm immediately, even if the prompt is still playing.
3. If eyes reopen, allow a short response window, initially 8 seconds after prompt playback ends. No recognized acknowledgment escalates.
4. An acknowledgment never clears sustained eye closure, an elevated closure trend, or a critical event. Critical mode directs a safe stop; recovery requires an explicit parked/rest confirmation.
5. Repeated yawn/nod candidates can contribute to a check-in, with hysteresis and cooldowns. They never claim a numerical probability of fatigue.
6. Stop time accumulation across missing faces, stale frames, app suspension, or inference errors. Loss of tracking during an unresolved critical event does not clear that event.

## Offline voice

Use a local dialogue state machine for the first version. Prompts respond to a few intents such as acknowledgment, repeat, need a break, and stopping. This supplies short contextual exchanges without putting a network request in the alarm path.

- Bundle spoken Hindi and Punjabi clips plus an alarm sound. Playback remains available without a downloaded system voice. System text-to-speech can support dynamic content where a suitable voice is installed.
- Example Hindi prompt: “Bhai, aankhen band ho rahi hain. Meri awaaz aa rahi hai? Surakshit jagah par gaadi rok kar aaram karo.”
- For recognition, evaluate a bundled multilingual `whisper.cpp` model on short response windows. The project supports iOS, Android, and offline inference. Start with a quantized tiny/base candidate and choose based on measured Hindi/Punjabi recognition quality, latency, and memory. [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
- Native speech recognition is an optional faster route only when the selected language/device reports on-device support. On iOS, `requiresOnDeviceRecognition` depends on `supportsOnDeviceRecognition`; do not silently fall back to sending audio to a server. [Apple on-device speech support](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)
- Stop playback before listening, apply voice activity detection, and recognize a limited set of acknowledgment phrases. Engine/road noise or an arbitrary loud sound does not count as a driver response.
- Keep detection and escalation running while recognition works on a separate worker. Silence, recognition failure, unavailable microphone, and missed deadlines preserve escalation.
- Test airplane-mode behavior per language. If a language is not reliable on the chosen phone, expose that limitation in setup and retain voice prompts plus alarm; do not describe the response recognizer as working.
- Respect audio interruptions and the actual system output volume. An iOS app cannot promise to override every device/audio-route condition to make its alarm loud.

The intervention should encourage stopping and resting. Conversation is an engagement mechanism, not evidence that it is safe to keep driving while sleepy. [FMCSA fatigue guidance](https://www.fmcsa.dot.gov/safety/driver-safety/cmv-driving-tips-driver-fatigue)

## Fleet alerts and persistence

Use SQLite for event metadata and a durable delivery outbox. Persist UUID, driver/vehicle identifiers, timestamps, trigger, acknowledgment state, and optional location with accuracy and age. Do not retain raw video or microphone recordings by default.

Ship a minimal authenticated Node/TypeScript alert service alongside the app. The app submits events over HTTPS; the service deduplicates by UUID and delivers to the configured fleet webhook or notification provider. Credentials for external delivery stay server-side. Add bounded retries and explicit `pending`, `accepted`, `delivered`, and `failed` states; a server receipt is not proof the owner received the notification.

Local detection, prompts, and the alarm work offline. Remote fleet delivery waits for connectivity. iOS's standard SMS interface requires a person to send the message, so it cannot implement silent automatic escalation from the driver's SIM. [Apple message composer](https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontroller)

Demo mode can show a clearly labeled simulated fleet receipt. A real end-to-end receipt requires a configured endpoint and recipient.

## Driver experience

1. Setup while parked: language, permissions, driver/vehicle identity, mount check, audio check, and calibration.
2. Drive screen: large monitoring state, compact front-camera preview, clear tracking status, and a simple rest reminder.
3. Check-in: spoken prompt and short response status; no reading or typing is required.
4. Critical screen: alarm, safe-stop instruction, and fleet delivery status.
5. Trip summary: duration and recorded events, with no claim that a trip was safe merely because no event was detected.
6. A separate, explicitly labeled demo mode provides replayable synthetic eye-closure/yawn/nod events for UI and simulator demonstrations. The real camera demonstration is tested independently.

For the first demo, use a generic safe-stop prompt. “The next dhaba is 4 km away” requires verified route/POI data and a usable location. Add route-specific rest stops later, with a route downloaded before departure and clear freshness handling.

On iOS, keep the monitoring app visible with auto-lock disabled during the session. Handle backgrounding and interruptions as monitoring unavailable; ordinary camera capture cannot be assumed to continue behind another app or a locked screen. [Apple camera interruption documentation](https://developer.apple.com/documentation/AVFoundation/AVCaptureSession/InterruptionReason/videoDeviceNotAvailableInBackground)

## Proposed repository structure

```text
lib/
  app/                 theme, routing, setup
  features/drive/      driver dashboard and trip controls
  features/demo/       replay controls, visibly simulated
  domain/fatigue/      metrics, calibration, temporal rules
  domain/voice/        dialogue and response intents
  data/                SQLite events and fleet outbox
packages/driver_vision/
  lib/                 typed camera/measurement interface
  ios/                 Swift camera and MediaPipe integration
  android/             Kotlin CameraX and MediaPipe integration
packages/offline_voice/
  lib/                 playback/recognition interface
  ios/                 audio session and recognition bridge
  android/             audio focus and recognition bridge
assets/                model, localized prompts, alarm
server/                fleet event ingestion and delivery
test/                  temporal engine and escalation tests
```

Pin SDK/package versions and retain model license notices/checksums when implementing.

## Build order and acceptance checks

1. Scaffold Flutter, the driver screens, local state machine, and labeled replay demo. Verify transitions with deterministic timestamped traces.
2. Integrate native camera and MediaPipe; run the eyes-closed demonstration on a physical phone. Verify normal blinking, calibration, rotation, dropped frames, face loss, and background/resume.
3. Add Hindi/Punjabi playback and short offline response recognition; verify prompt/response turn-taking and that recognition never delays the critical alarm.
4. Add persistence and fleet service; verify offline queueing, restart recovery, duplicate delivery, and a real configured recipient receipt.
5. Run an airplane-mode demonstration and a sustained camera/thermal test. Check cabin-like noise, low light, glasses, and permission/audio interruptions on the chosen device.

The first live demonstration is a parked teammate closing their eyes, receiving a spoken prompt, and triggering the alarm if closure continues. Driving use requires further representative testing and threshold validation.

## Local toolchain findings

The workspace was empty. Flutter/Dart and CocoaPods were not available on PATH during inspection. `xcode-select` points to Apple's Command Line Tools, and `xcodebuild` reports that full Xcode is required. No Xcode or Android Studio installation was found in the inspected standard Applications directories.

App source can be developed here. Compiling/running iOS needs full Xcode, native dependencies, signing, and a physical iPhone for the camera test. Android needs its SDK/build tools and a physical test phone. Framework and device setup is the first implementation task after platform confirmation.

## Confirmation needed

Confirm the proposed Flutter build, or choose native SwiftUI for an iPhone-only demo. Identify whether the first demo phone is an iPhone or Android device so the first camera and speech integration can target it.
