#!/bin/bash
set -euo pipefail
JR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$JR_ROOT"
./scripts/check-core.sh
node --test server/test.mjs
node scripts/check-secrets.mjs
swiftc -frontend -parse iOS/JaagteRaho/Core/*.swift iOS/JaagteRaho/Camera/*.swift iOS/JaagteRaho/Services/*.swift iOS/JaagteRaho/DriveModel.swift iOS/JaagteRaho/Views/*.swift iOS/JaagteRaho/JaagteRahoApp.swift
printf '%s\n' 'Core/backend/security checks and Swift syntax parsing passed. iOS SDK type checking and device testing require full Xcode.'
