#!/bin/bash
# Builds a runnable NotchIsland.app with the Command Line Tools (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=build/NotchIsland.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/NotchIsland "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Built $APP"
