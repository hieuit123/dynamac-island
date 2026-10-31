# Dynamac Island — Design

Native macOS (14+) Dynamic-Island-style app inspired by Alcove. Swift 6, SwiftUI + AppKit, built with SwiftPM and bundled into `Dynamac Island.app` (LSUIElement, ad-hoc signed).

## Window
- Borderless, non-activating `NSPanel` at `.statusBar+` level, top-center of the selected display (default: main/built-in). Joins all spaces, ignores Mission Control.
- Notch screens: collapsed size matches notch (`safeAreaInsets`/`auxiliaryTopLeftArea`). Non-notch: small black pill.
- States: `collapsed` → `hovered` (slightly enlarged, live activity glance) → `expanded` (click; detail popup). Mouse-exit collapses after 0.4 s.
- Window frame is fixed at max size; click-through outside the island shape via `ignoresMouseEvents` toggling driven by a global mouse-moved monitor only near the island area.

## Black-hole effects (selectable in Settings)
1. **Accretion** — rotating angular gradient ring (orange→magenta→violet) with blur glow.
2. **Event horizon** — dark warped shadow + thin shimmering white photon ring.
3. **Vortex** — swirling multi-ring spiral, intensifies when files are dragged over.
Shown on hover, in expanded popup, and amplified on drag-over. Animations use `TimelineView(.animation(paused:))`, paused when not visible.

## Features
- **Now Playing**: Music & Spotify via distributed notifications (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`); controls via AppleScript (play/pause, next, prev). Artwork via AppleScript for Spotify URL / Music artwork data.
- **Calendar**: EventKit, next event within 24 h, refreshed on `EKEventStoreChanged`.
- **Battery**: IOKit `IOPSNotificationCreateRunLoopSource` (event-driven).
- **Clock / Timer**: clock in expanded view; countdown timer with presets, shown as live activity in collapsed island while running.
- **HUD replacement**: `CGEventTap` on `NX_SYSDEFINED` media keys (volume up/down/mute, brightness up/down). Volume via CoreAudio; brightness via `DisplayServices` (dlopen). Event is swallowed so system HUD doesn't appear. Requires Accessibility permission; toggle in Settings; disabled gracefully if denied.
- **Shelf**: drop files on island (any state). Stored as bookmarks persisted in `~/Library/Application Support/Dynamac Island/shelf.json`. Items draggable out (NSItemProvider file URL) to any app / any screen; remove individually or clear all; missing files are pruned.

## Energy
- No polling; all services event-driven. Timers/animations only when visible.
- Pause everything on `screensDidSleep`, `sessionDidResignActive`; resume on wake.
- Clock ticks only while expanded; timer ticks 1 Hz only while running.

## Settings (menu-bar item → Settings window)
Effect style, display, HUD replacement toggle, launch at login (`SMAppService`), show battery/calendar/music toggles.

## Testing
Unit tests for shelf store (persist/load/prune) and timer model. Manual verification of UI.
