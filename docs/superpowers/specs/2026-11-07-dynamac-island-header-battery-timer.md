# Dynamac Island — 2026-11-07 (part 2): header, battery, timer, calendar

Delta on top of [2026-11-07-dynamac-island-pet-styles-calendar.md](2026-11-07-dynamac-island-pet-styles-calendar.md) (which builds on [2026-10-31-dynamac-island-design.md](2026-10-31-dynamac-island-design.md)). Branch: `feature/header-tooltips-battery-timer-calendar`.

## Summary

| Area         | Change                                                                                                                                       |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Header       | Home and Shelf are icon-only; every header icon has an instant hover tooltip                                                                 |
| Battery tab  | Two halves: 3-line battery info and a keyboard backlight slider                                                                              |
| Battery data | Time estimate refreshed on open and while open; system-estimate fallback                                                                     |
| Timer        | Custom hours / minutes / seconds (max 24:00:00), scroll to adjust, quick buttons, 3:7 layout                                                 |
| Calendar     | Today's remaining events by default, a dropdown for tomorrow and the day after; scrollable; vertical scroll is no longer a swipe on that tab |
| Build        | `AppIcon.icns` generated from `Resources/AppIcon.png` when it exists                                                                         |
| Reverted     | Timer sound picker (the original single Glass sound is kept)                                                                                 |

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
  - Verified on macOS 26.7.1: the class loads, the keyboard ID is found, the level can be read, and setting 100% was read back unchanged after 0.3, 1, 3 and 6 s (in a bright room, so the light sensor had no reason to intervene). The original level was restored afterwards.
  - **Auto brightness**: the setting "Adjust keyboard brightness in low light" was on on the test machine (`isAutoBrightnessEnabledForKeyboard:` returned true), and while it is on the ambient light sensor overrides a manual level, which made the slider appear to "fall back". The idle-dim time was 0 (no idle dimming), so that was ruled out. The drop itself was not reproduced; auto brightness is the likely cause.
  - `isAutoEnabled` and `setAuto(_:)` wrap `isAutoBrightnessEnabledForKeyboard:` and `enableAutoBrightness:forKeyboard:` (a `BOOL` argument passed as `UInt8`). The class also exposes `setBrightness:fadeSpeed:commit:forKeyboard:`, `idleDimTimeForKeyboard:`, `suspendIdleDimming:forKeyboard:` and others, which are not used.
- **`LevelSlider`**: a custom slider. A capsule track (8 pt), a white fill and a 16 pt white knob with a shadow. The whole track is the hit area (a `DragGesture` with `minimumDistance: 0`). It reports changes through `onUserChange`, which is called only for drags, not when the value is set from outside (reading the level when the tab opens must not write anything).
- **Behavior of the control** (`BatteryPanel`)
  - Dragging the slider turns auto brightness off first, then writes the level.
  - An "Auto brightness on / off" pill under the slider toggles auto brightness and re-reads the level.
  - On appear, the panel only reads the level and the auto state.
  - Auto brightness is a system setting (System Settings → Keyboard), so turning it off persists until it is turned on again, from the pill or from System Settings.

## Timer

- **Entry**: three columns (hr, min, sec), each with up and down chevrons and a text field. Typing keeps the last two digits (so `0` then `7` gives `07`) and clamps to the unit. The chevrons wrap (59 to 0).
- **Scroll to adjust**: hovering a column and scrolling changes that unit, so large changes need no clicking. The chevrons and typing still work.
  - Hover is tracked per column (`hoveredUnit`). While the panel is on screen, `TimerPanel` installs a local `NSEvent` monitor for `scrollWheel` (added in `onAppear`, removed in `onDisappear`). When the pointer is over a column and no timer is running, the event is consumed and changes the unit; otherwise it passes through. Only plain values (`ScrollInput`) cross into the main-actor closure, because `NSEvent` is not `Sendable`.
  - Direction: scrolling up increases and scrolling down decreases, for both trackpad and mouse wheel, regardless of the natural-scrolling setting (`finger = inverted ? deltaY : -deltaY`; negative means up).
  - Trackpad: 10 points of accumulated delta make one step. Mouse wheel: one step per notch. Momentum events are consumed without effect so the value does not run away after the fingers lift.
  - Scrolling clamps (hours 0…24, minutes and seconds 0…59) and does not wrap, unlike the chevrons; at 24 hours minutes and seconds are still forced to zero.
- **Limit**: hours 0…24, minutes and seconds 0…59. At 24 hours minutes and seconds are forced to zero, so the longest timer is 24:00:00. `ActivityCenter.maxTimerSeconds` caps the duration as well.
- **Start**: a Start button, disabled while the total is zero. `startTimer(minutes:)` became `startTimer(seconds:)`.
- **Quick buttons**: 1m, 5m, 10m, 15m, 30m, 1h under the picker. They start the timer immediately and also fill the picker.
- **Persistence**: `@AppStorage` keys `timerHours`, `timerMinutes`, `timerSeconds` (default 0 / 5 / 0).
- **Layout**: a `GeometryReader` gives the ring 30% of the width and the controls 70%, with 28 pt of leading padding on the controls. The proportions are fixed, so the ring does not move when switching between setup and running.
- **Sound**: unchanged. `ActivityCenter.timerFinished()` shows "Done" for 5 s and plays the system sound Glass once. A sound and repeat picker was built and then removed on request.

## Calendar

