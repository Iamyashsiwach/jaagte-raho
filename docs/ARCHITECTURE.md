# Native iOS architecture

This document describes the iOS MVP implementation, which supersedes the original Flutter proposal in `TECHNICAL_PLAN.md`.

## Ownership and execution

`DriveModel` coordinates a foreground session, calibration, current measurements, voice state, and event delivery. SwiftUI observes its published state. Camera capture and MediaPipe inference run on dedicated serial queues; only compact face measurements reach the UI thread.

`CameraService` owns AVFoundation and the bundled MediaPipe Face Landmarker. It uses the official iOS SDK in video mode on its frame worker, targeting approximately 12 inference frames/second with a 640 × 480 feed. AVFoundation discards late frames instead of accumulating latency. Under serious or critical thermal pressure the inference target drops to approximately 8 frames/second. These are implementation targets, not measured device performance.

The detector reads eye aspect ratios from face landmarks, jaw-opening blendshapes, and a relative pitch proxy from face geometry. Illumination and geometry checks mark unusable measurements. Facial transformation matrices are enabled in the SDK, but the current head signal uses the landmark-based proxy; it should not be described as a validated head-pose estimator.

## Calibration and temporal rules

Calibration collects approximately three seconds of stable open-eye measurements followed by approximately two seconds of closed-eye measurements. Gaps, invalid samples, or unsuitable eye geometry reset the current calibration phase. Median values establish per-driver eye thresholds and neutral pitch. Ollie speaks each enrollment phase through online Smallest speech or device fallback. Completion stays on the enrollment screen until the user confirms **Start monitoring with Ollie** with fresh usable tracking of both eyes open (maximum age 750 ms). The detector starts with that open-eye sample, keeping calibration closure time out of the monitoring session.

The `FatigueEngine` is a Swift struct with no camera, UI, network, or audio dependency. Every measurement uses the same monotonic clock. A watchdog advances missed-reply deadlines even when camera results stop arriving.

| Rule | Initial setting |
| --- | --- |
| Continuous bilateral closure → check-in | 1.5 seconds |
| Continuous bilateral closure → critical alarm | 3 seconds |
| Reply window after prompt completion | 8 seconds |
| Missing prompt-completion safeguard | 20 seconds from check-in |
| Continuity-breaking frame gap | More than 0.4 seconds |
| Stale tracking | More than 0.8 seconds since usable measurements |
| Closure trend | Time-weighted 60-second window; 30% candidate threshold |
| Trend readiness | At least 20 seconds elapsed, 15 tracked seconds, and 70% coverage |
| Repeated yawn candidates | Three sustained jaw-opening signals within 120 seconds |
| Repeated nod candidates | Three pitch departures and returns within 60 seconds |

These thresholds are tunable prototype heuristics. The closure fraction is inspired by PERCLOS research but is not a validated pupil-occlusion measurement. Jaw opening can reflect talking; pitch changes can reflect ordinary glances.

An acknowledgment is accepted only during check-in when the eyes have reopened for at least half a second, tracking is fresh, and the elevated closure trend is absent. It never clears a critical event. Critical state stays latched until the parked/end-session action.

Lost tracking breaks continuous closure accumulation and changes the status to unavailable. It does not dismiss an already critical event or prevent a missed-reply deadline from escalating.

## Voice and escalation

`VoiceService` uses `AVAudioPlayer` for bundled language clips and the looping alarm. It falls back to an installed system voice if a prompt clip is missing. Haptics accompany a critical alarm. Actual audibility depends on volume, audio route, interruptions, and device state.

Alarm acknowledgments use Apple Speech with `requiresOnDeviceRecognition=true`. Online companion input uses bounded 16 kHz WAV turns sent through the backend to Smallest Pulse for Hindi/English. The recording stops after a speech pause or at 12 seconds, and temporary audio is deleted when completed or cancelled. Punjabi online input uses labeled Apple recognition with network processing allowed. Unavailable recognition or denied microphone permission leaves the detection prompts and alarm active.

The backend defaults to Smallest Electron for brief AI replies when `SMALLEST_API_KEY` is present, then Lightning for WAV speech. A configured OpenAI provider remains an alternative when Smallest is absent. The companion accepts six bounded history turns and supports a custom HTTPS assistant. A new critical event cancels microphone capture and conversation tasks and starts the local alarm immediately.

The response prompt encourages a safe stop and rest. It disallows invented nearby rest stops, diagnoses, or claims that conversation makes a fatigued driver safe. Route-specific dhaba suggestions are outside the current MVP.

## Events and fleet delivery

`EventStore` writes phone events to an atomic, protected JSON file in Application Support. It restores them on launch. A critical transition records an event once per session. Demo events have a visible simulation flag and remain local. The phone periodically sends queued live events when a backend is configured.

The Node service persists one JSON file per event UUID and accepts repeat submissions idempotently. A configured HTTPS webhook receives the event with an idempotency header. Delivery failures retry with bounded exponential backoff. Server restart restores pending records from disk.

Delivery labels describe separate stages: queued on phone, stored on server, delivery retrying, or webhook accepted. A webhook acceptance is not proof of human receipt. An empty fleet URL means server storage only, not fleet notification.

## Credentials and data boundary

- `.env` contains provider secrets and stays outside Git; `.env.example` contains only blank fields and configuration defaults.
- Provider keys never enter the app bundle or app settings.
- The app's backend pairing token is stored in Keychain.
- Camera frames are discarded after local inference; there is no video recording or frame-upload endpoint.
- Online Hindi/English companion turns send a short microphone recording to the paired backend and Smallest Pulse; the backend validates bounded WAV bytes and stores no recordings. Local temporary files are deleted after completion/cancellation. Offline check-in recognition stays on-device. Conversation sends short text plus at most six bounded history turns.
- Local events contain UUID, timestamp, trigger, simulation flag, and delivery status; server records add receipt/retry metadata.

The local HTTP backend is intended for a trusted demonstration network. A deployed service needs HTTPS, appropriate token provisioning, operational monitoring, and data retention/access controls.

## Validation boundary

Core rules and backend behavior can run under `swift test` and `npm test`. Those checks cannot establish real camera accuracy, thermal stability, Punjabi recognition support, or alarm audibility. The real iPhone build and parked demonstration are separate acceptance gates. See [DEMO.md](DEMO.md).
