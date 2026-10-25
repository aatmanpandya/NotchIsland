# NotchIsland

A Dynamic Island–style companion for the MacBook notch. Hover the notch to expand it into a live panel with media controls, the time, and battery status.

## Status

Prototype (v0.8). Working:

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
- Settings window (right-click the island, or open the app again from Finder): open at login, animation, album-art timing, haptics, each media source, each pop-up, meeting reminder timing, calendar access
- First-run onboarding: welcome, media and the browser extension, calendar access, open at login

## Build and run

Needs macOS 14+ and the Swift toolchain (Command Line Tools are enough for the prototype).

```bash
./scripts/build-app.sh
open build/NotchIsland.app
```

There are two editions from the same code:

| Edition | Build | Media sources |
|---|---|---|
| Direct download (default) | `./scripts/build-app.sh` | Browser extension, Music, Spotify, plus system-wide Now Playing for every app |
| App Store | `EDITION=appstore ./scripts/build-app.sh` | Browser extension, Music, Spotify. No private APIs |

The direct edition's system-wide source uses the private MediaRemote framework. Since macOS 15.4 that framework only answers Apple-signed processes, so `Helpers/NowPlayingHelper` is a small library the app loads into `/usr/bin/perl`, which streams JSON lines back over a pipe. A future macOS update could close this route; the other sources keep working if it does.

The first time it reads Music or Spotify, macOS asks for Automation permission.

Building with Xcode's toolchain (macOS 26 SDK or later) enables real Liquid Glass. To hold the island in one state for design work, launch it with a preview state: `expanded`, `upnext` (expanded with sample meetings), `charging`, `unplugged`, `full`, `low`, `nowplaying`, `call`, `meeting`, `tools`, `timer`, `timerdone`, `device`, `shelf` (sample files, not saved) or `dropzone`.

```bash
open --env NOTCHISLAND_PREVIEW=expanded build/NotchIsland.app
```

### Browser extension

1. Open `chrome://extensions` (or the same page in Arc, Edge or Brave) and turn on **Developer mode**.
2. Click **Load unpacked** and choose the `Extensions/Chrome` folder.
3. Reload any tabs that were already open.

The extension talks to the app over a WebSocket on `127.0.0.1:47823`. The app only accepts connections from this Mac and from browser-extension origins, never from web pages.

## Architecture

- `Notch/`: the panel over the notch, hover tracking, and the island's shape and views
- `Media/`: `MediaSource` protocol plus sources. `ScriptableAppSource` covers Music and Spotify, `BrowserBridgeSource` receives browser tabs from the extension, and `SystemNowPlayingSource` (direct edition only, behind `DIRECT_DISTRIBUTION`) reads the system feed through the helper
- `Helpers/NowPlayingHelper/`: Objective-C library that talks to MediaRemote
- `Extensions/Chrome/`: Manifest V3 extension. `page.js` reads the page's media session and players, `relay.js` forwards to `background.js`, which holds the socket to the app
- `Calendar/`: `CalendarService` (EventKit; asks for access only when the user taps the button) and the Up next views
- `Widgets/`: media and battery views, and the battery service
- `Tools/`: timer and stopwatch services, and the Tools tab (timer, stopwatch, camera mirror)
- `Shelf/`: the shelf service (bookmarks) and the Shelf tab
- `Devices/`: Bluetooth connection alerts
- `Settings/`: the Settings window, onboarding, and `AppWindows`, which opens them
- `App/Preferences.swift`: every setting's key and default

## Roadmap

- v1: Xcode project, sandboxed App Store build, pairing between app and extension, Chrome Web Store listing
- v1.1: Safari extension
- v2: on-device assistant in the island (Apple Foundation Models), App Intents for Siri and Shortcuts
