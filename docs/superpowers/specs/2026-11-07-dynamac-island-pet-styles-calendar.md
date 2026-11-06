# Dynamac Island — 2026-11-07 changes

Delta on top of [2026-10-31-dynamac-island-design.md](2026-10-31-dynamac-island-design.md): a virtual pet, two new border styles, expanded-size settings, calendar sync, a repeat-one fix and optional tabs.

## Summary

| Area          | Change                                                                           |
| ------------- | -------------------------------------------------------------------------------- |
| Virtual pet   | New Pet tab and a default collapsed display                                      |
| Styles        | New **None** and **Golden Dragon** styles; picker becomes a row of live previews |
| Expanded size | Width and height settings; default 640 × 236 pt                                  |
| Widgets       | New Timer and Virtual pet toggles; every optional tab can be switched off        |
| Calendar      | Periodic and on-demand remote sync; all work stops when the widget is off        |
| Now Playing   | Repeat-one now works for browsers and other MediaRemote sources                  |

## Virtual pet

- **Model** (`IslandCore/Pet.swift`): `Pet` is a pure value type and `PetStore` is an `ObservableObject` that persists it to `~/Library/Application Support/Dynamac Island/pet.json`. Stats are 0…1: food (`fullness`), `happiness`, `energy`.
- **Lazy decay**: nothing ticks while idle. `advance(to:)` applies the time since `updatedAt`, and views read `PetStore.current(at:)`, which advances a copy without writing.
  - Awake: food −1/8 per hour, happiness −1/12 per hour (−1/6 when food < 20%), energy −1/16 per hour.
  - Asleep: energy +1 per 30 minutes (`fullSleepHours = 0.5`), food −1/16 per hour, happiness −1/24 per hour. The pet wakes on its own at 100% energy.
  - Energy ≤ 5% while awake puts the pet to sleep. An absence counts for at most 12 hours, so a long break never leaves it hopeless.
- **Actions**
  - Feed: +35% food, +5% happiness, +1 xp. Refused when asleep or food > 90%.
  - Play: +25% happiness, −12% energy, −5% food, +2 xp. Refused when asleep or energy < 15%.
  - Sleep / Wake toggles sleeping. While asleep the panel shows "wakes in …" (`sleepRemaining`).
- **Level** = xp / 10 + 1. It is only a number: there is no cap and no effect.
- **Mood** (sleeping, hungry, tired, sad, happy, content) is derived from the stats and shown as an emoji badge.
- **Species**: cat, dog, rabbit, chick, panda, fox (emoji glyphs). The species menu and the name field are in the panel (name: 16 characters, saved on Enter).
- **Pet tab** (`PetViews.swift`): opened from a paw icon in the right group of the header (a text tab would not fit next to the notch). It has the glyph with a bounce and a floating reaction emoji, a speech line, three stat bars and Feed / Play / Sleep buttons.
- **Default collapsed display**: `CollapsedActivity.pet` has the lowest priority. Order: HUD, transient activity, timer, upcoming event, music, then pet. It needs no dismissal, so swipe-up does nothing for it. The glyph bobs through a `TimelineView` that ticks every 1.2 s, and the mood badge updates once a minute.
- **Setting**: Settings → Island → Widgets → Virtual pet (default on). Off hides both the tab and the collapsed display.

## Styles

- Settings → General → **Style** replaces the segmented text picker with a horizontally scrolling row of live preview cards (240 × 110 pt, no labels). Clicking a card selects it, and the selected card has a 3 pt accent border. Titles are kept as accessibility labels.
- **None**: first in the list. `IslandViewModel.effectIntensity` returns 0, so no effect is ever mounted.
- **Golden Dragon** (`Effects/DragonEffect.swift`, drawn in a SwiftUI `Canvas`):
  - The outline is sampled into 240 points by `OutlineSampler`, cached by size and radii, so the per-frame work never walks the path.
  - The dragon runs along the outline at 0.14 of the perimeter per second. It enters at one top corner, leaves at the other and repeats. The body is 42% of the perimeter long.
  - Its back faces away from the island and its legs face it. Local frames come from the sampled tangent and an outward normal.
  - Parts: a scaled, wavy body of 90 overlapping discs (belly highlight, back shade, scale crescents), curved dorsal fins, two five-clawed legs with pearl tips, a side-view head (antlers, flowing mane, whiskers, teeth, red eye, glowing pearl) and a tail tuft.
  - The canvas is padded by 44 pt on every side so parts outside the outline are not clipped. The glow layer is a blurred gold stroke plus a head glow.
  - It always stays gold and ignores the album palette.
- The preview for each style reuses `BlackHoleEffect`.

## Expanded size

- `IslandMetrics.expandedSize` is 640 × 236 pt. Settings → Island → **Expanded size** adds a width offset (−100…+200 pt, step 4) and a height offset (−30…+90 pt, step 2), with the resulting size shown and a Reset button.
- The result is capped by `IslandMetrics.maxExpandedSize`: the window (900 × 340 pt) minus the hit-slop padding, i.e. 872 × 332 pt.

## Widgets and tabs

- Settings → Island → Widgets: Now Playing, Calendar, Timer, Virtual pet, Battery. A new `showTimer` and `showPet` join the existing ones.
- `IslandViewModel.availableTabs` filters the optional tabs, so swipe-down and middle-click only cycle through enabled ones. Home and Shelf are always present.

## Calendar

- **Sources**: EventKit reads whatever Calendar.app has. Google Calendar works by adding the Google account in System Settings → Internet Accounts (Calendars switched on). There is no direct Google API integration, which would need OAuth and, for a Workspace account, admin approval.
- **Why events arrive late**: remote accounts sync on macOS's own schedule, so a new Google event can take a few minutes to show up in Calendar.app. The island can only ask: `EKEventStore.refreshSourcesIfNecessary()` is a hint, not a forced sync.
- **Sync requests** (`CalendarService`)
  - A repeating 5-minute timer (60 s tolerance) calls `refreshSourcesIfNecessary()` while the widget is on and access is granted.
  - `syncNow()` calls it and re-queries local events. It runs when the Calendar widget is switched back on and when the Calendar tab is opened.
  - Late results arrive through `EKEventStoreChanged`, which triggers a refresh.
- **Widget off**: `refresh()` returns early, the sync timer and the one-shot timers are cancelled, and the upcoming list and live activity are cleared. Only the very cheap change observer stays registered.
- **Not done**: forcing Calendar.app to reload through AppleScript (`reload calendars`). It would need Automation permission and a running Calendar.app.

## Now Playing: repeat-one

- Music and Spotify keep their native repeat.
- Browsers and most other MediaRemote sources ignore the repeat command, and every update reports "off", which used to reset the button.
- For sources without a script backend the repeat mode is now local. With repeat-one on and the track playing, a one-shot timer seeks to 0 about 0.6 s before the end, so the player never reaches its own end-of-track behaviour. The timer is rescheduled after each update or seek.

## Energy

- New periodic work: the 5-minute calendar sync timer (only while the Calendar widget is on and access is granted) and the 1.2 s pet animation tick (only while the pet is the visible collapsed activity or the Pet tab is open).
- Everything else is unchanged: media, battery, power and Focus stay event-driven.
- The measured ~0% CPU / ~27 MB figures predate the pet and the dragon and have not been re-measured.

## Testing

- `PetTests` in `Tests/IslandCoreTests` covers decay, the absence cap, refusals (full or asleep), play costs, sleeping and waking, and persistence.
- `scripts/test.sh` runs 14 tests across 4 suites; all pass.
- The dragon, the pet panel and the style picker were verified to build but not yet inspected visually or on a running app.
