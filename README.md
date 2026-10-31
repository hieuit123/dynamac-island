# Dynamac Island

A native macOS Dynamic Island inspired by [Alcove](https://tryalcove.com), with "black hole" border effects and a file shelf.

## Features
- **Island at the notch**, a simulated notch, or a floating pill on displays without one. Show it on one display or on all of them. Width and height can be fine-tuned.
- **Black-hole effects**: Accretion Disk, Event Horizon or Vortex (chosen in Settings). They show on hover and in the expanded popup, and get stronger while files are dragged over.
- **Shelf**: drop files into the black hole and drag them out to any app or screen. Dragging out copies the file, and double-click opens it. The shelf stores references to the original files and keeps them across restarts.
- **Now Playing for every media source** (browsers, YouTube, Podcasts, Music, Spotify…) through the bundled [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter). If it's unavailable, Music and Spotify still work through AppleScript.
  - The player takes its colors from the album art: blurred artwork background, tinted controls, and a gradient progress bar you can drag to seek.
  - Shuffle and repeat (including repeat-one), favorite (Apple Music), playback speed (podcasts and video), copy song link, and Lossless / Hi-Res badges.
  - Long titles scroll, the playing app's icon is shown on the artwork, the artwork gets a glare sweep, and it dims when paused.
  - The collapsed island shows an animated waveform in the album's colors. Core Animation runs it outside the app, so it costs about 0% CPU.
- **Calendar** (corner icon): next 3 events, with declined and subscribed calendars filtered out. Click an event or the date to open Calendar, Fantastical or Notion Calendar. An upcoming event appears as a live activity, with a time-to-leave alert.
- **Timer** (corner icon): presets from 1 minute to 1 hour, a progress ring, and a countdown in the collapsed island.
- **Battery** (corner badge): level, time to empty or full, charging sound, low-battery alerts at 20 / 10 / 5%, and Low Power Mode alerts.
- **Connectivity**: AirPods and Bluetooth devices show a connect/disconnect activity with battery level.
- **Focus**: shows Focus mode changes with each mode's symbol and color (needs Full Disk Access).
- **Volume / brightness HUD**: optional percentage, visible mute, a bounce at 0 / 100%, glow, and Smooth / Fast / Instant speed (needs Accessibility).
- **Gestures**: swipe left/right to skip; swipe down to expand or cycle panels; swipe up to collapse or dismiss a live activity; middle-click to cycle; optional hover delay.
- **Privacy & visibility**: hide in fullscreen apps, while gaming, or in Mission Control, and hide from screenshots and recordings.
- **Onboarding**: a permissions checklist on first launch, also available from the menu bar.

## Energy
- No polling. Music, battery, calendar and power state all use system notifications.
- Effects and animations only exist while the island is hovered or expanded, and run at 30 fps in Low Power Mode.
- The timer uses one one-shot `Timer` at its end date. The clock only updates while expanded.
- The window is removed from the compositor while the display sleeps or the session is inactive.
- Calendar alerts use one-shot timers at the exact times needed. Focus changes use a kernel file watcher, and Bluetooth, fullscreen and battery changes come from system notifications.
- The MediaRemote adapter only sends updates when playback changes, and exits with the app (even after a crash).
- Measured: ~0% CPU for both the app and the adapter, idle or while music plays; ~27 MB RAM.

## Build & run
Requires macOS 14+ and Swift 5.10+ (Command Line Tools are enough).

```sh
./scripts/bundle.sh          # builds build/Dynamac Island.app (incl. the MediaRemote adapter)
open "build/Dynamac Island.app"
./scripts/test.sh            # unit tests
```

Copy the app to `/Applications` for launch-at-login. The app is ad-hoc signed, so after each rebuild macOS may ask again for Accessibility and Automation permissions (remove the old entry in System Settings → Privacy & Security → Accessibility).

## Third-party
- [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause) is vendored in `Vendor/` and built by `scripts/build-mediaremote.sh`. Its license ships inside the app bundle.
