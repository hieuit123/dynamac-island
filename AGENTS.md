# Agent notes — Dynamac Island

Native macOS 14+ app (Swift, SwiftUI + AppKit, SwiftPM). Testable logic lives in `Sources/IslandCore`, the app in `Sources/DynamacIsland`.

## After every change request

1. **Verify before saying it is done**
   - `swift build` must succeed.
   - Run `./scripts/test.sh` when `Sources/IslandCore` or `Tests/` changed (plain `swift test` fails without the Testing framework path).
   - Say plainly what was not verified (for example UI that was not run, or private APIs that were only read, not written).
2. **Update the docs in the same turn**
   - **Spec**: write to `docs/superpowers/specs/`. Use the spec for today's date, named `YYYY-MM-DD-dynamac-island-<topic>.md`. If none exists for today, create one; if one exists, extend it. Never rewrite an older spec to describe newer work.
   - **README**: update `README.md` when a user-visible feature, setting, permission, build step or energy behavior changes. Keep the Calendar setup section accurate.
   - Only write what was actually done. Mark anything not verified, and do not copy old measurements (CPU, RAM) as if they were current.
   - If a change is reverted, remove it from the README and the spec instead of leaving a note about a feature that does not exist.
3. **Do not commit or push** unless asked. When asked: create a branch from `main`, commit, push, then give a PR title and description (the `gh` CLI may be signed in to a different account than the repo owner, in which case give the compare link instead).

## Conventions

- Settings live in `AppSettings` (UserDefaults keys with registered defaults). Anything optional gets a toggle in Settings → Island → Widgets.
- Keep the app event-driven: no polling. A timer is acceptable only when it exists solely while a view is on screen or while a feature is enabled, and it must be listed in the README "Energy" section and the spec.
- Services that are switched off must stop all background work (see `CalendarService`).
- Private macOS APIs are loaded lazily with `dlopen` and must degrade silently when missing (`BrightnessControl`, `KeyboardBacklight`).
- The island window is a fixed 900 × 340 pt transparent panel; the expanded size is capped by `IslandMetrics.maxExpandedSize`.
- Vertical scroll events are consumed as swipe gestures by `IslandGestureMonitor`. A tab with its own vertical scrolling (Calendar, Timer) must be excluded there.
- Comments only for what the code cannot show, one short line.

## Things to avoid

- `Resources/AppIcon.png` may be committed (the owner approved it); `bundle.sh` skips the icon when the file is missing. It is another app's icon, so the owner is responsible for the rights if the repository is public. Do not add other third-party artwork without being asked.
- Do not add notification scraping for other apps (the Notification Center database approach was tried and removed).
- The app is ad-hoc signed, so rebuilding resets Accessibility, Calendar and Automation permissions.