- `CalendarService.refresh()` keeps every event of the current day that has not ended yet (`prefix(3)` was removed). The query runs from now to the start of tomorrow (`startOfTomorrow(after:)`), so tomorrow's events are not shown; an event that started earlier and is still running is. It was first the next 24 hours and was changed to "today" on request. The panel header reads "Today" and the empty state "No more events today.". The refresh timer is capped at midnight, so the list switches to the new day without waiting for the 3-hour refresh. The live activity uses the same list, so an event just after midnight does not trigger it before midnight, and it still uses only the first timed event.
- **Day dropdown**: a `Menu` next to the date offers Today, Tomorrow and Day after tomorrow, stored in `CalendarService.selectedDay` (0, 1 or 2). The options are an inline `Picker`, so the selected day shows a checkmark (they were plain buttons at first, which gave no sign of the current choice). Today shows events that have not ended; tomorrow and the day after show every event of that calendar day (from its 00:00 to the next 00:00, all-day ones last), with the same filters (declined, subscribed). The shown date, the header label and the empty state ("No events tomorrow.") follow the selection. `refresh()` computes today's list every time (for the live activity and `nextEvent`, which is now a stored property that drives the icon's dot) and the selected day's list for display. Opening the Calendar panel resets the selection to Today. Not verified: the menu on this non-activating panel.
- `CalendarPanel` puts the list in a vertical `ScrollView` (no indicator) inside the card.
- **Gestures**: vertical scroll events were consumed as swipe-down (cycle tab) and swipe-up (collapse), which would have closed the island while scrolling. In `IslandGestureMonitor.handleScroll`, the vertical branch now returns `false` when the island is expanded on the Calendar or Timer tab, so scrolling reaches the event list or the timer fields. On those tabs swipe-up no longer collapses and swipe-down no longer cycles tabs; middle-click, the icons and moving the pointer away still work.

## Build and icon

- `Resources/Info.plist` has `CFBundleIconFile = AppIcon`.
- `scripts/bundle.sh` builds `AppIcon.icns` with `sips` and `iconutil` (16 to 512 px plus @2x) from `Resources/AppIcon.png` when that file exists, and skips the step otherwise.
- `Resources/AppIcon.png` is the owner's own artwork: a 1024 × 1024 PNG with transparent rounded corners (downscaled from a 2048 × 2048 original). It replaced a 480 px placeholder taken from another app's store listing; that earlier file is still in the git history of this branch.
- The menu bar item still uses the `capsule.fill` SF Symbol.

## Collapsed width and the timer countdown

- The default `notchWidthOffset` is now −20 pt (was 0). A saved value is kept, and Reset in Settings → Island → Fine tuning goes back to −20.
- With −20 pt the music activity fits, but a running timer clipped its digits (for example `1:00:00`). Two earlier attempts were dropped: a "Width during timer" slider, and a fixed 0 pt offset during the countdown.
- **Countdown layout** (`CollapsedActivityView`, `IslandRootView.islandSize`): while the collapsed island shows `CollapsedActivity.timer` it is larger than for other activities.
  - Wider: the side width for `.timer` is 62 pt per side (46 pt for most activities), so the digits fit even with the −20 pt offset.
  - Taller: `timerControlsHeight` (34 pt) is added below the notch-height row. The top row keeps the timer icon on the left and the countdown on the right, aligned with the notch.
  - The second row holds two buttons. **Pause** pauses the timer and turns into **Resume**; the island stays as it is, with the paused time dimmed. **Cancel** stops the timer, so the activity ends and the island collapses back to its normal size.
  - The extra size appears and disappears with the existing activity animation; the window frame is fixed, so nothing is repositioned.
  - **"Done" alert**: with the −20 pt width the word "Done" was pushed against the island's edge and clipped, because `TransientActivity.timerDone` used the narrow 46 pt side width. It now counts as a wide alert (`isWide`, 100 pt per side) like the Bluetooth and Focus alerts.
  - **Hover**: hovering the island used to peek or expand it (with "expand on hover" on, it opened fully), which moved the buttons away before they could be clicked. `IslandViewModel.hoverChanged` now ignores hover while `showsTimerControls` is true (the timer is active and no HUD or alert is showing). To open the island during a countdown, click its background, swipe down or middle-click. The pointer leaving still collapses as before.
- Not yet checked on a running app, in particular that the buttons receive clicks (the island itself has a tap-to-expand gesture) and that the second row clears the notch on a hardware-notch display.

## Energy

- Battery: one 15 s timer, alive only while the Battery panel is on screen.
- Hover exit: the island now collapses 0.05 s after the pointer leaves (it was 0.4 s expanded and 0.15 s peeking). The safety check that catches a missed mouse-exit now runs every 0.25 s (was 0.5 s) and waits 0.05 s (was 0.3 s) before collapsing; it still exists only while the island is open. The 0.34 s collapse animation and the invisible hit-slop around the island (14 pt on the sides, 8 pt below) are unchanged, so the pointer still counts as inside until it leaves that margin.
- Everything else from the earlier specs is unchanged.

## Testing

- `swift build` succeeds and `./scripts/test.sh` passes (14 tests in 4 suites). No new unit tests: the changes are view and service glue.
- Not yet inspected on a running app: tooltips, the battery panel, the 3:7 timer layout, scrolling the timer fields (including the scroll direction), the calendar scroll, and the keyboard backlight slider under low light (the fix for the slider falling back is untested).
