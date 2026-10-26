# NotchIsland handoff

State of the project as of 26 October 2026, for picking the work back up.

## What NotchIsland is

A Dynamic Island for the MacBook notch, built in SwiftUI for macOS 14+, with real Liquid Glass on macOS 26+. It's a resume project: the owner targets AI/ML roles and iOS/macOS companies. It ships as two editions from one codebase:

| Edition | Xcode target | Bundle ID | Notes |
|---|---|---|---|
| App Store | `NotchIsland` | `com.aatmanpandya.NotchIsland` | Sandboxed, public APIs only, no updater |
| Direct download | `NotchIsland Direct` | `com.aatmanpandya.NotchIsland.Direct` | Hardened runtime, system-wide Now Playing helper, Sparkle updates. The owner's daily copy |

Repo: https://github.com/aatmanpandya/NotchIsland (public, MIT).

## Done

- **Island:** notch overlay, hover to expand, iOS-style motion (bouncy spring, content grows into focus; Classic style kept), black notch band fading into clear Liquid Glass, glass rim, preview mode (`NOTCHISLAND_PREVIEW=<state>`).
- **Tabs:** Home (player + Up next), Shelf (70% shelf, 30% AirDrop zone), Tools (Timer | Stopwatch switch, plus camera mirror). Remembers the last tab across restarts.
- **Media:** Music and Spotify (AppleScript), Chrome/Arc/Edge/Brave via the extension (YouTube, YT Music, Netflix, Spotify web, SoundCloud, Twitch, ...), and system-wide Now Playing in the direct edition. Next/previous use the page's Media Session handlers; YouTube "previous" returns to the last video watched in the tab. Duplicates of the same title prefer the dedicated source over the system one. Paused tabs keep reporting; tabs resync when the extension reconnects.
- **Extension security:** fixed extension ID via the public key in `manifest.json`; the app only accepts `chrome-extension://fjhaakdelmjpbelljbjggikdioknjkmg`, loopback only, and logs turned-away connections.
- **Pop-ups:** charging, unplugged, fully charged, low battery at 20%/10% and on unplug at or below 20% (with a real Low Power toggle in the direct edition via `pmset` + admin prompt), new track, call started (browser calls), meeting in N minutes (Join), timer done (alarm loops until Dismiss/+1 min), Bluetooth connect (battery % in direct), slim notch-height volume and brightness. Pop-ups with buttons don't open the panel on hover.
- **Up next:** EventKit; next event, countdown, Join for Meet/Zoom/Teams/etc., reminder 1/5/10/15 min before.
- **Tools:** iPhone Clock-style timer (wheels, label, alert sound, cancel/start, ears or split bubble while music plays), stopwatch with laps, camera mirror.
- **Shelf:** drag files toward the notch, kept as bookmarks until cleared, thumbnails, drag out, AirDrop zone.
- **Live visualizer (opt-in):** Core Audio process tap + FFT; asks for system audio at most once per launch. Currently switched off for the owner.
- **Volume key takeover (direct, opt-in, needs Accessibility):** only volume up/down; mute, play/pause and brightness always stay with macOS. Currently off.
- **Settings and onboarding:** General, Media, Pop-ups, About; four-page first run; ⌃⌥⌘N opens and focuses the island for VoiceOver/Tab, Esc closes it.
- **Engineering:** XcodeGen project (`project.yml`; `.xcodeproj` not committed), two entitlement files, icon asset catalog drawn by `scripts/make-icon.swift`, 28 unit tests (`swift test -Xswiftc -DDIRECT_DISTRIBUTION`), VoiceOver labels, diagnostics log at `~/Library/Logs/NotchIsland/keys.log`.
- **Distribution (direct):** Sparkle with an EdDSA key in the owner's login Keychain (public key in `scripts/make-direct-plist.sh`), `appcast.xml` feed in the repo, `scripts/make-dmg.sh`, `scripts/release.sh <version>`. No release published yet.

## Remaining plan

1. **Owner:** create a free Apple Development certificate (Xcode → Settings → Accounts → Manage Certificates → + → Apple Development). Then do one final rebuild so permissions persist across builds; the build script picks the certificate up automatically.
2. **Owner:** join the Apple Developer Program ($99/year) for Developer ID signing, notarization and App Store submission.
3. **Notarize** the direct edition: set `SIGN_IDENTITY` (Developer ID Application) and `NOTARY_PROFILE` (`xcrun notarytool store-credentials`), run `./scripts/make-dmg.sh`, test the DMG on a clean user account.
4. **First release:** `./scripts/release.sh 0.11.0`. Ask the owner before publishing. Verify Check for Updates finds it.
5. **App Store submission:** set the team in `project.yml`, archive the `NotchIsland` target, App Store Connect record, screenshots, description, privacy policy URL, privacy labels, and review notes explaining the Apple Events exception (Music/Spotify) and the overlay window.
6. **Sandbox checks still owed:** shelf drag and drop with bookmarks across relaunch, Music/Spotify control, calendar, camera and Bluetooth prompts in the App Store build.
7. **Chrome Web Store:** $5 developer account, listing, privacy policy; then add the store's extension ID to `BrowserBridgeSource.allowedOrigins`.
8. **Not yet tested live:** VoiceOver with ⌃⌥⌘N, Voice Control, visualizer with real audio, a real Bluetooth connect, external display without a notch, full-screen apps.
9. **Later:** Safari extension (v1.1); v2 on-device AI assistant in the island (Apple Foundation Models, App Intents for Siri/Shortcuts).

## Gotchas learned the hard way

- **Permissions reset on every ad-hoc rebuild** (Accessibility, system audio, calendar, camera). Until the certificate exists, build test copies with `OUT=build/preview ./scripts/build-app.sh` so the owner's running copy keeps its identity.
- **macOS 27 renamed Accessibility** to *Device Control and Data Access*. Re-granting means removing the app with **−** and adding it again, not toggling.
- **macOS 27 reverts brightness set by apps** within about 0.3 s, so brightness keys must stay with macOS.
- **The hardened runtime refuses Sparkle under ad-hoc signing** (different "developer"), so the build script turns it off for local builds without a certificate.
- **Don't edit the built Info.plist after Xcode processes it**: it races and can break the signature. Edition-specific keys come from `scripts/make-direct-plist.sh` (run by XcodeGen's `preGenCommand`).
- **Each edition builds in its own DerivedData** (`.build/xcode-<edition>`) so nothing leaks between them.
- **The helper dylib is copied, not linked**; linking it makes the app fail at launch with "Library missing".
- **Identity:** commits use `Aatman Pandya <134851865+aatmanpandya@users.noreply.github.com>` (repo-local config). The work identity (aatmandx, dxfactor email) must never appear here. Use `command gh` to avoid the shell hook that changes the global git identity.
- **Screenshots:** relaunch-with-preview sometimes races (`open` error -600 or an old instance still running); wait for the process to exit before relaunching.
