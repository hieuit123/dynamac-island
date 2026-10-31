import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var hud: HUDPermissionState

    var body: some View {
        Form {
            Section("Black hole effect") {
                Picker("Style", selection: $settings.effectStyle) {
                    ForEach(EffectStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                EffectPreview(style: settings.effectStyle)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
            }

            Section("Island") {
                Picker("Display", selection: $settings.displayID) {
                    Text("Automatic (main display)").tag(UInt32(0))
                    ForEach(NSScreen.screens, id: \.displayID) { screen in
                        Text(screen.localizedName).tag(UInt32(screen.displayID))
                    }
                }
                Toggle("Expand on hover (instead of click)", isOn: $settings.expandOnHover)
                Toggle("Haptic feedback on hover", isOn: $settings.hapticsEnabled)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section("Widgets") {
                Toggle("Now Playing", isOn: $settings.showMusic)
                Toggle("Calendar", isOn: $settings.showCalendar)
                Toggle("Battery", isOn: $settings.showBattery)
            }

            Section {
                Toggle("Replace volume & brightness HUD", isOn: $settings.hudEnabled)
                if settings.hudEnabled && !hud.isActive {
                    HStack {
                        Text("Needs Accessibility permission.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Grant…") { hud.requestPermission() }
                    }
                }
            } header: {
                Text("HUD")
            } footer: {
                Text("⌥⇧ + key for fine steps. If the output device has no software volume, the system HUD is used.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
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
