# Saarthi · सारथी

**An iPhone drowsiness co-pilot that notices prolonged eye closure, checks in by voice, and escalates to an alarm.**

This prototype uses the driver's dashboard-mounted iPhone rather than a dedicated fleet camera. Face analysis runs locally; Hindi, Punjabi, and English alerts are bundled for playback without mobile data. Online Ollie uses Smallest.ai Pulse transcription, Electron conversation and Lightning speech through a small paired server. The same Smallest key powers all three stages; OpenAI is an optional alternative. Fleet delivery uses a configured webhook.

**Project status:** native iOS MVP builds with full Xcode and real MediaPipe, and has been signed, installed, and launched on an iPhone 14. Live camera startup, video-frame delivery, and face inference have been verified on that phone after fixing permission-dialog lifecycle handling. The dashboard also runs visibly on the iPhone 17 simulator in Xcode 27's Device Hub, with backend voice pairing connected. Recognition accuracy, speech support, and sustained performance still require acceptance checks. The first demonstration must take place while parked. This is a prototype with heuristic thresholds, not a validated driver-safety system.

**Continuing on another Mac?** Read [context.txt](context.txt) for current state and immediate demo setup.

**Building on your friend's iPhone?** Follow [HOW_TO_RUN.md](HOW_TO_RUN.md) for copy-and-paste setup, Apple signing, the private `.env`, online voice pairing and eye calibration.

## What the MVP does

**New demo features:** Ollie, the owl companion; four-step onboarding leading into spoken eye enrollment; Smallest.ai listening, AI replies and speech; hands-free turns, a short story and a voice quiz; music-library selection; opt-in GPS journey recording with saved route maps; timestamped location sharing; and a server-side custom assistant adapter. Home puts eye setup first. See [technical specs](docs/FEATURE_SPECS.md) and [another-Mac/iPhone setup](docs/FRIEND_SETUP.md). Smallest alone powers general AI conversation through Electron.

- Front-camera face tracking with the bundled Google MediaPipe Face Landmarker model.
- Parked calibration for the driver's open eyes, closed eyes, and neutral head position.
- Time-based rules for eye closure, closure trends, repeated yawn candidates, and head-nod candidates.
- A voice check-in after approximately **1.5 seconds** of continuous bilateral eye closure; a latched alarm after approximately **3 seconds**.
- Short on-device speech acknowledgments when Apple's recognizer supports the selected language on that iPhone. Missing recognition support never disables the alarm.
- Local event history and a persistent delivery queue that retries when a backend becomes reachable.
- An explicitly labeled synthetic demo for screen demonstrations, separate from real camera monitoring.

The alarm does not wait for an API request. A spoken response does not clear a critical event or prove that someone is safe to continue driving.

## How it works

```text
iPhone front camera → MediaPipe → calibrated temporal engine
                                      │
                              bundled voice check-in
                                      │
                       continued closure / missed reply
                                      │
                                local alarm
                                      │
                         persistent event delivery queue
                                      │ connectivity
                         Node backend → fleet webhook

Optional, after an accepted reply:
short transcript → Node backend → GPT-5-nano → Smallest.ai → spoken follow-up
```

| Layer | Implementation |
| --- | --- |
| iPhone interface | Native SwiftUI; iOS 16 or later |
| Camera | AVFoundation; 640 × 480 front-camera feed |
| Face inference | MediaPipeTasksVision 0.10.35 via CocoaPods; bundled `.task` model |
| Performance target | About 12 inference frames/second; late frames discarded; reduced rate during high thermal pressure |
| Detection | Platform-independent Swift core, monotonic timestamps, frame-freshness checks |
| Offline output | Bundled WAV prompts, local alarm, haptics |
| Offline replies | Apple Speech with `requiresOnDeviceRecognition`; language/device dependent |
| Online Ollie | Smallest Pulse (Hindi/English input), Electron replies, Lightning TTS; Punjabi uses Apple input |
| Persistence | Atomic JSON files on the phone and server; no database dependency |
| Backend | Node.js 20.12+; built-in HTTP and fetch; no npm dependencies |

See [architecture and current behavior](docs/ARCHITECTURE.md) and the [parked demo checklist](docs/DEMO.md). The earlier [technical proposal](TECHNICAL_PLAN.md) describes a Flutter alternative; this repository now prioritizes native iOS.

## Run on an iPhone

Prerequisites: a Mac with **full Xcode**, an attached trusted iPhone, enabled iPhone Developer Mode, an Apple signing team, XcodeGen, and CocoaPods. Command Line Tools alone cannot build or install the app.

Generate the project and install the pinned dependencies:

```sh
./scripts/bootstrap.sh
open iOS/JaagteRaho.xcworkspace
```

In Xcode, select the JaagteRaho target, choose your signing team, select the connected iPhone, and run. Allow camera access for monitoring; microphone and speech permissions are needed only for voice replies. Use the app's voice test and calibrate while parked before starting a live session.

