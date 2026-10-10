# Ollie and journey features

SAARTHI is the app; **Ollie** is its owl companion. Native SwiftUI, iOS 16+, Swift 5, with no Flutter migration. All changes stay on `main`.

## Presentation flow

Four-step first launch: meet Ollie, select Hindi/Punjabi/English and hear the voice, choose optional journey recording, then start parked eye enrollment. Settings can replay the introduction. Home places **Set up my eyes with Ollie** above companion and journey cards.

Enrollment uses the real front-camera MediaPipe eye signals: three seconds with both eyes open, then two seconds with both eyes closed, with phase continuity checks. Ollie gives language-specific instructions through Smallest.ai when paired, with device speech fallback. The eye badge follows measured closure during calibration and monitoring. A completion screen requires explicit **Start monitoring with Ollie** and a usable sample of both eyes open from the past 750 ms; calibration samples do not contribute to fatigue closure time. Baselines remain in memory for the current session, and every real session requires enrollment. Camera frames stay local.

## Online voice and companion

Online voice is enabled by default. The iPhone calls the paired authenticated Node backend; the backend calls Smallest.ai Lightning `lightning_v3.1_pro` at `POST https://api.smallest.ai/waves/v1/tts`. Audio is WAV at 24 kHz; voices are `aviraj` for Hindi, `rajdeep` for Punjabi and `blake` for English. A real English request returned HTTP 200 and a valid WAV during this implementation.

- Hindi/English online input uses a bounded 16 kHz mono PCM WAV recording and Smallest Pulse at `POST /waves/v1/stt/?model=pulse&language=hi|en`. A turn ends after 1.2 seconds of silence following speech, at 12 seconds maximum, or when the driver taps Finish reply. Temporary audio is removed on completion/cancellation. The authenticated backend accepts at most 512,000 bytes and never saves recordings. Punjabi online input uses Apple recognition because Pulse's documented language list does not include Punjabi. Offline alarm acknowledgments retain on-device recognition.
- Hands-free turns resume listening after speech playback. Saying “stop” ends the conversation. Microphone/audio permission is requested when starting conversation.
- Original short story and one voice quiz are bundled in all three languages. Their speech is synthesized online with Smallest when connected.
- General conversation defaults to Smallest Electron at `POST /waves/v1/chat/completions`, model `electron`, using the same `SMALLEST_API_KEY`; no OpenAI key is needed. A bounded six-message history provides context. Without a Smallest key, the configured OpenAI provider remains an alternative. The custom HTTPS assistant remains selectable. Scripted replies are labeled if the conversation provider fails.
- Online companion input sends the short recording through the paired backend to Smallest for transcription, then sends the short transcript and bounded history for conversation. Camera frames and GPS are never sent to the voice providers. The companion screen and microphone permission text explain online recording transfer.
- Voice generation/playback and conversation are cancelled for a detection check-in or critical alarm. Music is paused. A critical alarm remains latched until the parked/end-session confirmation.
- If a speech request fails, installed device speech is the fallback. Alarm and check-in clips remain bundled so the detection response never waits for the network.

Custom assistant configuration lives only in the backend `.env`:

```dotenv
ASSISTANT_URL=https://your-assistant.example/chat
ASSISTANT_TOKEN=your-server-side-token
```

Select “My assistant” in the companion hub. `POST /v1/companion` accepts `transcript` (1–500 characters), `language` (`hi`, `pa`, `en`), and `assistant` (`saarthi` or `custom`). The custom endpoint receives:

```json
{"transcript":"Hello","language":"en","context":"road_companion","maxWords":35}
```

Return `{"text":"Your short response"}` (1–600 characters). The adapter requires HTTPS, rejects embedded URL credentials, disallows redirects, and times out after 6.5 seconds. It does not send GPS data. This adapter does not automatically connect a personal ChatGPT or other consumer account.

## Music

