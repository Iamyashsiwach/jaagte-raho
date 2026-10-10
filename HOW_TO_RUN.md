# Run SAARTHI with Ollie on your iPhone

Use the demo repository: **https://github.com/Sudhanshu069/jaagte-raho**, branch **main**.

## 1. Prepare your Mac and download the app

Install **full Xcode** from the Mac App Store, open it once, and finish downloading its components. Install Homebrew if it is not already available. Then run:

```sh
git clone https://github.com/Sudhanshu069/jaagte-raho.git
cd jaagte-raho
brew install xcodegen cocoapods node
./scripts/bootstrap.sh
open iOS/JaagteRaho.xcworkspace
```

If you already have the original repository, run these inside that checkout instead of cloning again:

```sh
git fetch https://github.com/Sudhanshu069/jaagte-raho.git main
git merge --ff-only FETCH_HEAD
./scripts/bootstrap.sh
open iOS/JaagteRaho.xcworkspace
```

The app workspace is **iOS/JaagteRaho.xcworkspace**. Select the **JaagteRaho** scheme. The root Swift package is the core library, not the iPhone app.

## 2. Sign and install on your iPhone

1. Connect your iPhone to your Mac by cable, unlock it, and tap **Trust**.
2. On the iPhone, enable **Settings → Privacy & Security → Developer Mode**; restart if prompted.
3. In Xcode, open **Settings → Accounts** and add your Apple ID.
4. Select the **JaagteRaho** project, then the **JaagteRaho** target → **Signing & Capabilities**. Enable **Automatically manage signing** and select your team. If Xcode says the bundle identifier is unavailable, change it to a unique identifier for your team.
5. Select your attached iPhone as the run destination and press **⌘R**.
6. If iOS asks you to trust the developer, open **Settings → General → VPN & Device Management** and trust your developer profile.

The camera and eye detection work locally. Online speech needs the backend in the next step. No provider key is embedded in the iPhone app.

## 3. Start Smallest.ai online voice

Get **friend-demo.env** privately from Sudhanshu. Save it as **.env** directly inside the `jaagte-raho` folder, next to this guide. Finder may hide files beginning with a dot; **⌘⇧.** shows them.

The provided file already contains `SMALLEST_API_KEY`, `APP_TOKEN`, and `HOST=0.0.0.0`. Do not add the file to Git. A template is available in `.env.example`; a blank template will not connect online voice.

Open a terminal in the repo and run:

```sh
node --version
npm --prefix server start
```

Node must be version **20.12 or newer**. This backend uses no npm dependencies, so `npm install` is unnecessary. Keep this terminal running for the demo.

In another terminal, check that it is running and get your Mac's name:

```sh
curl http://localhost:8787/health
scutil --get LocalHostName
```

The health response should be `{"ok":true}`. If the Mac name is `Yash-MacBook-Pro`, use **http://Yash-MacBook-Pro.local:8787** on the phone. Do not use `localhost` on a physical iPhone; that means the phone itself.

## 4. Pair the app with your Mac

1. Put the iPhone and Mac on the **same Wi-Fi**.
2. Open SAARTHI → **Settings** using the sliders button on the home screen.
3. In the voice connection section, enter **http://YOUR-MAC-NAME.local:8787** and the exact **APP_TOKEN** from your `.env` file.
4. Connect and allow **Local Network** access. Allow incoming Node connections if macOS asks.
5. Keep online voice enabled. A successful connection shows **Smallest.ai online voice connected**.
6. Open Ollie's companion screen, select **Hindi** or **English**, and tap **Talk to Ollie**. Allow Microphone, speak, then pause or tap **Finish reply**. The app transcribes with **Smallest Pulse**, replies with **Electron**, and speaks with **Lightning**. Enable Hands-free turns to listen again after the reply. Try a story or quiz too.

Your supplied `SMALLEST_API_KEY` powers all three stages, including open-ended AI replies; **no OpenAI key is required**. Punjabi microphone input uses Apple recognition; use Hindi or English for the Smallest listening path. If selecting **My assistant**, configure its HTTPS `ASSISTANT_URL`/`ASSISTANT_TOKEN` on the backend.

