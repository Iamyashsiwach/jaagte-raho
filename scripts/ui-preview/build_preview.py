#!/usr/bin/env python3
"""Compile unchanged iOS SwiftUI views as a clearly labeled Mac Catalyst UI preview."""
from pathlib import Path
import plistlib
import subprocess

source = Path(__file__).resolve().parent
root = source.parents[1]
output = root / "build/UI-Preview"
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
sdk = Path(sdk)
app = output / "Saarthi UI Preview.app"
contents = app / "Contents"
executable = contents / "MacOS" / "JaagteRahoUIPreview"
executable.parent.mkdir(parents=True, exist_ok=True)
sources = [source / "PreviewServices.swift", source / "PreviewApp.swift"]
sources += sorted((root / "iOS/JaagteRaho/Core").glob("*.swift"))
sources += [root / "iOS/JaagteRaho/DriveModel.swift"]
sources += sorted((root / "iOS/JaagteRaho/Views").glob("*.swift"))
command = [
    "xcrun", "swiftc", "-swift-version", "5", "-strict-concurrency=targeted",
    "-target", "arm64-apple-ios16.0-macabi", "-sdk", str(sdk),
    "-F", str(sdk / "System/iOSSupport/System/Library/Frameworks"),
    "-I", str(sdk / "System/iOSSupport/usr/include"),
    "-L", str(sdk / "System/iOSSupport/usr/lib"),
    "-Xlinker", "-rpath", "-Xlinker", "/System/iOSSupport/usr/lib/swift",
    "-o", str(executable),
] + [str(source) for source in sources]
subprocess.run(command, check=True, cwd=root)
with (contents / "Info.plist").open("wb") as destination:
    plistlib.dump({
        "CFBundleName": "Saarthi UI Preview",
        "CFBundleDisplayName": "Saarthi UI Preview",
        "CFBundleIdentifier": "com.jaagteraho.ui-preview",
        "CFBundleExecutable": executable.name,
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1",
        "CFBundleShortVersionString": "0.1",
        "CFBundleSupportedPlatforms": ["MacOSX"],
        "LSMinimumSystemVersion": "14.0",
        "NSPrincipalClass": "NSApplication",
        "UIDeviceFamily": [1, 2],
    }, destination)
subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
print(app)
