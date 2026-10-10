# Ollie and journey features

SAARTHI is the app; **Ollie** is its owl companion. Native SwiftUI, iOS 16+, Swift 5, with no Flutter migration. All changes stay on `main`.

## Presentation flow

Three-step first launch: meet Ollie, select Hindi/Punjabi/English and hear the voice, then choose optional journey recording. Settings can replay the introduction. The dashboard opens the companion hub, journey screen, real camera calibration, and the existing explicitly synthetic demo.

## Online voice and companion

Online voice is enabled by default. The iPhone calls the paired authenticated Node backend; the backend calls Smallest.ai Lightning `lightning_v3.1_pro` at `POST https://api.smallest.ai/waves/v1/tts`. Audio is WAV at 24 kHz; voices are `aviraj` for Hindi, `rajdeep` for Punjabi and `blake` for English. A real English request returned HTTP 200 and a valid WAV during this implementation.

- Apple Speech recognizes input on-device when supported by the chosen language/device. Each listening turn ends on a final transcript or after 12 seconds. Typed input remains available.
- Hands-free turns resume listening after speech playback. Saying “stop” ends the conversation. Microphone/audio permission is requested when starting conversation.
- Original short story and one voice quiz are bundled in all three languages. Their speech is synthesized online with Smallest when connected.
- General conversation uses the existing OpenAI provider if configured, or a custom assistant. Without either conversation provider, local scripted replies are spoken through Smallest; this is explicitly a limited companion rather than an unrestricted LLM chat.
- Only short text goes to the conversation backend. The app does not upload microphone recordings or camera frames.
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

The integrated checks cover 32 Swift core assertions, 23 backend tests, credential checks and Swift parsing. The full iOS simulator app compiles, links, installs and launches with the real MediaPipe frameworks and resources. The unsigned iPhone-target build also passes; Ollie dashboard rendering and the connected online-voice status were visually inspected. A live Smallest speech request succeeded. GPS accuracy, microphone recognition, music-library playback, phone speaker routing and sustained camera performance still need physical-device acceptance.

Official API references: [Smallest Lightning](https://docs.smallest.ai/model-cards/text-to-speech/lightning-v-3-1), [Core Location authorization](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization()), [music picker](https://developer.apple.com/documentation/mediaplayer/displaying-a-media-picker-from-your-app), [MapKit overlays](https://developer.apple.com/documentation/mapkit/mapkit-overlays).
