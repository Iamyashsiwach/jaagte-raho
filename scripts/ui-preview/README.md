# Mac UI preview

This temporary harness compiles the actual iOS SwiftUI views, `DriveModel`, calibration collector and fatigue engine unchanged as a Mac Catalyst application. The permanent preview banner identifies it as a UI preview.

Preview-only replacements disable the camera, microphone, audio, network, Keychain and persistent event storage. The camera surface is explicitly labeled as a placeholder. The synthetic demo still runs through the real fatigue engine; the Alarm preview control closes the simulated eyes and waits for the real escalation threshold.

On an Apple Silicon Mac with full Xcode installed and its license accepted, run from the repository root:

```sh
python3 scripts/ui-preview/build_preview.py
open "build/UI-Preview/Jaagte Raho UI Preview.app"
```

This is an interface preview, not a substitute for compiling, installing or testing the real iPhone app. The source is tracked under `scripts/ui-preview`; generated app files stay in the ignored `build/UI-Preview` directory. No CocoaPods dependency or provider API key is required for this preview.

`Home`, `Calibration`, `Demo` and `Alarm` are preview controls outside the actual app UI. Calibration intentionally stays incomplete because no camera samples are available.
