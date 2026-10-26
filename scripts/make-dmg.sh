#!/bin/bash
# Packages the direct-download edition as build/NotchIsland-<version>.dmg: the app next to an
# Applications shortcut, the usual drag-to-install window.
#
# To notarize (needs an Apple Developer Program membership), set:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE=<name saved with `xcrun notarytool store-credentials`>
set -euo pipefail
cd "$(dirname "$0")/.."

# Built into its own folder so the copy you're running (and its permissions) stays untouched.
EDITION=direct OUT=build/release ./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/release/NotchIsland.app/Contents/Info.plist)
DMG="build/NotchIsland-$VERSION.dmg"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R build/release/NotchIsland.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "NotchIsland" -srcfolder "$STAGE" -format UDZO -ov -quiet "$DMG"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  codesign --sign "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application certificate}" --timestamp "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  echo "Notarized $DMG"
else
  echo "Not notarized: macOS will warn people who download it. Set SIGN_IDENTITY and NOTARY_PROFILE once you have a Developer ID certificate."
fi
echo "Built $DMG"
