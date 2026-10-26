#!/bin/bash
# Writes the direct edition's Info.plist: the shared one plus Sparkle's update settings, which
# the App Store edition must not have. XcodeGen runs this before generating the project.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=Resources/Generated/Info-Direct.plist
mkdir -p "$(dirname "$OUT")"
cp Resources/Info.plist "$OUT"
/usr/libexec/PlistBuddy \
  -c "Add :SUFeedURL string https://raw.githubusercontent.com/aatmanpandya/NotchIsland/main/appcast.xml" \
  -c "Add :SUPublicEDKey string RARs5p7/48Yf5oMHfXFCEQwD4VM9pno+6iJuGlzW6P4=" \
  -c "Add :SUEnableAutomaticChecks bool true" \
  "$OUT"
