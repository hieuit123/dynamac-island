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

enum HUDSpeed: String, CaseIterable, Identifiable {
    case smooth, fast, instant
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CalendarApp: String, CaseIterable, Identifiable {
    case calendar, fantastical, notion
    var id: String { rawValue }
    var title: String {
        switch self {
        case .calendar: return "Calendar"
        case .fantastical: return "Fantastical"
        case .notion: return "Notion Calendar"
        }
    }
    var bundleID: String {
        switch self {
        case .calendar: return "com.apple.iCal"
        case .fantastical: return "com.flexibits.fantastical2.mac"
        case .notion: return "com.cron.electron"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

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
    @Published var hideInFullscreen: Bool { didSet { defaults.set(hideInFullscreen, forKey: "hideInFullscreen") } }
    @Published var hideWhileGaming: Bool { didSet { defaults.set(hideWhileGaming, forKey: "hideWhileGaming") } }
    @Published var hideInMissionControl: Bool { didSet { defaults.set(hideInMissionControl, forKey: "hideInMissionControl") } }
    @Published var hideFromCapture: Bool { didSet { defaults.set(hideFromCapture, forKey: "hideFromCapture") } }
    @Published var hudShowPercentage: Bool { didSet { defaults.set(hudShowPercentage, forKey: "hudShowPercentage") } }
    @Published var hudOvershoot: Bool { didSet { defaults.set(hudOvershoot, forKey: "hudOvershoot") } }
    @Published var hudGlow: Bool { didSet { defaults.set(hudGlow, forKey: "hudGlow") } }
    @Published var chargingSound: Bool { didSet { defaults.set(chargingSound, forKey: "chargingSound") } }
    @Published var lowBatteryAlerts: Bool { didSet { defaults.set(lowBatteryAlerts, forKey: "lowBatteryAlerts") } }
    @Published var lowBatterySound: Bool { didSet { defaults.set(lowBatterySound, forKey: "lowBatterySound") } }
    @Published var lowPowerModeAlert: Bool { didSet { defaults.set(lowPowerModeAlert, forKey: "lowPowerModeAlert") } }
    @Published var calendarLiveActivity: Bool { didSet { defaults.set(calendarLiveActivity, forKey: "calendarLiveActivity") } }
    @Published var timeToLeaveAlert: Bool { didSet { defaults.set(timeToLeaveAlert, forKey: "timeToLeaveAlert") } }
    @Published var showDeclinedEvents: Bool { didSet { defaults.set(showDeclinedEvents, forKey: "showDeclinedEvents") } }
    @Published var excludeSubscribedCalendars: Bool { didSet { defaults.set(excludeSubscribedCalendars, forKey: "excludeSubscribedCalendars") } }
    @Published var verticalSwipeGestures: Bool { didSet { defaults.set(verticalSwipeGestures, forKey: "verticalSwipeGestures") } }
    @Published var middleClickCycle: Bool { didSet { defaults.set(middleClickCycle, forKey: "middleClickCycle") } }
    @Published var marqueeTitles: Bool { didSet { defaults.set(marqueeTitles, forKey: "marqueeTitles") } }
    @Published var showMusicWhenPaused: Bool { didSet { defaults.set(showMusicWhenPaused, forKey: "showMusicWhenPaused") } }
    @Published var showAudioBadges: Bool { didSet { defaults.set(showAudioBadges, forKey: "showAudioBadges") } }
    @Published var useMediaRemote: Bool { didSet { defaults.set(useMediaRemote, forKey: "useMediaRemote") } }
    @Published var bluetoothActivity: Bool { didSet { defaults.set(bluetoothActivity, forKey: "bluetoothActivity") } }
    @Published var focusActivity: Bool { didSet { defaults.set(focusActivity, forKey: "focusActivity") } }
    @Published var simulatedNotch: Bool { didSet { defaults.set(simulatedNotch, forKey: "simulatedNotch") } }
    @Published var showOnAllDisplays: Bool { didSet { defaults.set(showOnAllDisplays, forKey: "showOnAllDisplays") } }
    @Published var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: "onboardingDone") } }
    @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: "hoverDelay") } }
    @Published var notchWidthOffset: Double { didSet { defaults.set(notchWidthOffset, forKey: "notchWidthOffset") } }
    @Published var notchHeightOffset: Double { didSet { defaults.set(notchHeightOffset, forKey: "notchHeightOffset") } }
    @Published var calendarLeadMinutes: Int { didSet { defaults.set(calendarLeadMinutes, forKey: "calendarLeadMinutes") } }
    @Published var effectStyle: EffectStyle { didSet { defaults.set(effectStyle.rawValue, forKey: "effectStyle") } }
    @Published var hudSpeed: HUDSpeed { didSet { defaults.set(hudSpeed.rawValue, forKey: "hudSpeed") } }
    @Published var calendarApp: CalendarApp { didSet { defaults.set(calendarApp.rawValue, forKey: "calendarApp") } }
    /// 0 = automatic (primary display with the menu bar).
    @Published var displayID: UInt32 { didSet { defaults.set(Int(displayID), forKey: "displayID") } }
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
        defaults.register(defaults: ["hudEnabled": true, "expandOnHover": false, "hapticsEnabled": true, "showMusic": true, "showCalendar": true, "showBattery": true, "animatedWaveform": true, "albumTintedEffects": true, "gradientProgress": true, "swipeToSkip": true, "hideInFullscreen": true, "hideWhileGaming": true, "hideInMissionControl": false, "hideFromCapture": false, "hudShowPercentage": false, "hudOvershoot": true, "hudGlow": true, "chargingSound": true, "lowBatteryAlerts": true, "lowBatterySound": true, "lowPowerModeAlert": true, "calendarLiveActivity": true, "timeToLeaveAlert": true, "showDeclinedEvents": false, "excludeSubscribedCalendars": true, "verticalSwipeGestures": true, "middleClickCycle": true, "marqueeTitles": true, "showMusicWhenPaused": false, "showAudioBadges": true, "useMediaRemote": true, "bluetoothActivity": true, "focusActivity": true, "simulatedNotch": true, "showOnAllDisplays": false, "onboardingDone": false, "hoverDelay": 0.0, "notchWidthOffset": 0.0, "notchHeightOffset": 0.0, "calendarLeadMinutes": 10, "displayID": 0])
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
        hideInFullscreen = defaults.bool(forKey: "hideInFullscreen")
        hideWhileGaming = defaults.bool(forKey: "hideWhileGaming")
        hideInMissionControl = defaults.bool(forKey: "hideInMissionControl")
        hideFromCapture = defaults.bool(forKey: "hideFromCapture")
        hudShowPercentage = defaults.bool(forKey: "hudShowPercentage")
        hudOvershoot = defaults.bool(forKey: "hudOvershoot")
        hudGlow = defaults.bool(forKey: "hudGlow")
        chargingSound = defaults.bool(forKey: "chargingSound")
        lowBatteryAlerts = defaults.bool(forKey: "lowBatteryAlerts")
        lowBatterySound = defaults.bool(forKey: "lowBatterySound")
        lowPowerModeAlert = defaults.bool(forKey: "lowPowerModeAlert")
        calendarLiveActivity = defaults.bool(forKey: "calendarLiveActivity")
        timeToLeaveAlert = defaults.bool(forKey: "timeToLeaveAlert")
        showDeclinedEvents = defaults.bool(forKey: "showDeclinedEvents")
        excludeSubscribedCalendars = defaults.bool(forKey: "excludeSubscribedCalendars")
        verticalSwipeGestures = defaults.bool(forKey: "verticalSwipeGestures")
        middleClickCycle = defaults.bool(forKey: "middleClickCycle")
        marqueeTitles = defaults.bool(forKey: "marqueeTitles")
        showMusicWhenPaused = defaults.bool(forKey: "showMusicWhenPaused")
        showAudioBadges = defaults.bool(forKey: "showAudioBadges")
        useMediaRemote = defaults.bool(forKey: "useMediaRemote")
        bluetoothActivity = defaults.bool(forKey: "bluetoothActivity")
        focusActivity = defaults.bool(forKey: "focusActivity")
        simulatedNotch = defaults.bool(forKey: "simulatedNotch")
        showOnAllDisplays = defaults.bool(forKey: "showOnAllDisplays")
        onboardingDone = defaults.bool(forKey: "onboardingDone")
        hoverDelay = defaults.double(forKey: "hoverDelay")
        notchWidthOffset = defaults.double(forKey: "notchWidthOffset")
        notchHeightOffset = defaults.double(forKey: "notchHeightOffset")
        calendarLeadMinutes = defaults.integer(forKey: "calendarLeadMinutes")
        effectStyle = EffectStyle(rawValue: defaults.string(forKey: "effectStyle") ?? "") ?? .accretion
        hudSpeed = HUDSpeed(rawValue: defaults.string(forKey: "hudSpeed") ?? "") ?? .smooth
        calendarApp = CalendarApp(rawValue: defaults.string(forKey: "calendarApp") ?? "") ?? .calendar
        displayID = UInt32(defaults.integer(forKey: "displayID"))
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
