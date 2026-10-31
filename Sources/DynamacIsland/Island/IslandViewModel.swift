import AppKit
import Combine
import IslandCore

enum IslandState { case collapsed, peek, expanded }
enum ExpandedTab { case home, shelf }

enum HUDKind: Equatable {
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
}

enum TransientActivity: Equatable {
    case charging(level: Int)
    case timerDone
}

@MainActor
final class IslandViewModel: ObservableObject {
    @Published var state: IslandState = .collapsed { didSet { updateExitWatchdog() } }
    @Published var tab: ExpandedTab = .home
    @Published var hud: HUDKind?
    @Published var transient: TransientActivity?
    @Published private(set) var timer = CountdownTimer()
    @Published private(set) var isSuspended = false
    @Published var isDraggingOut = false { didSet { if !isDraggingOut { scheduleCollapse(after: 0.8) } } }
    @Published var isDropTargeted = false {
        didSet {
            guard isDropTargeted != oldValue else { return }
            if isDropTargeted {
                cancelPendingCollapse()
                tab = .shelf
                state = .expanded
            } else {
                scheduleCollapse(after: 1.2)
            }
        }
    }

    @Published var notchSize = CGSize(width: 190, height: 32)
    @Published var hasNotch = false

    var openSettings: () -> Void = {}
    var mouseInsideProbe: () -> Bool = { false }
    var onExpand: () -> Void = {}

    private let settings: AppSettings
    private var collapseWork: DispatchWorkItem?
    private var hudWork: DispatchWorkItem?
    private var transientWork: DispatchWorkItem?
    private var timerFire: Timer?
    private var exitWatchdog: Timer?

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Tracking areas can miss a mouse-exit on fast pointer jumps; poll slowly only while the island is open.
    private func updateExitWatchdog() {
        guard state != .collapsed else {
            exitWatchdog?.invalidate()
            exitWatchdog = nil
            return
        }
        guard exitWatchdog == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.collapseWork == nil, !self.isDropTargeted, !self.isDraggingOut,
                      !self.mouseInsideProbe() else { return }
                self.scheduleCollapse(after: 0.3)
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        exitWatchdog = timer
    }

    /// Effects render only while the island is active, so a collapsed island costs no GPU time.
    var effectIntensity: Double? {
        if isSuspended { return nil }
        if isDropTargeted { return 1.6 }
        switch state {
        case .collapsed: return nil
        case .peek: return 0.7
        case .expanded: return 1.0
        }
    }

    // MARK: Interaction

    func hoverChanged(_ inside: Bool) {
        if inside {
            cancelPendingCollapse()
            guard state == .collapsed, !isSuspended else { return }
            if settings.hapticsEnabled { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            if settings.expandOnHover { expand() } else { state = .peek }
        } else {
            scheduleCollapse(after: state == .expanded ? 0.4 : 0.15)
        }
    }

    func expand() {
        cancelPendingCollapse()
        guard state != .expanded else { return }
        state = .expanded
        onExpand()
    }

    func collapse() {
        cancelPendingCollapse()
        state = .collapsed
        tab = .home
    }

    func scheduleCollapse(after delay: TimeInterval) {
        cancelPendingCollapse()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWork = nil
            guard !self.isDropTargeted, !self.isDraggingOut, !self.mouseInsideProbe() else { return }
            self.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingCollapse() {
        collapseWork?.cancel()
        collapseWork = nil
    }

    func didDropFiles() {
        tab = .shelf
        state = .expanded
        scheduleCollapse(after: 1.5)
    }

    func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
        if suspended { collapse(); hud = nil }
    }

    // MARK: Live activities

    func showHUD(_ kind: HUDKind) {
        hud = kind
        hudWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hud = nil }
        hudWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func showTransient(_ activity: TransientActivity, duration: TimeInterval = 3) {
        transient = activity
        transientWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.transient = nil }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    // MARK: Timer (a single one-shot Timer at the end date; no per-second ticking)

    func startTimer(minutes: Double) {
        timer.start(duration: minutes * 60)
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
        NSSound(named: "Glass")?.play()
        showTransient(.timerDone, duration: 5)
    }
}
