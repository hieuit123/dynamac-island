# Dynamac Island

A native macOS Dynamic Island inspired by [Alcove](https://tryalcove.com), with "black hole" border effects and a file shelf.

## Features
- **Island at the notch** (or a pill on non-notch displays): hover to peek, click to expand.
- **Black-hole effects**: Accretion Disk, Event Horizon or Vortex. Choose one in Settings. They show on hover and in the expanded popup, and get stronger while files are dragged over.
- **Shelf**: drop files into the black hole (the drop zone shows a black-hole icon that spins while files hover over it) and drag them out to any app or screen. Dragging out copies the file, and double-click opens it. The shelf stores references to the original files and keeps them across restarts.
- **Now Playing**: Music & Spotify, event-driven:
  - The player takes its colors from the album art: a blurred artwork background, tinted controls, and a gradient progress bar you can drag to seek.
  - Shuffle, repeat (repeat-one in Apple Music) and favorite (Apple Music).
  - The artwork gets a glare sweep on hover and track change, and dims and shrinks when paused.
  - The collapsed island shows an animated waveform in the album's colors. Core Animation runs it outside the app (about 0% app CPU); it stops when paused or in Low Power Mode.
  - Swipe left/right with two fingers on the island to skip tracks.
  - The black-hole effect can take on the album colors while music plays.
- **Layout**: Home shows the music player. Calendar and Timer open from icons in the top-right corner (a colored dot shows the next event or a running timer). Settings is in the menu bar.
- **Calendar**: up to 3 events in the next 24 h (EventKit).
- **Battery**: level, charging state, and a charging live activity when you plug in.
- **Timer**: presets from 1 min to 1 h, with a progress ring and a countdown in the collapsed island.
- **Volume / brightness HUD** replacement (needs Accessibility permission).

## Energy
- No polling. Music, battery, calendar and power state all use system notifications.
- Effects and animations only exist while the island is hovered or expanded, and run at 30 fps in Low Power Mode.
- The timer uses one one-shot `Timer` at its end date. The clock only updates while expanded.
- The window is removed from the compositor while the display sleeps or the session is inactive.
- Measured idle: ~0% CPU, ~25 MB RAM.

## Build & run
Requires macOS 14+ and Swift 5.10+ (Command Line Tools are enough).

```sh
./scripts/bundle.sh          # builds build/Dynamac Island.app
open "build/Dynamac Island.app"
./scripts/test.sh            # unit tests
```

Copy the app to `/Applications` for launch-at-login. The app is ad-hoc signed, so after each rebuild macOS may ask again for Accessibility and Automation permissions (remove the old entry in System Settings → Privacy & Security → Accessibility).
