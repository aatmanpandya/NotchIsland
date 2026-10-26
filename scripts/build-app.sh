#!/bin/bash
# Builds NotchIsland.app with Xcode (the project is generated from project.yml).
#
#   ./scripts/build-app.sh                    direct-download edition (system-wide Now Playing)
#   EDITION=appstore ./scripts/build-app.sh   App Store edition (sandboxed, public APIs only)
#
# The result is copied to build/NotchIsland.app.
set -euo pipefail
cd "$(dirname "$0")/.."

EDITION=${EDITION:-direct}
case "$EDITION" in
  direct) SCHEME="NotchIsland Direct" ;;
  appstore) SCHEME="NotchIsland" ;;
  *) echo "Unknown EDITION '$EDITION' (use direct or appstore)" >&2; exit 1 ;;
esac

# Sign with an Apple Development certificate when there is one, so macOS keeps permissions
# (Accessibility, system audio, camera) across rebuilds. Without one, sign to run locally,
# and macOS asks for permissions again after each build.
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/' || true)

xcodegen generate --quiet
xcodebuild -project NotchIsland.xcodeproj -scheme "$SCHEME" -configuration Release \
  -derivedDataPath .build/xcode CODE_SIGN_IDENTITY="${IDENTITY:--}" build -quiet

rm -rf build/NotchIsland.app
mkdir -p build
cp -R ".build/xcode/Build/Products/Release/NotchIsland.app" build/
echo "Signed with ${IDENTITY:-an ad-hoc identity}"
echo "Built build/NotchIsland.app ($EDITION edition)"
