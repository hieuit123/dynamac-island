import AppKit
import Combine
import EventKit

@MainActor
final class CalendarService: ObservableObject {
    enum Access { case notDetermined, granted, denied }

    struct EventInfo: Equatable {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var color: NSColor
        var location: String?
    }

    @Published private(set) var access: Access
    @Published private(set) var upcoming: [EventInfo] = []
    /// Day shown in the panel: 0 = today, 1 = tomorrow, 2 = the day after. The live activity and the badge always use today.
    @Published var selectedDay = 0
    /// Next event today; drives the dot on the Calendar icon.
    @Published private(set) var nextEvent: EventInfo?

    private let store = EKEventStore()
    private let settings: AppSettings
    private let center: ActivityCenter
    private var observer: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    /// One-shot timers only (lead time, event start, next refresh) – nothing ticks in between.
    private var timers: [Timer] = []
    /// Keys (event id plus start, so each occurrence of a recurring event counts) already alerted when they appeared, and at their start.
    private var leadAlerted = Set<String>()
    private var startAlerted = Set<String>()
    private var syncTimer: Timer?

    init(settings: AppSettings, center: ActivityCenter) {
        self.settings = settings
        self.center = center
        access = Self.currentAccess()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        Publishers.MergeMany(settings.$calendarLeadMinutes.map { _ in () }.eraseToAnyPublisher(),
                             settings.$showDeclinedEvents.map { _ in () }.eraseToAnyPublisher(),
                             settings.$excludeSubscribedCalendars.map { _ in () }.eraseToAnyPublisher(),
                             settings.$calendarLiveActivity.map { _ in () }.eraseToAnyPublisher())
            .dropFirst(4)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
        settings.$showCalendar.removeDuplicates().dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled { self?.startRemoteSync() } else { self?.stopRemoteSync() }
                if enabled { self?.syncNow() } else { self?.refresh() }
            }
            .store(in: &cancellables)
        if settings.showCalendar { startRemoteSync() }
        refresh()
    }

    /// Remote accounts (Google, Exchange) only sync when asked; pull changes every few minutes, they arrive via EKEventStoreChanged.
    private func startRemoteSync() {
        guard syncTimer == nil else { return }
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.access == .granted else { return }
                self.store.refreshSourcesIfNecessary()
            }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer
    }

    private func stopRemoteSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    /// Re-reads local events now and asks remote accounts to pull; late changes arrive via EKEventStoreChanged.
    func syncNow() {
        if settings.showCalendar, access == .granted { store.refreshSourcesIfNecessary() }
        refresh()
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { _, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.access = Self.currentAccess()
                self.refresh()
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Opening events

    func open(_ event: EventInfo?) {
        let date = event?.start ?? Date()
        switch settings.calendarApp {
        case .calendar:
            if let event, let encoded = event.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let url = URL(string: "ical://ekevent/\(encoded)?method=show&options=more") {
                NSWorkspace.shared.open(url)
            } else {
                openApp(.calendar)
            }
        case .fantastical:
            let day = date.formatted(.iso8601.year().month().day())
            if let url = URL(string: "x-fantastical3://show?date=\(day)"), NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
                NSWorkspace.shared.open(url)
            } else {
                openApp(.fantastical)
            }
        case .notion:
            openApp(.notion)
        }
    }

    private func openApp(_ app: CalendarApp) {
        let id = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) != nil ? app.bundleID : CalendarApp.calendar.bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: Query & scheduling

    /// Cheap on-demand query; called on expand, store changes, wake, and by its own one-shot timers.
    func refresh() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
        guard settings.showCalendar, access == .granted else {
            upcoming = []
            nextEvent = nil
            center.setUpcomingEvents([])
            return
        }
        let now = Date()
        let today = events(from: now, to: Self.startOfTomorrow(after: now), now: now)
        nextEvent = today.first.map(Self.info)
        if selectedDay == 0 {
            upcoming = today.map(Self.info)
        } else {
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: selectedDay, to: calendar.startOfDay(for: now)) ?? now
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 3600)
            upcoming = events(from: start, to: end, now: nil).map(Self.info)
        }
        // Events past their window are dropped here, so every refresh time computed below lies in the future.
        let pending = today.filter { !$0.isAllDay && $0.startDate.addingTimeInterval(Self.nowWindow) > now }
        scheduleLiveActivities(pending.map(Self.info), now: now)
    }

    /// Events in the range, all-day ones last. With `now` set, events that already ended are dropped.
    private func events(from start: Date, to end: Date, now: Date?) -> [EKEvent] {
        store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { event in (now.map { $0 < event.endDate } ?? true) && include(event) }
            .sorted { ($0.isAllDay ? 1 : 0, $0.startDate) < ($1.isAllDay ? 1 : 0, $1.startDate) }
    }

    private static func startOfTomorrow(after date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(24 * 3600)
    }

    private func include(_ event: EKEvent) -> Bool {
        if settings.excludeSubscribedCalendars, let type = event.calendar?.type, type == .subscription || type == .birthday {
            return false
        }
        if !settings.showDeclinedEvents,
           event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined {
            return false
        }
        return true
    }

    private static func info(_ event: EKEvent) -> EventInfo {
        EventInfo(id: event.calendarItemIdentifier, title: event.title ?? "Event", start: event.startDate, end: event.endDate,
                  isAllDay: event.isAllDay,
                  color: event.calendar.map { NSColor(cgColor: $0.cgColor) ?? .systemBlue } ?? .systemBlue,
                  location: event.location)
    }

    /// How long an event stays on the island after it starts.
    private static let nowWindow: TimeInterval = 5 * 60

    /// An event is shown from `lead` before its start until `nowWindow` after it; `events` are sorted by start.
    private func scheduleLiveActivities(_ events: [EventInfo], now: Date) {
        // Refresh at midnight too, so the list switches to the new day.
        var nextRefresh = min(now.addingTimeInterval(3 * 3600), Self.startOfTomorrow(after: now))
        defer { schedule(at: nextRefresh) { [weak self] in self?.refresh() } }

        guard settings.calendarLiveActivity else {
            center.setUpcomingEvents([])
            return
        }
        let lead = TimeInterval(settings.calendarLeadMinutes * 60)
        var active: [EventInfo] = []
        for event in events {
            let showFrom = event.start.addingTimeInterval(-lead)
            if now >= showFrom {
                active.append(event)
                // Wake up at the start (for the second alert), then when the event leaves the island.
                nextRefresh = min(nextRefresh, event.start > now ? event.start : event.start.addingTimeInterval(Self.nowWindow))
            } else {
                nextRefresh = min(nextRefresh, showFrom)
            }
        }
        center.setUpcomingEvents(active)
        alert(for: active, now: now)
    }

    private func key(_ event: EventInfo) -> String { "\(event.id)|\(event.start.timeIntervalSince1970)" }

    /// One alarm per meeting when it shows up on the island, and another at its start unless it was dismissed.
    private func alert(for active: [EventInfo], now: Date) {
        guard settings.timeToLeaveAlert else { return }
        var toAlert: [EventInfo] = []
        for event in active {
            let k = key(event)
            if now < event.start {
                if leadAlerted.insert(k).inserted { toAlert.append(event) }
            } else if startAlerted.insert(k).inserted {
                leadAlerted.insert(k)
                // A late refresh (a minute or more after the start) must not ring.
                if now.timeIntervalSince(event.start) < 60, !center.dismissedEventIDs.contains(event.id) { toAlert.append(event) }
            }
        }
        guard let first = toAlert.first else { return }
        let minutes = max(Int(ceil(first.start.timeIntervalSince(now) / 60)), 0)
        center.showTransient(.eventSoon(title: first.title, minutes: minutes, color: first.color), duration: 5, sound: nil)
        // Each meeting rings once; several at the same moment ring one after the other.
        for index in toAlert.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * (AlertSound.alarmDuration + 0.3)) {
                AlertSound.play(AlertSound.alarm)
            }
        }
    }

    private func schedule(at date: Date, _ action: @escaping @MainActor () -> Void) {
        let timer = Timer(fire: max(date, Date().addingTimeInterval(1)), interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }
}
