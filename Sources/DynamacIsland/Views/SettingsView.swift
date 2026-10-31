import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var hud: HUDPermissionState
    let focusAvailable: Bool
    let usingMediaRemote: Bool

    var body: some View {
        TabView {
            form(general).tabItem { Label("General", systemImage: "gearshape") }
            form(island).tabItem { Label("Island", systemImage: "capsule") }
            form(music).tabItem { Label("Music", systemImage: "music.note") }
            form(activities).tabItem { Label("Activities", systemImage: "bolt.horizontal") }
            form(hudSection).tabItem { Label("HUD", systemImage: "speaker.wave.2") }
        }
        .frame(width: 520, height: 560)
    }

    private func form<C: View>(_ content: C) -> some View {
        Form { content }.formStyle(.grouped)
    }

    // MARK: General

    @ViewBuilder private var general: some View {
        Section("Black hole effect") {
            Picker("Style", selection: $settings.effectStyle) {
                ForEach(EffectStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            EffectPreview(style: settings.effectStyle).frame(maxWidth: .infinity).frame(height: 110)
        }
        Section("Behavior") {
            Toggle("Expand on hover (instead of click)", isOn: $settings.expandOnHover)
            Picker("Hover delay", selection: $settings.hoverDelay) {
                Text("None").tag(0.0); Text("Short (0.15s)").tag(0.15); Text("Medium (0.3s)").tag(0.3); Text("Long (0.6s)").tag(0.6)
            }
            Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
        }
        Section("Gestures") {
            Toggle("Swipe left/right to skip tracks", isOn: $settings.swipeToSkip)
            Toggle("Swipe down to expand / cycle, up to collapse / dismiss", isOn: $settings.verticalSwipeGestures)
            Toggle("Middle-click to cycle panels", isOn: $settings.middleClickCycle)
        }
        Section("Privacy & visibility") {
            Toggle("Hide when an app is fullscreen", isOn: $settings.hideInFullscreen)
            Toggle("Hide while gaming", isOn: $settings.hideWhileGaming)
            Toggle("Hide in Mission Control", isOn: $settings.hideInMissionControl)
            Toggle("Hide from screenshots & screen recordings", isOn: $settings.hideFromCapture)
        }
    }

    // MARK: Island

    @ViewBuilder private var island: some View {
        Section("Display") {
            Toggle("Show on all displays", isOn: $settings.showOnAllDisplays)
            Picker("Display", selection: $settings.displayID) {
                Text("Automatic (main display)").tag(UInt32(0))
                ForEach(NSScreen.screens, id: \.displayID) { screen in
                    Text(screen.localizedName).tag(UInt32(screen.displayID))
                }
            }
            .disabled(settings.showOnAllDisplays)
            Toggle("Simulated notch on displays without one", isOn: $settings.simulatedNotch)
            Text("Off shows a floating pill instead.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Fine tuning") {
            LabeledContent("Width") {
                Slider(value: $settings.notchWidthOffset, in: -40...80, step: 1)
                Text("\(Int(settings.notchWidthOffset)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
            }
            LabeledContent("Height") {
                Slider(value: $settings.notchHeightOffset, in: -8...12, step: 1)
                Text("\(Int(settings.notchHeightOffset)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
            }
            Button("Reset") { settings.notchWidthOffset = 0; settings.notchHeightOffset = 0 }
        }
        Section("Widgets") {
            Toggle("Now Playing", isOn: $settings.showMusic)
            Toggle("Calendar", isOn: $settings.showCalendar)
            Toggle("Battery", isOn: $settings.showBattery)
        }
    }

    // MARK: Music

    @ViewBuilder private var music: some View {
        Section {
            Toggle("All media sources (MediaRemote)", isOn: $settings.useMediaRemote)
            Text(usingMediaRemote ? "Active: browsers, Podcasts, YouTube and any player are supported."
                                  : "Inactive: using Music & Spotify only. Restart the app after changing this.")
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text("Sources") }
        Section("Player") {
            Toggle("Scrolling titles", isOn: $settings.marqueeTitles)
            Toggle("Audio quality badges (Apple Music)", isOn: $settings.showAudioBadges)
            Toggle("Gradient progress bar", isOn: $settings.gradientProgress)
            Toggle("Keep live activity while paused", isOn: $settings.showMusicWhenPaused)
        }
        Section("Effects") {
            Toggle("Animated waveform in collapsed island", isOn: $settings.animatedWaveform)
            Toggle("Tint black-hole effect with album colors", isOn: $settings.albumTintedEffects)
        }
    }

    // MARK: Activities

    @ViewBuilder private var activities: some View {
        Section("Battery") {
            Toggle("Charging sound", isOn: $settings.chargingSound)
            Toggle("Low battery alerts (20%, 10%, 5%)", isOn: $settings.lowBatteryAlerts)
            Toggle("Low battery sound", isOn: $settings.lowBatterySound).disabled(!settings.lowBatteryAlerts)
            Toggle("Low Power Mode alerts", isOn: $settings.lowPowerModeAlert)
        }
        Section("Calendar") {
            Toggle("Upcoming event live activity", isOn: $settings.calendarLiveActivity)
            Picker("Show before start", selection: $settings.calendarLeadMinutes) {
                ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) minutes").tag($0) }
            }
            Toggle("Time-to-leave alert", isOn: $settings.timeToLeaveAlert)
            Toggle("Show declined events", isOn: $settings.showDeclinedEvents)
            Toggle("Exclude subscribed & birthday calendars", isOn: $settings.excludeSubscribedCalendars)
            Picker("Open events in", selection: $settings.calendarApp) {
                ForEach(CalendarApp.allCases) { Text($0.title).tag($0) }
            }
        }
        Section("Connectivity & Focus") {
            Toggle("Bluetooth / AirPods connections", isOn: $settings.bluetoothActivity)
            Toggle("Focus mode changes", isOn: $settings.focusActivity)
            if !focusAvailable {
                HStack {
                    Text("Focus needs Full Disk Access.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings…") { FocusMonitor.openFullDiskAccessSettings() }
                }
            }
        }
    }

    // MARK: HUD

    @ViewBuilder private var hudSection: some View {
        Section {
            Toggle("Replace volume & brightness HUD", isOn: $settings.hudEnabled)
            if settings.hudEnabled && !hud.isActive {
                HStack {
                    Text("Needs Accessibility permission.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Grant…") { hud.requestPermission() }
                }
            }
        } footer: {
            Text("⌥⇧ + key for fine steps. If the output device has no software volume, the system HUD is used.")
                .foregroundStyle(.secondary)
        }
        Section("Style") {
            Toggle("Show percentage", isOn: $settings.hudShowPercentage)
            Toggle("Glow", isOn: $settings.hudGlow)
            Toggle("Overshoot bounce at 0% / 100%", isOn: $settings.hudOvershoot)
            Picker("Speed", selection: $settings.hudSpeed) {
                ForEach(HUDSpeed.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// Lightweight live preview; only animates while the Settings window is visible.
private struct EffectPreview: View {
    let style: EffectStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)],
                                                                   startPoint: .top, endPoint: .bottom))
            NotchShape(topRadius: 10, bottomRadius: 22)
                .fill(Color.black)
                .frame(width: 220, height: 64)
                .background(BlackHoleEffect(style: style, intensity: 1, topRadius: 10, bottomRadius: 22, layer: .glow))
                .overlay(BlackHoleEffect(style: style, intensity: 1, topRadius: 10, bottomRadius: 22, layer: .border))
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
