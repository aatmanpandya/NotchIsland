#!/bin/bash
# Builds NotchIsland.app with Xcode (the project is generated from project.yml).
#
#   ./scripts/build-app.sh                    direct-download edition (system-wide Now Playing)
#   EDITION=appstore ./scripts/build-app.sh   App Store edition (sandboxed, public APIs only)
#
# The result is copied to build/NotchIsland.app, or to $OUT/NotchIsland.app when OUT is set
# (handy for test builds that shouldn't replace the copy you're running).
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
# Releases set SIGN_IDENTITY to the "Developer ID Application: ..." certificate for notarization.
IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/' || true)}

# The hardened runtime only loads frameworks (Sparkle) signed by the same developer as the app.
# Ad-hoc signing has no developer, so local builds without a certificate turn it off; real
# release builds are signed by one developer and keep it.
RUNTIME=()
[ -z "$IDENTITY" ] && RUNTIME=(ENABLE_HARDENED_RUNTIME=NO)
# Notarization also needs a secure timestamp on every signature.
[ -n "${SIGN_IDENTITY:-}" ] && RUNTIME+=(OTHER_CODE_SIGN_FLAGS=--timestamp)

xcodegen generate --quiet
xcodebuild -project NotchIsland.xcodeproj -scheme "$SCHEME" -configuration Release \
  -derivedDataPath ".build/xcode-$EDITION" CODE_SIGN_IDENTITY="${IDENTITY:--}" ${RUNTIME[@]+"${RUNTIME[@]}"} build -quiet

OUT=${OUT:-build}
rm -rf "$OUT/NotchIsland.app"
mkdir -p "$OUT"
# Each edition builds in its own folder, so nothing from one (like the updater) leaks into the other.
cp -R ".build/xcode-$EDITION/Build/Products/Release/NotchIsland.app" "$OUT/"
echo "Signed with ${IDENTITY:-an ad-hoc identity}"
echo "Built $OUT/NotchIsland.app ($EDITION edition)"
