import AppKit
import Combine
import ServiceManagement

enum EffectStyle: String, CaseIterable, Identifiable {
    case accretion, eventHorizon, vortex
    var id: String { rawValue }
    var title: String {
        switch self {
        case .accretion: return "Accretion Disk"
        case .eventHorizon: return "Event Horizon"
        case .vortex: return "Vortex"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var effectStyle: EffectStyle { didSet { defaults.set(effectStyle.rawValue, forKey: "effectStyle") } }
    /// 0 = automatic (primary display with the menu bar).
    @Published var displayID: UInt32 { didSet { defaults.set(Int(displayID), forKey: "displayID") } }
    @Published var hudEnabled: Bool { didSet { defaults.set(hudEnabled, forKey: "hudEnabled") } }
    @Published var expandOnHover: Bool { didSet { defaults.set(expandOnHover, forKey: "expandOnHover") } }
    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: "hapticsEnabled") } }
    @Published var showMusic: Bool { didSet { defaults.set(showMusic, forKey: "showMusic") } }
    @Published var showCalendar: Bool { didSet { defaults.set(showCalendar, forKey: "showCalendar") } }
    @Published var showBattery: Bool { didSet { defaults.set(showBattery, forKey: "showBattery") } }
    @Published var animatedWaveform: Bool { didSet { defaults.set(animatedWaveform, forKey: "animatedWaveform") } }
    @Published var albumTintedEffects: Bool { didSet { defaults.set(albumTintedEffects, forKey: "albumTintedEffects") } }
    @Published var gradientProgress: Bool { didSet { defaults.set(gradientProgress, forKey: "gradientProgress") } }
    @Published var swipeToSkip: Bool { didSet { defaults.set(swipeToSkip, forKey: "swipeToSkip") } }
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Dynamac Island: launch at login failed: \(error)")
            }
        }
    }

    private init() {
        defaults.register(defaults: [
            "effectStyle": EffectStyle.accretion.rawValue, "displayID": 0, "hudEnabled": true,
            "expandOnHover": false, "hapticsEnabled": true, "showMusic": true, "showCalendar": true, "showBattery": true,
            "animatedWaveform": true, "albumTintedEffects": true, "gradientProgress": true, "swipeToSkip": true,
        ])
        effectStyle = EffectStyle(rawValue: defaults.string(forKey: "effectStyle") ?? "") ?? .accretion
        displayID = UInt32(defaults.integer(forKey: "displayID"))
        hudEnabled = defaults.bool(forKey: "hudEnabled")
        expandOnHover = defaults.bool(forKey: "expandOnHover")
        hapticsEnabled = defaults.bool(forKey: "hapticsEnabled")
        showMusic = defaults.bool(forKey: "showMusic")
        showCalendar = defaults.bool(forKey: "showCalendar")
        showBattery = defaults.bool(forKey: "showBattery")
        animatedWaveform = defaults.bool(forKey: "animatedWaveform")
        albumTintedEffects = defaults.bool(forKey: "albumTintedEffects")
        gradientProgress = defaults.bool(forKey: "gradientProgress")
        swipeToSkip = defaults.bool(forKey: "swipeToSkip")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
