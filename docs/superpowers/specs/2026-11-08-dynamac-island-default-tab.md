# Dynamac Island — 2026-11-08 changes

## Default tab

- **Setting**: `AppSettings.defaultTab` (`ExpandedTab`, key `defaultTab`, default `home`).
- **Behavior**: `IslandViewModel.expand()` and `collapse()` set the tab to `startTab`, which is the default tab when it is in `availableTabs` and Home otherwise (disabled, or Battery on a Mac without one).
- **Settings → Island → Widgets**: one row per `ExpandedTab` with an Enabled toggle and a Default radio. Only one default can be selected. Choosing a disabled widget enables it (`makeDefault`). Disabling the default widget resets the default to Home.
- **Rows**: Home (its toggle is the Now Playing switch, `showMusic`), Shelf (always on, toggle disabled), Calendar, Timer, Virtual pet, Battery.
- **New tabs**: the list iterates `ExpandedTab.allCases`, and `isEnabled` / `setEnabled` / `title` are exhaustive switches, so a new tab does not compile until it is handled and then appears in Settings.

## Calendar live activity fix

- `CalendarService.refresh()` picked the first non-all-day event of today that had not ended. A meeting already running for more than 5 minutes was therefore chosen, no live activity was shown for it, the next meeting was never considered, and the refresh timer was re-armed every second (its lead time was already in the past).
- It now picks the first non-all-day event whose start + 5 minutes is still in the future, so the next meeting is announced and the timer targets a future time.

## Meeting list popup

- `ActivityCenter.upcomingEvent` became `upcomingEvents` (every event inside its window), plus `dismissedEventIDs`, `visibleEvents`, `dismissEvent` and `dismissAllEvents`. Dismissed IDs are dropped once the event leaves the window.
- `CalendarService.scheduleLiveActivities` lists every non-all-day event of today that is within `calendarLeadMinutes` before its start or 5 minutes after it, and arms a single one-shot timer at the next window edge. The time-to-leave alert (sound plus the 5 s transient) fires once, for the earliest of the events that just appeared.
- `CollapsedActivity.events` draws one row per event (at most 5: colored dot, title, countdown, × button) under the notch row; the island grows in height and uses a wider side (130 pt). The countdown uses `TimelineView(.everyMinute)`, so it adds no timer of its own.
- While meeting rows are visible, hover does not open the island (same rule as the timer controls); a click still does. Swipe up on the collapsed island dismisses all visible rows.
- Events starting at the same time are all shown. Rows beyond the fifth are not shown until one leaves.

## Shelf: screenshot thumbnail drops

- The drop target now accepts `.fileURL` and `.image` (`ShelfDrop` in `ShelfView.swift`). The floating thumbnail after Cmd+Shift+4 offers a temporary file that macOS deletes shortly after, or only image data.
- A file URL inside a temporary folder (`TemporaryItems`, `/var/folders`) is copied to `Application Support/Dynamac Island/Dropped/<uuid>/` before it is added, so the shelf reference survives. Image-only drops are copied from the provider's file representation the same way.
- Other dropped files are still referenced in place, not copied.
- Not verified: dragging a real screenshot thumbnail; the exact types the thumbnail offers were assumed, not inspected.

## Verification

- `swift build` succeeds.
- Not verified: the Settings layout, the hover-to-open behavior, the calendar fix and the meeting list popup were not run by hand with real meetings. `./scripts/test.sh` was not run (no `IslandCore` or test changes).