For an installed iPhone simulator, run `./scripts/run-simulator.sh` after bootstrap. It builds, installs, and launches using local ad-hoc signing without Apple signing credentials, then opens Device Hub on Xcode 27 or Simulator on earlier versions. Start the labeled synthetic demo for a predictable presentation.

The connected-device helper also supports a signed build and install:

```sh
TEAM_ID=YOUR_APPLE_TEAM_ID ./scripts/run-iphone.sh
```

The simulator can demonstrate the labeled replay flow. It cannot validate the physical front-camera pipeline, cabin noise, speech support, or thermal behavior.

## Optional voice and fleet backend

The app's detection, bundled prompts, and alarm do not require this service.

1. Copy `.env.example` to `.env` in the repository root.
2. Set `SMALLEST_API_KEY` locally for Pulse, Electron and Lightning. `OPENAI_API_KEY` is optional. Provider keys stay on the Mac/server and are never entered into the iPhone app.
3. Set `APP_TOKEN` to a random value of at least 24 characters. Use it as the iPhone's backend pairing token.
4. Keep `HOST=127.0.0.1` for Mac-only testing. For an iPhone on the same Wi-Fi, set `HOST=0.0.0.0` and use your Mac's `.local` hostname in the app. Use HTTPS for a deployed service.
5. Configure `FLEET_WEBHOOK_URL` only when a real recipient endpoint is available. It must use HTTPS; add `FLEET_WEBHOOK_TOKEN` if that endpoint requires authentication.

```sh
cp .env.example .env
# Edit .env privately, then:
cd server
npm start
```

Pair the app with `http://your-mac-name.local:8787` for a local demonstration, or an HTTPS URL for a deployed service. The app stores the pairing token in iOS Keychain. Optional online voice is controlled separately in the app.

To regenerate bundled speech with the Smallest.ai credits:

```sh
cd server
npm run voices
```

This generator calls Smallest.ai at development time and writes WAV files into the app resources; playback of those files remains offline. Regeneration consumes voice credits. Neither provider keys nor `.env` belong in source control.

### Backend endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/health` | Health check; no token required |
| GET | `/v1/status` | Provider and fleet configuration status |
| POST | `/v1/conversation` | Short follow-up from a recognized transcript |
| POST | `/v1/voice` | WAV speech for a short text |
| POST | `/v1/events` | Idempotent event ingestion by UUID |
| GET | `/v1/events/:id` | Event delivery status |

All `/v1` requests require `Authorization: Bearer <APP_TOKEN>`. Fleet events are stored locally on the server and retried with backoff. “Delivered” means the webhook returned a successful HTTP status; it does not establish that the owner read an alert. Synthetic demo events remain local and do not notify a fleet recipient.

## Tests and validation

The fatigue engine is a Swift package, so its temporal rules can be tested without Xcode or an iPhone:

```sh
swift test
cd server
npm test
```

From the repository root, `./scripts/check.sh` runs the integrated core, backend, and credential checks.

Current executed results: **26/26 Swift core assertions and 19/19 backend tests pass**. The **full signed iOS app build, iPhone installation, and launch succeed**. Device logs confirm live camera frames and completed MediaPipe inference. Simulator build, installation, launch, visible dashboard, and backend pairing also succeed; broader device acceptance checks remain to be completed. An actual-view Mac Catalyst preview also builds and displays the dashboard.

The core tests cover closure escalation, acknowledgments, missing/stale frames, calibration, and timing. Backend tests cover authentication, event handling, provider failures, and fleet delivery. Automated tests establish behavior for those cases; physical-device recognition accuracy, alert audibility, battery use, inference latency, and heat still need measurement. See [the demo checklist](docs/DEMO.md) before presenting the live camera flow.

## Repository layout

```text
iOS/JaagteRaho/        SwiftUI app, camera, services, core, bundled resources
Tests/                Deterministic Swift core tests
server/               Authenticated optional voice and fleet service
scripts/              Toolchain, model, and Xcode project setup
docs/                 Architecture and demo instructions
Package.swift         Host-runnable Swift core package
.env.example          Empty credential/configuration template
```

All demo development is on `main`.

## Privacy and operating limits

Camera frames are processed locally and are not recorded or sent to the backend. Offline detection acknowledgments use on-device recognition. Online Hindi/English companion turns send a short WAV recording through the backend to Smallest Pulse; temporary phone files are deleted after completion/cancellation, and the backend stores no recordings. Punjabi online companion input uses Apple recognition. Conversation sends short text and a bounded history. Events contain identifiers, timestamps, trigger type, and delivery state.

Monitoring requires the app to remain foregrounded. Backgrounding, stale frames, poor lighting, and lost face tracking are shown as unavailable rather than interpreted as an alert driver. Sunglasses, camera mounting, individual eye geometry, speaking, and cabin noise may affect the heuristic signals. The head-pitch estimate is a landmark-based proxy, not a validated gaze or fatigue measurement.

Set up and test the phone while parked. Alerts support a safe stop and rest; conversation, coffee, or answering the app should never be treated as a cure for fatigue. iOS audio volume and routing still matter. A production release requires representative driver testing, accessibility work, reliability evaluation, and validated intervention thresholds.
