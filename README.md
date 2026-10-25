# NotchIsland

A Dynamic Island–style companion for the MacBook notch. Hover the notch to expand it into a live panel with media controls, the time, and battery status.

## Status

Prototype (v0.1). Working:

- Notch overlay that expands on hover with a spring animation
- Now playing for Apple Music and Spotify: artwork, progress, play/pause/skip/seek
- Live "ears" beside the notch while audio plays, tinted from the artwork
- Charging and unplugged alerts
- Clock, date and week strip
- Right-click the island for Open at Login and Quit

## Build and run

Needs macOS 14+ and the Swift toolchain (Command Line Tools are enough for the prototype).

```bash
./scripts/build-app.sh
open build/NotchIsland.app
```

The first time it reads Music or Spotify, macOS asks for Automation permission.

## Architecture

- `Notch/`: the panel over the notch, hover tracking, and the island's shape and views
- `Media/`: `MediaSource` protocol plus sources. `ScriptableAppSource` covers Music and Spotify; the Chrome extension bridge and the system-wide Now Playing source (direct-download edition) plug in here
- `Widgets/`: media, clock and battery views, and the battery service

## Roadmap

- v1: Xcode project, sandboxed App Store build, Chrome extension bridge (YouTube, YouTube Music, Netflix web), calendar events
- v1.1: Safari extension
- v2: on-device assistant in the island (Apple Foundation Models), App Intents for Siri and Shortcuts