`MPMediaPickerController` selects songs from the user's library; `MPMusicPlayerController.applicationMusicPlayer` manages playback. Media-library authorization is separate from camera/microphone authorization. It uses available library items rather than bundling copyrighted music or providing a streaming catalog. Actual library availability and playback require a physical-device check. Every voice prompt or alarm pauses playback; it does not automatically resume after an alarm.

## Journey recording and sharing

Core Location with When In Use authorization, nearest-ten-meter desired accuracy, 15-meter distance filter, automotive activity type. Opt-in recording begins with a real monitoring session, including setup. Synthetic demo sessions never record real routes.

- A sample must have finite coordinates, latitude/longitude in range, horizontal accuracy 0–100 m, and timestamp within the past 15 seconds (allowing 5 seconds of clock tolerance).
- The route rejects duplicate/out-of-order timestamps, moves faster than 55 m/s, and stationary drift smaller than 15 m unless 60 seconds have elapsed.
- Foreground suspension and GPS gaps over 60 seconds start new segments. Distance and polylines never bridge these gaps.
- Route storage is bounded by thinning after 12,000 points while retaining segment boundaries. Recorded distance is computed before thinning.
- Atomic JSON is saved in Application Support with iOS file protection, periodically and on pause/end. Interrupted sessions remain labeled as saved portions. Users can delete saved routes.
- `MKMapView` draws mint polylines with start/last-position pins. Saved summaries include recorded distance, duration, check-ins, alarms and timestamps.
- Sharing requires a fresh fix. `ShareLink` opens the native share sheet with an Apple Maps coordinate URL, measurement timestamp and accuracy. The user chooses the recipient.
- This is a location snapshot, not continuous remote tracking. Routes are not uploaded to the fleet webhook or assistant.

## Mascot asset

Built-in ImageGen generated the transparent owl; alpha is preserved in `iOS/JaagteRaho/Resources/Assets.xcassets/SaarthiCompanion.imageset/mascot.png`. It is displayed as Ollie in onboarding, the dashboard, conversation and monitoring controls.

Generation prompt:

> Use case: stylized-concept. Asset type: transparent mascot illustration for Saarthi, a native iPhone companion app for Indian truck drivers. Primary request: one friendly, watchful owl road companion with warm open eyes, rounded mint-teal plumage, a small amber scarf, and a simple amber sun badge. Style: polished soft 3D illustration with tactile matte surfaces, expressive but calm and trustworthy, sophisticated app mascot rather than a children's toy. Full body, front-facing with a slight three-quarter turn, one wing gently raised in greeting. Composition: centered single character, generous clear margin, readable at 96 pixels. Palette matches dark midnight, mint, and amber UI. Real transparent background, clean alpha edge, no platform, no scene, no text, no lettering, no watermark, no extra characters.

## Validation scope

The integrated checks cover 36 Swift core checks, 30 backend tests, credential checks and Swift parsing. Tests include enrollment freshness/open-eye requirements, voice turn boundaries, authenticated bounded WAV uploads, no recording storage, Electron routing with only a Smallest key, conversation history validation and malformed provider output. The simulator app and unsigned iPhone build compile with the real MediaPipe frameworks and resources. Live Pulse transcription, Electron conversation and Lightning WAV generation succeeded using the supplied key. GPS accuracy, microphone recognition, music-library playback, phone speaker routing and sustained camera performance still need physical-device acceptance.

Official API references: [Smallest Pulse](https://docs.smallest.ai/models/speech-to-text/quickstart), [Smallest Electron](https://docs.smallest.ai/models/api-reference/llm-chat-completions/electron-chat-completions), [Smallest Lightning](https://docs.smallest.ai/model-cards/text-to-speech/lightning-v-3-1), [Core Location authorization](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization()), [music picker](https://developer.apple.com/documentation/mediaplayer/displaying-a-media-picker-from-your-app), [MapKit overlays](https://developer.apple.com/documentation/mapkit/mapkit-overlays).
