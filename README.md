# Dynamac Island

A native macOS Dynamic Island inspired by [Alcove](https://tryalcove.com), with "black hole" border effects and a file shelf.

## Features
- **Island at the notch** (or a pill on non-notch displays): hover to peek, click to expand.
- **Black-hole effects**: Accretion Disk, Event Horizon or Vortex. Choose one in Settings. They show on hover and in the expanded popup, and get stronger while files are dragged over.
- **Shelf**: drop files into the island and drag them out to any app or screen. Dragging out copies the file, and double-click opens it. The shelf stores references to the original files and keeps them across restarts.
- **Now Playing**: Music & Spotify title, artwork and controls (event-driven).
- **Calendar**: next event in the next 24 h (EventKit).
- **Battery**: level, charging state, and a charging live activity when you plug in.
- **Clock & Timer**: presets with a countdown in the collapsed island.
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
