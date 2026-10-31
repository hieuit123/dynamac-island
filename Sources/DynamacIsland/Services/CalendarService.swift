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
    var nextEvent: EventInfo? { upcoming.first }

    private let store = EKEventStore()
    private let settings: AppSettings
    private let center: ActivityCenter
    private var observer: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    /// One-shot timers only (lead time, event start, next refresh) – nothing ticks in between.
    private var timers: [Timer] = []
    private var alertedEventIDs = Set<String>()

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
        guard access == .granted else {
            upcoming = []
            center.upcomingEvent = nil
            return
        }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(24 * 3600), calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > now && include($0) }
            .sorted { ($0.isAllDay ? 1 : 0, $0.startDate) < ($1.isAllDay ? 1 : 0, $1.startDate) }
        upcoming = events.prefix(3).map(Self.info)
        scheduleLiveActivity(events.first { !$0.isAllDay }.map(Self.info), now: now)
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

    private func scheduleLiveActivity(_ event: EventInfo?, now: Date) {
        var nextRefresh = now.addingTimeInterval(3 * 3600)
        defer { schedule(at: nextRefresh) { [weak self] in self?.refresh() } }

        guard let event, settings.calendarLiveActivity else {
            center.upcomingEvent = nil
            return
        }
        let lead = TimeInterval(settings.calendarLeadMinutes * 60)
        let showFrom = event.start.addingTimeInterval(-lead)
        let showUntil = event.start.addingTimeInterval(5 * 60)
        if now >= showFrom && now < showUntil {
            activate(event)
            nextRefresh = min(nextRefresh, showUntil)
        } else {
            center.upcomingEvent = nil
            nextRefresh = min(nextRefresh, showFrom)
        }
    }

    private func activate(_ event: EventInfo) {
        center.upcomingEvent = event
        guard settings.timeToLeaveAlert, !alertedEventIDs.contains(event.id) else { return }
        alertedEventIDs.insert(event.id)
        let minutes = max(Int(event.start.timeIntervalSinceNow / 60), 0)
        center.showTransient(.eventSoon(title: event.title, minutes: minutes, color: event.color), duration: 5, sound: "Ping")
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
