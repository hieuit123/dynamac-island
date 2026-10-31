import AppKit
import Combine
import IslandCore

enum IslandState { case collapsed, peek, expanded }
enum ExpandedTab: CaseIterable { case home, shelf, calendar, timer, battery }

/// Per-island UI state (one island per display). Shared state lives in `ActivityCenter`.
@MainActor
final class IslandViewModel: ObservableObject {
    @Published var state: IslandState = .collapsed { didSet { updateExitWatchdog(); updateEffectMount() } }
    @Published var tab: ExpandedTab = .home
    /// Keeps the effect alive while it fades out, then removes it so an idle island costs no GPU time.
    @Published private(set) var isEffectMounted = false
    /// Horizontal artwork offset driven by the swipe-to-skip gesture.
    @Published var swipeOffset: CGFloat = 0
    @Published var isDraggingOut = false { didSet { if !isDraggingOut { scheduleCollapse(after: 0.8) } } }
    @Published var isDropTargeted = false {
        didSet {
            guard isDropTargeted != oldValue else { return }
            updateEffectMount()
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
    /// Floating pill (instead of a simulated notch) on displays without a notch.
    @Published var pillMode = false

    var mouseInsideProbe: () -> Bool = { false }
    var onExpand: () -> Void = {}

    let activities: AppActivities
    private let settings: AppSettings
    private var collapseWork: DispatchWorkItem?
    private var hoverWork: DispatchWorkItem?
    /// Set after a deliberate collapse (swipe up) so the shrinking tracking area can't immediately re-expand it.
    private var ignoreHoverUntilExit = false
    private var exitWatchdog: Timer?
    private var effectUnmountWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings, activities: AppActivities) {
        self.settings = settings
        self.activities = activities
        activities.center.$isSuspended.removeDuplicates().sink { [weak self] suspended in
            guard let self else { return }
            if suspended { self.collapse() }
            DispatchQueue.main.async { self.updateEffectMount() }
        }.store(in: &cancellables)
    }

    private var isSuspended: Bool { activities.center.isSuspended }

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

    /// Target effect strength; 0 means fading out (or hidden once unmounted).
    var effectIntensity: Double {
        if isSuspended { return 0 }
        if isDropTargeted { return 1.6 }
        switch state {
        case .collapsed: return 0
        case .peek: return 0.7
        case .expanded: return 1.0
        }
    }

    private func updateEffectMount() {
        effectUnmountWork?.cancel()
        if effectIntensity > 0 {
            if !isEffectMounted { isEffectMounted = true }
            return
        }
        guard isEffectMounted else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.effectIntensity == 0 else { return }
            self.isEffectMounted = false
        }
        effectUnmountWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + IslandAnimation.collapseDuration + 0.1, execute: work)
    }

    // MARK: Interaction

    func hoverChanged(_ inside: Bool) {
        hoverWork?.cancel()
        if inside {
            if ignoreHoverUntilExit { return }
            cancelPendingCollapse()
            guard state == .collapsed, !isSuspended else { return }
            let delay = settings.hoverDelay
            guard delay > 0 else { return activateFromHover() }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.mouseInsideProbe() else { return }
                self.activateFromHover()
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            ignoreHoverUntilExit = false
            scheduleCollapse(after: state == .expanded ? 0.4 : 0.15)
        }
    }

    private func activateFromHover() {
        guard state == .collapsed else { return }
        if settings.hapticsEnabled { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        if settings.expandOnHover { expand() } else { state = .peek }
    }

    func expand() {
        cancelPendingCollapse()
        guard state != .expanded else { return }
        state = .expanded
        onExpand()
    }

    /// Collapse requested by the user while the pointer is still over the island.
    func dismiss() {
        ignoreHoverUntilExit = true
        collapse()
    }

    func collapse() {
        cancelPendingCollapse()
        state = .collapsed
        tab = .home
    }

    /// Swipe-down / middle-click: expand, or move to the next panel when already expanded.
    func cycleTab() {
        guard state == .expanded else { return expand() }
        let tabs = availableTabs
        let index = tabs.firstIndex(of: tab) ?? 0
        tab = tabs[(index + 1) % tabs.count]
    }

    var availableTabs: [ExpandedTab] {
        ExpandedTab.allCases.filter { tab in
            switch tab {
            case .calendar: return settings.showCalendar
            case .battery: return settings.showBattery && activities.battery.hasBattery
            default: return true
            }
        }
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
}
