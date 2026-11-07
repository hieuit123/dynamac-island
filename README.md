# Dynamac Island

A native macOS Dynamic Island inspired by [Alcove](https://tryalcove.com), with animated border styles (including a golden dragon), a file shelf and a virtual pet.

## Features

- **Island at the notch**, a simulated notch, or a floating pill on displays without one. Show it on one display or on all of them. The collapsed width and height, and the expanded width and height (Settings → Island), can be fine-tuned.
- **Border styles**, chosen from a scrolling row of live previews in Settings → General → Style: None, Accretion Disk, Event Horizon, Vortex and Golden Dragon (a gilded dragon that runs along the island's outline). They show on hover and in the expanded popup, and get stronger while files are dragged over. The dragon is always gold; the others can take the album colors.
- **Shelf**: drop files into the black hole and drag them out to any app or screen. Dragging out copies the file, and double-click opens it. The shelf stores references to the original files and keeps them across restarts.
- **Now Playing for every media source** (browsers, YouTube, Podcasts, Music, Spotify…) through the bundled [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter). If it's unavailable, Music and Spotify still work through AppleScript.
  - The player takes its colors from the album art: blurred artwork background, tinted controls, and a gradient progress bar you can drag to seek.
  - Shuffle and repeat (including repeat-one), favorite (Apple Music), playback speed (podcasts and video), copy song link, and Lossless / Hi-Res badges. Repeat-one also works for browsers: since they ignore the command, the island loops the track itself.
  - Long titles scroll, the playing app's icon is shown on the artwork, the artwork gets a glare sweep, and it dims when paused.
  - The collapsed island shows an animated waveform in the album's colors. Core Animation runs it outside the app, so it costs about 0% CPU.
- **Calendar** (corner icon): every event in the next 24 hours in a scrollable list, with declined and subscribed calendars filtered out. It reads the calendars in the macOS Calendar app, so Google Calendar works once you add your Google account (see [Calendar setup](#calendar-setup)). Click an event or the date to open Calendar, Fantastical or Notion Calendar. An upcoming event appears as a live activity, with a time-to-leave alert.
- **Timer** (corner icon): set any time from 00:00:01 to 24:00:00 with hours / minutes / seconds fields, or start 1m, 5m, 10m, 15m, 30m or 1h with one click. It shows a progress ring, remembers your last duration, and counts down in the collapsed island. When it ends, the island shows "Done" and plays the Glass sound.
- **Virtual pet** (paw icon): feed it, play with it and put it to sleep (cat, dog, rabbit, chick, panda or fox; rename it in the panel). Food, happiness and energy fall over time, even while the app is closed. A sleeping pet recovers in about 30 minutes and wakes at full energy. When nothing else is showing (no music, timer, event or alert), the collapsed island shows your pet; anything more important replaces it.
- **Header icons**: Home and Shelf (a dot shows when the shelf has files) are icons, like Pet, Calendar and Timer, and each shows its name as soon as you hover it. Home and Shelf are always there; Calendar, Timer, Pet and Battery can each be switched off in Settings → Island → Widgets.
- **Battery** (corner badge): the Battery tab shows the level, the state (charging, on battery…) and the time to empty or full on three lines, plus a slider for the **keyboard backlight** (dragging it turns off macOS's "Adjust keyboard brightness in low light", otherwise the light sensor would undo your level; an "Auto brightness" button turns it back on). It uses a private macOS API, so it may stop working in a future macOS; without a backlit keyboard it shows "No keyboard backlight". Also charging sound, low-battery alerts at 20 / 10 / 5%, and Low Power Mode alerts.
- **Connectivity**: AirPods and Bluetooth devices show a connect/disconnect activity with battery level.
- **Focus**: shows Focus mode changes with each mode's symbol and color (needs Full Disk Access).
- **Volume / brightness HUD**: optional percentage, visible mute, a bounce at 0 / 100%, glow, and Smooth / Fast / Instant speed (needs Accessibility).
- **Gestures**: swipe left/right to skip; swipe down to expand or cycle panels; swipe up to collapse or dismiss a live activity; middle-click to cycle; optional hover delay. On the Calendar tab, vertical scrolling moves the event list instead.
- **Privacy & visibility**: hide in fullscreen apps, while gaming, or in Mission Control, and hide from screenshots and recordings.
- **Onboarding**: a permissions checklist on first launch, also available from the menu bar.

## Energy

- No polling for music, battery and power state: they use system notifications. Focus changes use a kernel file watcher, and Bluetooth, fullscreen and battery changes come from system notifications.
- Calendar asks your accounts to sync every 5 minutes, and only while the Calendar widget is on. Turn the widget off and all calendar work stops.
- Effects and animations only exist while the island is hovered or expanded, and run at 30 fps in Low Power Mode.
- The pet's idle animation ticks every 1.2 seconds while it is the visible collapsed activity or the Pet tab is open.
- The timer uses one one-shot `Timer` at its end date. The clock only updates while expanded.
- The Battery tab re-reads the battery every 15 seconds, but only while the tab is open.
- The window is removed from the compositor while the display sleeps or the session is inactive.
- Calendar alerts use one-shot timers at the exact times needed.
- The MediaRemote adapter only sends updates when playback changes, and exits with the app (even after a crash).
- Measured: ~0% CPU for both the app and the adapter, idle or while music plays; ~27 MB RAM (measured before the pet and dragon were added).

## Calendar setup

The island shows events from the macOS Calendar app, so any calendar you can see there works.

**1. Grant calendar access**

- On first launch the permissions checklist asks for Calendar. It is also under the menu bar icon → Set Up Permissions…, or open the Calendar panel and click **Allow Calendar**.
- If you denied it earlier: System Settings → Privacy & Security → Calendars → enable Dynamac Island (full access is required).
- After each rebuild the app is signed again, so macOS may ask again. Remove the old Dynamac Island entry and grant it once more.

**2. Connect your Google account**

1. Open System Settings → Internet Accounts → Add Account… → Google and sign in.
2. Make sure the **Calendars** switch is on for that account.
3. Open the Calendar app and check that your Google calendars are ticked in the sidebar. Calendars that are unticked there do not show in the island.

**3. Syncing**

- New or changed Google events can take a few minutes to reach macOS. That delay is macOS's, not the island's. Cmd+R in the Calendar app forces a refresh.
- The island asks macOS to sync every 5 minutes, when you re-enable the Calendar widget, and when you open the Calendar panel. Events appear as soon as macOS has them.
- Events are limited to the next 24 hours. Settings → Activities → Calendar controls declined events, subscribed/birthday calendars, the live activity lead time, and which app opens an event.

## Build & run

Requires macOS 14+ and Swift 5.10+ (Command Line Tools are enough).

```sh
./scripts/bundle.sh          # builds build/Dynamac Island.app (incl. the MediaRemote adapter)
open "build/Dynamac Island.app"
./scripts/test.sh            # unit tests
```

Copy the app to `/Applications` for launch-at-login. The app is ad-hoc signed, so after each rebuild macOS may ask again for Accessibility and Automation permissions (remove the old entry in System Settings → Privacy & Security → Accessibility).

**App icon**: if `Resources/AppIcon.png` exists (a square PNG, ideally 1024 × 1024), `bundle.sh` turns it into `AppIcon.icns` for the app. Without the file the app gets the default icon. Use artwork you have the rights to; the file is not part of the repository. The app has no Dock icon, so the icon shows in Finder, permission dialogs and Login Items.

## Third-party

- [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause) is vendored in `Vendor/` and built by `scripts/build-mediaremote.sh`. Its license ships inside the app bundle.
