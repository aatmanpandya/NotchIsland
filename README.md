# NotchIsland

A Dynamic Island–style companion for the MacBook notch. Hover the notch to expand it into a live panel with media controls, the time, and battery status.

## Status

Prototype (v0.10). Working:

- Notch overlay that expands on hover with a spring animation
- Liquid Glass design (macOS 26+): solid black where it meets the notch, fading into dark glass with the artwork's color glowing through; frosted blur on macOS 14–15
- Now playing from Apple Music, Spotify, and any tab in Chrome, Arc, Edge or Brave (YouTube, YouTube Music, Netflix, Spotify web, SoundCloud, Twitch and any site with a video or audio player)
- Direct-download edition: every app that reports to macOS Now Playing (VLC, IINA, Apple TV, Podcasts, Safari and more)
- Play/pause, skip and seek; click the artwork to jump to the app or tab
- Live "ears" beside the notch while something plays
- Pop-ups: charging (with time to full), unplugged (with time left), fully charged, low battery at 20% and 10% with a Low Power Mode button, and new track
- Up next: your next calendar event with a countdown and a Join button for Meet, Zoom, Teams and other call links; a reminder pop-up 5 minutes before each meeting
- Call-started pop-up for browser video calls
- Tabs in the expanded island: Home (player and Up next), Shelf, and Tools
- File shelf: drag files toward the notch to park them; kept as links (no extra disk space) until cleared; drag out, open, Show in Finder, AirDrop
- Timer (Tools tab, iPhone Clock layout): scroll wheels, cancel and start, a label and an alert sound; lives in the ears or in a separate bubble while music plays; +1 min / Dismiss pop-up when done; survives restarts
- Stopwatch (Tools tab, next to the timer): laps, and it shows in the ears while running
- Camera mirror (Tools tab): the camera runs only while the preview is showing
- Bluetooth pop-up when AirPods or other devices connect; battery level in the direct edition
- Volume pop-up (public Core Audio; off by default in the App Store edition, since macOS still shows its own) and, in the direct edition, brightness plus an option to take over the volume up and down keys so the system volume pop-up never appears (needs Accessibility). Mute, play/pause and brightness always stay with macOS; on macOS 27 the system reverts brightness changes made by apps
- Opt-in live visualizer: a Core Audio process tap and an FFT (Accelerate) drive the bars from the actual audio; nothing is recorded
- Settings window (right-click the island, or open the app again from Finder): open at login, animation, album-art timing, haptics, each media source, each pop-up, meeting reminder timing, calendar access
- First-run onboarding: welcome, media and the browser extension, calendar access, open at login

## Build and run

Needs macOS 14+ and Xcode 26 or later (for the Liquid Glass SDK). The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), so it isn't committed.

```bash
./scripts/build-app.sh
open build/NotchIsland.app
```

Or `xcodegen generate` and open `NotchIsland.xcodeproj` in Xcode.

There are two editions from the same code, as separate Xcode targets:

| Edition | Target / build | Bundle ID | Media sources |
|---|---|---|---|
| App Store | `NotchIsland` · `EDITION=appstore ./scripts/build-app.sh` | `com.aatmanpandya.NotchIsland` | Browser extension, Music, Spotify. Sandboxed, public APIs only |
| Direct download (default) | `NotchIsland Direct` · `./scripts/build-app.sh` | `com.aatmanpandya.NotchIsland.Direct` | Also system-wide Now Playing for every app. Hardened runtime, for notarization |

Each edition declares exactly what it uses in `Resources/AppStore.entitlements` and `Resources/Direct.entitlements`.

The direct edition's system-wide source uses the private MediaRemote framework. Since macOS 15.4 that framework only answers Apple-signed processes, so the `NowPlayingHelper` target builds a small library that the app loads into `/usr/bin/perl`, which streams JSON lines back over a pipe. A future macOS update could close this route; the other sources keep working if it does.

The first time it reads Music or Spotify, macOS asks for Automation permission. Without an Apple Development certificate, builds are signed to run locally, and macOS asks for permissions again after each rebuild; with one, the build script uses it automatically.

To hold the island in one state for design work, launch it with a preview state: `expanded`, `upnext` (expanded with sample meetings), `charging`, `unplugged`, `full`, `low`, `nowplaying`, `call`, `meeting`, `tools`, `timer`, `timerdone`, `device`, `shelf` (sample files, not saved), `dropzone`, `volume` or `brightness`.

```bash
open --env NOTCHISLAND_PREVIEW=expanded build/NotchIsland.app
```

### Browser extension

1. Open `chrome://extensions` (or the same page in Arc, Edge or Brave) and turn on **Developer mode**.
2. Click **Load unpacked** and choose the `Extensions/Chrome` folder.
3. Reload any tabs that were already open.

The extension talks to the app over a WebSocket on `127.0.0.1:47823`. The app only accepts connections from this Mac, and only from the NotchIsland extension: its ID is fixed by the public key in `manifest.json`, and the app checks the connection's origin against it.

## Tests

```bash
swift test -Xswiftc -DDIRECT_DISTRIBUTION
```

Covers playback position and optimistic updates, which source the island shows, the timer and stopwatch, time formatting, video-call link detection and meeting countdowns.

## App icon

Drawn in code by `scripts/make-icon.swift`, which writes the app icon asset catalog:

```bash
swift scripts/make-icon.swift
```

## Architecture

- `Notch/`: the panel over the notch, hover tracking, and the island's shape and views
- `Media/`: `MediaSource` protocol plus sources. `ScriptableAppSource` covers Music and Spotify, `BrowserBridgeSource` receives browser tabs from the extension, and `SystemNowPlayingSource` (direct edition only, behind `DIRECT_DISTRIBUTION`) reads the system feed through the helper
- `Helpers/NowPlayingHelper/`: Objective-C library that talks to MediaRemote
- `Extensions/Chrome/`: Manifest V3 extension. `page.js` reads the page's media session and players, `relay.js` forwards to `background.js`, which holds the socket to the app
- `Calendar/`: `CalendarService` (EventKit; asks for access only when the user taps the button) and the Up next views
- `Widgets/`: media and battery views, and the battery service
- `Tools/`: timer and stopwatch services, and the Tools tab (timer, stopwatch, camera mirror)
- `Shelf/`: the shelf service (bookmarks) and the Shelf tab
- `Devices/`: Bluetooth alerts, volume (Core Audio), brightness and media-key takeover (direct edition only)
- `Media/LiveSpectrum.swift`: the live visualizer (system audio tap, FFT, four bands with automatic gain)
- `Settings/`: the Settings window, onboarding, and `AppWindows`, which opens them
- `App/Preferences.swift`: every setting's key and default

## Roadmap

- v1: signing and notarization, App Store submission, Chrome Web Store listing, DMG with auto-updates
- v1.1: Safari extension
- v2: on-device assistant in the island (Apple Foundation Models), App Intents for Siri and Shortcuts

## License

MIT. See [LICENSE](LICENSE).
