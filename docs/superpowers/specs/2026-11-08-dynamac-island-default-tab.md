# Dynamac Island — 2026-11-08 changes

## Default tab

- **Setting**: `AppSettings.defaultTab` (`ExpandedTab`, key `defaultTab`, default `home`).
- **Behavior**: `IslandViewModel.expand()` and `collapse()` set the tab to `startTab`, which is the default tab when it is in `availableTabs` and Home otherwise (disabled, or Battery on a Mac without one).
- **Settings → Island → Widgets**: one row per `ExpandedTab` with an Enabled toggle and a Default radio. Only one default can be selected. Choosing a disabled widget enables it (`makeDefault`). Disabling the default widget resets the default to Home.
- **Rows**: Home (its toggle is the Now Playing switch, `showMusic`), Shelf (always on, toggle disabled), Calendar, Timer, Virtual pet, Battery.
- **New tabs**: the list iterates `ExpandedTab.allCases`, and `isEnabled` / `setEnabled` / `title` are exhaustive switches, so a new tab does not compile until it is handled and then appears in Settings.

## Verification

- `swift build` succeeds.
- Not verified: the Settings layout and the hover-to-open behavior were not run by hand. `./scripts/test.sh` was not run (no `IslandCore` or test changes).
