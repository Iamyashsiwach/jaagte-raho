# Pull, build and demo on another iPhone

The current demo build is published at [Sudhanshu069/jaagte-raho](https://github.com/Sudhanshu069/jaagte-raho) on `main`. For a fresh checkout:

```sh
git clone https://github.com/Sudhanshu069/jaagte-raho.git
cd jaagte-raho
```

If you already cloned `Iamyashsiwach/jaagte-raho`, bring in the demo build with:

```sh
git fetch https://github.com/Sudhanshu069/jaagte-raho.git main
git merge --ff-only FETCH_HEAD
```

Then install dependencies and open the app workspace:

```sh
brew install xcodegen cocoapods
./scripts/bootstrap.sh
open iOS/JaagteRaho.xcworkspace
```

Open the **workspace**, select **JaagteRaho**, choose your Apple signing team and attached trusted iPhone, then Run. Do not build the root `JaagteRahoCore` Swift package as the app. Developer Mode and developer trust are required on the phone. Each Mac uses its own signing team; no provider key or Apple account is included in Git.

## Online voice at the demo

One host Mac can serve phones on the same Wi-Fi. Its ignored root `.env` needs `SMALLEST_API_KEY`, a random `APP_TOKEN` of at least 24 characters, and `HOST=0.0.0.0`.

```sh
cd server
npm start
```

On the host, find its local name with `scutil --get LocalHostName`. In the iPhone app's Settings, pair with `http://HOSTNAME.local:8787` and enter the host's APP_TOKEN privately. Allow Local Network access. The token is stored in Keychain; Smallest credentials stay on the host. Keep online voice enabled. A successful connection displays “Smallest.ai online voice connected.”

The supplied Smallest key powers Hindi/English microphone transcription through Pulse, AI replies through Electron, and speech through Lightning; no OpenAI key is required. Punjabi voice input uses Apple recognition. See [feature specs](FEATURE_SPECS.md) for the custom assistant contract. A deployed backend should use HTTPS. After pulling updated server code, stop and restart the backend before testing Talk to Ollie.

For the simulator, `./scripts/run-simulator.sh` injects pairing information from the local ignored `.env` at launch, without embedding secrets in the app. Start the backend first. The helper uses local ad-hoc signing so Keychain pairing works without an Apple signing account, and opens Device Hub on Xcode 27 or Simulator on earlier Xcode versions.

For a complete simulator presentation, run `./scripts/run-presentation.sh` instead. It starts or reuses the backend, regenerates the project, grants camera, microphone, foreground location and music-library permissions, and launches the paired app. Allow Speech Recognition on its first prompt and allow Device Hub to use the Mac microphone if macOS asks. Use the synthetic demo for the eye-closure flow; live camera enrollment requires a physical iPhone.

## Two-minute demo

1. Meet **Ollie** in onboarding, choose the language, and play the live online voice preview. The fourth step leads into eye enrollment while parked; you can also explore Home first.
2. On the dashboard, open the companion. Play the story, start the quiz, and demonstrate voice or typed replies. Show the online voice source label.
3. Choose a song from the phone's library; demonstrate that a voice prompt pauses it.
4. Open Your journey, enable recording, refresh location and show the native share sheet. Select a recipient yourself if actually sharing.
5. While parked, tap **Set up my eyes with Ollie** on Home. Follow the spoken open-eye (3 seconds) and closed-eye (2 seconds) steps. Open your eyes, then tap **Start monitoring with Ollie** after enrollment completes. For a predictable screen presentation use the visibly labeled synthetic demo; it doesn't record a route or send fleet alerts.
6. Close simulated eyes to show the check-in and alarm; confirm parked/end session to stop the alarm. Show saved alerts and any recorded real journey.

Fresh installations show onboarding. Settings → “Meet Ollie again” replays it. New GPS/voice/music behavior must be checked on the actual demo phone; the simulator cannot establish their real-world performance.
