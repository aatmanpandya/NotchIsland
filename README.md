# NotchIsland

A Dynamic Island–style companion for the MacBook notch. Hover the notch to expand it into a live panel with media controls, the time, and battery status.

## Status

Prototype (v0.2). Working:

- Notch overlay that expands on hover with a spring animation and an artwork-tinted glow
- Now playing from Apple Music, Spotify, and any tab in Chrome, Arc, Edge or Brave (YouTube, YouTube Music, Netflix, Spotify web, SoundCloud, Twitch and any site with a video or audio player)
- Play/pause, skip and seek; click the artwork to jump to the app or tab
- Live "ears" beside the notch while something plays
- Pop-ups: charging (with time to full), unplugged (with time left), fully charged, low battery, and new track
- Clock, date and week strip
- Right-click the island for Open at Login and Quit

## Build and run

Needs macOS 14+ and the Swift toolchain (Command Line Tools are enough for the prototype).

```bash
./scripts/build-app.sh
open build/NotchIsland.app
```

The first time it reads Music or Spotify, macOS asks for Automation permission.

### Browser extension

1. Open `chrome://extensions` (or the same page in Arc, Edge or Brave) and turn on **Developer mode**.
2. Click **Load unpacked** and choose the `Extensions/Chrome` folder.
3. Reload any tabs that were already open.

The extension talks to the app over a WebSocket on `127.0.0.1:47823`. The app only accepts connections from this Mac and from browser-extension origins, never from web pages.

## Architecture

- `Notch/`: the panel over the notch, hover tracking, and the island's shape and views
- `Media/`: `MediaSource` protocol plus sources. `ScriptableAppSource` covers Music and Spotify, `BrowserBridgeSource` receives browser tabs from the extension, and the system-wide Now Playing source (direct-download edition) will plug in here
- `Extensions/Chrome/`: Manifest V3 extension. `page.js` reads the page's media session and players, `relay.js` forwards to `background.js`, which holds the socket to the app
- `Widgets/`: media, clock and battery views, and the battery service

## Roadmap

- v1: Xcode project, sandboxed App Store build, calendar events, pairing between app and extension
- Direct-download edition: system-wide Now Playing for every native app
- v1.1: Safari extension
- v2: on-device assistant in the island (Apple Foundation Models), App Intents for Siri and Shortcuts
