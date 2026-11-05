# Dynamac Island — Design

Native macOS (14+) Dynamic-Island-style app inspired by Alcove. Swift 6, SwiftUI + AppKit, built with SwiftPM and bundled into `Dynamac Island.app` (LSUIElement, ad-hoc signed) by `scripts/bundle.sh`.

_Originally written 2026-10-31; updated to reflect the shipped app (music player, Alcove-changelog features, bug fixes)._

## Architecture
- **`ActivityCenter`** (shared): HUD, transient live activities, countdown timer, suspension, upcoming calendar event, dismissed activity.
- **`AppActivities`**: shared services handed to every island (`NowPlayingService`, `BatteryService`, `CalendarService`, `ShelfStore`).
- **`IslandController` + `IslandViewModel`** (one per display): window, notch geometry, hover/expand state, tab, drag/drop, effect mounting.
- **`IslandCore`** (testable library): `ShelfStore`, `CountdownTimer`, `ArtworkPalette`.

## Window
- Borderless, non-activating `NSPanel` above the menu bar, top-center of each island's display. Joins all spaces. In Mission Control it is stationary (visible) or transient (hidden), depending on the setting.
- One display (selected, default: the display with the menu bar) or all displays.
- Notch displays: the collapsed size matches the notch. Non-notch displays: a simulated notch or a floating pill. Width and height can be fine-tuned.
- States: `collapsed` → `peek` (hover) → `expanded` (click, or hover when "expand on hover" is on), with an optional hover delay. Collapsing uses a non-bouncing animation so the island never gets shorter than the hardware notch.
- The window frame is fixed at the maximum size; transparent pixels are click-through.
- The mouse-inside check runs in screen space and includes the edges. The screen's top row counts as inside, which prevents open/close flicker when the pointer sits at the very top.
- Hidden (ordered out) while the display sleeps or the session is inactive, when a fullscreen app is on that display, or while a game is frontmost. Optionally excluded from screen capture (`sharingType = .none`).

## Layout (expanded)
- Header: Home / Shelf tabs on the left; Calendar and Timer icons (with a status dot) and a Battery badge on the right. No clock or settings button; Settings is in the menu bar.
- Home: the music player only. Calendar, Timer and Battery are panels opened from the corner icons.
- Gestures: swipe left/right to skip; swipe down to expand or cycle panels; swipe up to collapse or dismiss a live activity; middle-click to cycle.

## Black-hole effects (selectable)
1. **Accretion**: rotating gradient ring with a glow.
2. **Event horizon**: dark lensing shadow and a shimmering photon ring.
3. **Vortex**: counter-rotating dashed spirals.

Shown on peek and expanded, and stronger on drag-over. They can take the album colors while music plays. Intensity is animatable; the effect stays mounted while it fades out, then unmounts so it costs nothing when idle. The Shelf drop zone uses a procedural `BlackHoleIcon` that spins only during drag-over.

## Features
- **Now Playing**: every media source through the bundled `ungive/mediaremote-adapter` (BSD-3), run via `/usr/bin/perl` because MediaRemote access is restricted on macOS 15.4+. It falls back to AppleScript for Music/Spotify. The adapter runs behind a `sh` wrapper tied to an stdin pipe, so it exits with the app, even after `kill -9`.
  - Player: album-palette theme, blurred-artwork background, scrubbable gradient progress, shuffle / repeat / repeat-one, favorite (Apple Music), speed (non-Music/Spotify sources), copy link, marquee titles, Lossless / Hi-Res badges, playing-app icon, artwork glare and dimming when paused.
  - Collapsed: artwork plus a waveform animated by Core Animation keyframes (render server, ~0% app CPU).
- **Calendar** (EventKit): next 3 events in 24 h, with declined and subscribed/birthday calendars filtered out. Open in Calendar, Fantastical or Notion Calendar. An upcoming-event live activity starts N minutes before an event, with a time-to-leave alert, scheduled by one-shot timers.
- **Timer**: presets from 1 minute to 1 hour, with one one-shot `Timer` at the end date. The ring runs a single linear animation (fills in on start, freezes on pause, removed when idle). The controls column has a fixed width so the ring never shifts sideways.
- **Battery** (IOKit notifications): level, time to empty or full, charging sound, low-battery alerts at 20/10/5%, and Low Power Mode alerts.
- **Connectivity**: `IOBluetooth` connect/disconnect notifications, with AirPods battery when available.
- **Focus**: a vnode watcher on `~/Library/DoNotDisturb/DB` (needs Full Disk Access).
- **HUD replacement**: `CGEventTap` on media keys. Volume via CoreAudio and brightness via DisplayServices. Optional percentage, visible mute, bounce at the limits, glow, and Smooth / Fast / Instant speed. Needs Accessibility.
- **Shelf**: files are stored as bookmarks in `~/Library/Application Support/Dynamac Island/shelf.json`. Dragging out always copies. Missing files are pruned.
- **Notifications from other apps are not shown**: there is no public API for it.

## Energy
- No polling. Every service is driven by system notifications or one-shot timers, except the 0.5 s exit check, which runs only while the island is open.
- Animations exist only while visible; the waveform and timer ring run in the render server.
- Measured: ~0% CPU for the app and the adapter, idle and while music plays.

## Settings & onboarding
- Tabbed Settings: General, Island, Music, Activities, HUD.
- On first launch, a permissions checklist (Accessibility, Calendar, Automation, Bluetooth, Full Disk Access). It is also available from the menu bar.

## Testing
- Unit tests (`scripts/test.sh`) for `ShelfStore`, `CountdownTimer` and `ArtworkPalette`.
- UI behaviour is checked manually with synthetic input, screenshots and screen recordings.
