#!/bin/bash
# Publishes a direct-download release:  ./scripts/release.sh 0.11.0
#
# Bumps the version, builds and (if configured) notarizes the DMG, signs it for Sparkle with
# the key in your Keychain, uploads it as a GitHub release, then adds it to appcast.xml, which
# is what installed copies check for updates.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?Usage: ./scripts/release.sh <version, e.g. 0.11.0>}
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first." >&2; exit 1; }

# Sparkle compares the build number, so it goes up by one every release.
BUILD=$(( $(sed -nE 's/^ *CURRENT_PROJECT_VERSION: *([0-9]+).*/\1/p' project.yml) + 1 ))
sed -i '' -E "s/^( *MARKETING_VERSION: *).*/\1$VERSION/; s/^( *CURRENT_PROJECT_VERSION: *).*/\1$BUILD/" project.yml

./scripts/make-dmg.sh
DMG="build/NotchIsland-$VERSION.dmg"

# The update signature, checked against SUPublicEDKey before any update is installed.
SIGNATURE=$(.build/xcode-direct/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update "$DMG")

gh release create "v$VERSION" "$DMG" --title "NotchIsland $VERSION" --generate-notes

python3 - "$VERSION" "$BUILD" "$SIGNATURE" <<'PY'
import sys
from email.utils import formatdate
version, build, signature = sys.argv[1:]
url = f"https://github.com/aatmanpandya/NotchIsland/releases/download/v{version}/NotchIsland-{version}.dmg"
item = f"""    <item>
      <title>NotchIsland {version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <link>https://github.com/aatmanpandya/NotchIsland/releases/tag/v{version}</link>
      <enclosure url="{url}" type="application/octet-stream" {signature} />
    </item>
"""
path = "appcast.xml"
feed = open(path).read()
marker = "    <!-- Releases are added below, newest first. -->\n"
open(path, "w").write(feed.replace(marker, marker + item))
PY

git add project.yml appcast.xml
git commit -m "Release $VERSION"
git tag "v$VERSION"
git push --follow-tags
echo "Released $VERSION"
