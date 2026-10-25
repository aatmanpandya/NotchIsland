#!/bin/bash
# Builds a runnable NotchIsland.app with the Command Line Tools (no Xcode needed).
#
#   ./scripts/build-app.sh            direct-download edition (system-wide Now Playing)
#   EDITION=appstore ./scripts/build-app.sh   App Store edition (no private APIs)
set -euo pipefail
cd "$(dirname "$0")/.."

EDITION=${EDITION:-direct}
case "$EDITION" in
  direct) SWIFT_FLAGS=(-Xswiftc -DDIRECT_DISTRIBUTION) ;;
  appstore) SWIFT_FLAGS=() ;;
  *) echo "Unknown EDITION '$EDITION' (use direct or appstore)" >&2; exit 1 ;;
esac

swift build -c release --build-path ".build/$EDITION" ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}

APP=build/NotchIsland.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$EDITION/release/NotchIsland" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

if [ "$EDITION" = direct ]; then
  clang -dynamiclib -fobjc-arc -O2 -Wall -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
    -framework Foundation -o "$APP/Contents/Resources/NowPlayingHelper.dylib" \
    Helpers/NowPlayingHelper/NowPlayingHelper.m
  codesign --force --sign - "$APP/Contents/Resources/NowPlayingHelper.dylib"
fi

codesign --force --sign - "$APP"
echo "Built $APP ($EDITION edition)"