After pulling an update, stop the old backend with **Ctrl+C** and run `npm --prefix server start` again. Rebuild the iPhone app. An older running backend will not have the new transcription endpoint.

## 5. Enroll your eyes and demonstrate detection

Stay parked for this setup and demonstration. Mount the iPhone facing you, with your full face visible and good light.

On Home, choose **Set up my eyes with Ollie** and confirm that you are parked. First-launch onboarding also leads directly into this setup. Allow the camera. Ollie speaks each step in your selected language: keep both eyes open for **3 seconds**, then gently close both eyes for **2 seconds**. Progress follows actual face samples; missing face tracking resets the current step. Allow microphone and speech access if you want spoken replies.

When **Eye setup complete** appears, open both eyes and press **Start monitoring with Ollie**. The button requires a fresh camera view of both eyes open. Calibration does not automatically begin monitoring while your eyes are still closed. This setup is repeated for each real monitoring session; eye baselines stay in memory for that session.

Monitoring uses the calibrated eye signals, yawn candidates and head nods. Prolonged closure prompts a voice check-in around **1.5 seconds** and an alarm around **3 seconds**. Confirm that you are safely parked to end the session and silence a latched alarm.

For a predictable presentation without camera calibration, use **Start synthetic demo**. It is labeled as simulated. Hold **Close eyes** to show the check-in and alarm; it does not record a real journey or notify a fleet owner.

## 6. Routes, sharing and music

- Enable **Record my journey**. Real route recording runs during a real monitoring/setup session while the app stays open; the synthetic demo never records a route.
- Open **Your journey**, refresh your location, then use the native share sheet to share a timestamped location snapshot. This is not continuous remote tracking.
- Open Ollie's companion screen and choose music from the iPhone's library. Voice prompts and alarms pause playback. Library availability depends on the phone.

## Simulator alternative

Install an iOS simulator runtime in Xcode if needed. Save the privately supplied credentials as `.env` in the repository root, then run:

```sh
./scripts/run-presentation.sh
```

This command starts or reuses the backend, regenerates the Xcode project, builds and launches the app, grants simulator camera, microphone, location and music-library access, and pairs voice using the local `.env`. It opens Device Hub on Xcode 27 or Simulator on earlier Xcode. Allow Speech Recognition once if iOS asks when starting the synthetic demo. Allow any Mac microphone prompt from Device Hub so the simulator can hear you.

Use **Start synthetic demo** to present eye closure, check-ins and the alarm; real eye enrollment needs an iPhone camera. Hindi or English **Talk to Ollie**, typed conversation, stories and quizzes use the running backend. Simulator location and music-library contents depend on what you configure in Xcode.

## If something fails

- **Wrong project/scheme:** open the workspace and select JaagteRaho, not JaagteRahoCore.
- **Missing xcodegen or pod:** run `brew install xcodegen cocoapods`, then bootstrap again.
- **Signing error:** select your own Apple team and a unique bundle identifier in Xcode.
- **Voice cannot connect:** keep the backend running; check the Mac `.local` name, Wi-Fi, Local Network permission and exact pairing token. On a phone, `localhost` is incorrect.
- **Port 8787 already in use:** stop the other backend before starting another copy.
- **Camera unavailable:** allow Camera in iPhone Settings and restart setup while parked.
- **Calibration stuck:** keep the whole face in view, improve lighting, and follow the open/closed instruction for the current step.
- **Talk to Ollie fails:** pull the latest `main`, rebuild the app, stop/restart the backend, reconnect in Settings, and choose Hindi or English. Allow Microphone in iPhone Settings. Online Pulse listening needs the paired backend; Punjabi uses Apple recognition. The alarm still works independently.

For the architecture and assistant endpoint contract, see [docs/FEATURE_SPECS.md](docs/FEATURE_SPECS.md).
