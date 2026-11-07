# Dynamac Island — 2026-11-07 (part 2): header, battery, timer, calendar

Delta on top of [2026-11-07-dynamac-island-pet-styles-calendar.md](2026-11-07-dynamac-island-pet-styles-calendar.md) (which builds on [2026-10-31-dynamac-island-design.md](2026-10-31-dynamac-island-design.md)). Branch: `feature/header-tooltips-battery-timer-calendar`.

## Summary

| Area | Change |
| --- | --- |
| Header | Home and Shelf are icon-only; every header icon has an instant hover tooltip |
| Battery tab | Two halves: 3-line battery info and a keyboard backlight slider |
| Battery data | Time estimate refreshed on open and while open; system-estimate fallback |
| Timer | Custom hours / minutes / seconds (max 24:00:00), quick buttons, 3:7 layout |
| Calendar | All events in 24 h, scrollable; vertical scroll is no longer a swipe on that tab |
| Build | `AppIcon.icns` generated from `Resources/AppIcon.png` when it exists |
| Reverted | Timer sound picker (the original single Glass sound is kept) |

## Header

- `HeaderIcon` is now used for every header button: Home, Shelf, Pet, Calendar, Timer. `TabButton` (icon plus text) was removed.
- Home: `house.fill`. Shelf: `tray.full.fill`, with a white dot badge when the shelf has files and the tooltip `Shelf (N)`.
- **Instant tooltip** (`InstantTooltip` modifier, `ExpandedView.swift`): the native `.help` waits about a second and cannot be tuned, so a small capsule label is shown through `onHover`. It sits 28 pt below the icon with a 0.1 s fade, ignores hit testing, and the header has `zIndex(1)` so the label draws above the panel. The Battery badge uses the same modifier.
- Risk: `onHover` can be unreliable while the app is never active (see the comment in `AppKitBridges.swift`). If the label does not appear, track the pointer with AppKit instead.

## Battery tab

- **Layout**: `BatteryPanel` is two halves separated by a 1 pt divider.
  - Left: the battery graphic (108 × 62 pt) and three lines: percent, state, remaining time. A Low Power Mode label follows when active.
  - Right: the keyboard backlight control.
- **Three lines** (`BatteryService`)
  - `statusText`: `Charging`, `Charged`, `On power adapter` or `On battery`.
  - `remainingText`: `2h 10m until full`, `1h 20m remaining` or `Calculating…`; nil when fully charged or when no estimate applies.
- **Estimate refresh**: macOS reports `-1` for the time estimate until it has measured the rate, and no power-source event fires when the estimate becomes available, so the value could stay at "calculating". Now `BatteryService.refresh()` runs when the tab appears and every 15 s while it is shown (a `Timer.publish` that only exists while the panel is on screen). If the dictionary value is not positive while on battery, `IOPSGetTimeRemainingEstimate()` is used. If macOS has no estimate either, "Calculating…" stays.
- **Keyboard backlight** (`Services/KeyboardBacklight.swift`)
  - Uses the private `KeyboardBrightnessClient` from `/System/Library/PrivateFrameworks/CoreBrightness.framework`, loaded lazily with `dlopen` (the same approach as `BrightnessControl` for the display).
  - Selectors: `copyKeyboardBacklightIDs` (first ID is the built-in keyboard), `brightnessForKeyboard:` and `setBrightness:forKeyboard:`, called through `class_getMethodImplementation` because they return `float` / `BOOL`.
  - `isAvailable` is false when the class, a selector or a keyboard ID is missing; the panel then shows "No keyboard backlight".
  - Verified on macOS 26.7.1: the class loads, the keyboard ID is found and the level can be read (it printed 1.0). Setting the level was not verified, and macOS may override a manual value through ambient-light auto brightness.
- **`LevelSlider`**: a custom slider. A capsule track (8 pt), a white fill and a 16 pt white knob with a shadow. The whole track is the hit area (a `DragGesture` with `minimumDistance: 0`), and the value is written to the backlight on every change.

## Timer

- **Entry**: three columns (hr, min, sec), each with up and down chevrons and a text field. Typing keeps the last two digits (so `0` then `7` gives `07`) and clamps to the unit. The chevrons wrap (59 to 0).
- **Limit**: hours 0…24, minutes and seconds 0…59. At 24 hours minutes and seconds are forced to zero, so the longest timer is 24:00:00. `ActivityCenter.maxTimerSeconds` caps the duration as well.
- **Start**: a Start button, disabled while the total is zero. `startTimer(minutes:)` became `startTimer(seconds:)`.
- **Quick buttons**: 1m, 5m, 10m, 15m, 30m, 1h under the picker. They start the timer immediately and also fill the picker.
- **Persistence**: `@AppStorage` keys `timerHours`, `timerMinutes`, `timerSeconds` (default 0 / 5 / 0).
- **Layout**: a `GeometryReader` gives the ring 30% of the width and the controls 70%, with 28 pt of leading padding on the controls. The proportions are fixed, so the ring does not move when switching between setup and running.
- **Sound**: unchanged. `ActivityCenter.timerFinished()` shows "Done" for 5 s and plays the system sound Glass once. A sound and repeat picker was built and then removed on request.

## Calendar

- `CalendarService.refresh()` keeps every event in the next 24 hours (`prefix(3)` was removed). The live activity still uses only the first timed event.
- `CalendarPanel` puts the list in a vertical `ScrollView` (no indicator) inside the card.
- **Gestures**: vertical scroll events were consumed as swipe-down (cycle tab) and swipe-up (collapse), which would have closed the island while scrolling. In `IslandGestureMonitor.handleScroll`, the vertical branch now returns `false` when the island is expanded on the Calendar tab, so scrolling reaches the list. On that tab swipe-up no longer collapses and swipe-down no longer cycles tabs; middle-click, the icons and moving the pointer away still work.

## Build and icon

- `Resources/Info.plist` has `CFBundleIconFile = AppIcon`.
- `scripts/bundle.sh` builds `AppIcon.icns` with `sips` and `iconutil` (16 to 512 px plus @2x) from `Resources/AppIcon.png` when that file exists, and skips the step otherwise.
- `Resources/AppIcon.png` is not committed. The image tried locally is another app's icon, so it must not be published; use your own artwork (square, ideally 1024 × 1024). The 480 px source was upscaled for the largest sizes.
- The menu bar item still uses the `capsule.fill` SF Symbol.

## Energy

- Battery: one 15 s timer, alive only while the Battery panel is on screen.
- Everything else from the earlier specs is unchanged.

## Testing

- `swift build` succeeds and `./scripts/test.sh` passes (14 tests in 4 suites). No new unit tests: the changes are view and service glue.
- Not yet inspected on a running app: tooltips, the battery panel, the 3:7 timer layout, the calendar scroll, and setting the keyboard backlight.
