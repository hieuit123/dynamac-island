import AppKit
import Combine
import IslandCore
import SwiftUI

/// Plays a sound bundled in the app's Resources (for example the alarm), or a system sound by name.
enum AlertSound {
    static let alarm = "alarm-clock-ringing"
    /// Keeps the sound alive while it plays.
    private static var playing: NSSound?

    static func play(_ name: String) {
        if let url = Bundle.main.url(forResource: name, withExtension: "aiff"),
           let sound = NSSound(contentsOf: url, byReference: true) {
            playing = sound
            sound.play()
        } else {
            // Not running from the app bundle (for example `swift run`): fall back to a system sound.
            (NSSound(named: name) ?? NSSound(named: "Glass"))?.play()
        }
    }
}

enum HUDKind: Equatable {
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
}

enum TransientActivity: Equatable {
    case charging(level: Int)
    case timerDone
    case lowBattery(level: Int)
    case lowPowerMode(on: Bool)
    case bluetooth(name: String, symbol: String, battery: Int?, connected: Bool)
    case focus(name: String, symbol: String, tint: String, on: Bool)
    case eventSoon(title: String, minutes: Int, color: NSColor)
    case linkCopied

    /// Whether the right side needs extra room (longer labels).
    var isWide: Bool {
        switch self {
        case .bluetooth, .focus, .eventSoon, .lowPowerMode, .linkCopied, .timerDone: return true
        default: return false
        }
    }
}

/// Island-independent state shared by every island (one per display): HUD, live activities,
/// timer and dismissals.
@MainActor
final class ActivityCenter: ObservableObject {
    @Published private(set) var hud: HUDKind?
    /// Incremented when a HUD key is pressed at 0% / 100% to trigger the overshoot bounce.
    @Published private(set) var hudBump = 0
    @Published private(set) var transient: TransientActivity?
    @Published private(set) var timer = CountdownTimer()
    @Published private(set) var isSuspended = false
    /// Calendar events inside their live-activity window (soon to start, or just started), earliest first.
    @Published private(set) var upcomingEvents: [CalendarService.EventInfo] = []
    /// Events the user closed; forgotten once they leave the window.
    @Published private(set) var dismissedEventIDs = Set<String>()
    /// Identifier of a live activity the user swiped away; it stays hidden until the activity changes.
    @Published var dismissedActivityID: String?

    var visibleEvents: [CalendarService.EventInfo] { upcomingEvents.filter { !dismissedEventIDs.contains($0.id) } }

    var onSuspendChange: (Bool) -> Void = { _ in }

    private let settings: AppSettings
    private var hudWork: DispatchWorkItem?
    private var transientWork: DispatchWorkItem?
    private var timerFire: Timer?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
        if suspended { hud = nil }
        onSuspendChange(suspended)
    }

    // MARK: HUD & transient activities

    func showHUD(_ kind: HUDKind, atLimit: Bool = false) {
        hud = kind
        if atLimit, settings.hudOvershoot { hudBump += 1 }
        hudWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hud = nil }
        hudWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func showTransient(_ activity: TransientActivity, duration: TimeInterval = 3, sound: String? = nil) {
        transient = activity
        if let sound { AlertSound.play(sound) }
        transientWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.transient = nil }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func dismissTransient() {
        transientWork?.cancel()
        transient = nil
    }

    func setUpcomingEvents(_ events: [CalendarService.EventInfo]) {
        if events != upcomingEvents { upcomingEvents = events }
        let ids = Set(events.map(\.id))
        if !dismissedEventIDs.isSubset(of: ids) { dismissedEventIDs.formIntersection(ids) }
    }

    func dismissEvent(_ id: String) {
        dismissedEventIDs.insert(id)
    }

    func dismissAllEvents() {
        dismissedEventIDs.formUnion(upcomingEvents.map(\.id))
    }

    // MARK: Timer (a single one-shot Timer at the end date; no per-second ticking)

    static let maxTimerSeconds = 24 * 3600

    func startTimer(seconds: Int) {
        timer.start(duration: TimeInterval(min(seconds, Self.maxTimerSeconds)))
        scheduleTimerFire()
    }

    func pauseTimer() {
        timer.pause()
        timerFire?.invalidate()
    }

    func resumeTimer() {
        timer.resume()
        scheduleTimerFire()
    }

    func stopTimer() {
        timer.stop()
        timerFire?.invalidate()
    }

    private func scheduleTimerFire() {
        timerFire?.invalidate()
        guard let end = timer.endDate else { return }
        let t = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerFinished() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timerFire = t
    }

    private func timerFinished() {
        timer.stop()
        showTransient(.timerDone, duration: 5, sound: AlertSound.alarm)
    }
}

/// References to the shared services, handed to every island.
@MainActor
final class AppActivities {
    let center: ActivityCenter
    let nowPlaying: NowPlayingService
    let battery: BatteryService
    let calendar: CalendarService
    let shelf: ShelfStore
    let pet: PetStore

    init(center: ActivityCenter, nowPlaying: NowPlayingService, battery: BatteryService,
         calendar: CalendarService, shelf: ShelfStore, pet: PetStore) {
        self.center = center
        self.nowPlaying = nowPlaying
        self.battery = battery
        self.calendar = calendar
        self.shelf = shelf
        self.pet = pet
    }
}
