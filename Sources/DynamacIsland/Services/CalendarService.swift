import AppKit
import Combine
import EventKit

@MainActor
final class CalendarService: ObservableObject {
    enum Access { case notDetermined, granted, denied }

    struct EventInfo: Equatable {
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var color: NSColor
    }

    @Published private(set) var access: Access
    @Published private(set) var upcoming: [EventInfo] = []
    var nextEvent: EventInfo? { upcoming.first }

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    init() {
        access = Self.currentAccess()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
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

    /// Cheap on-demand query; called when the island expands and when the store changes.
    func refresh() {
        guard access == .granted else { upcoming = []; return }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(24 * 3600), calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { ($0.isAllDay ? 1 : 0, $0.startDate) < ($1.isAllDay ? 1 : 0, $1.startDate) }
        upcoming = events.prefix(3).map {
            EventInfo(title: $0.title ?? "Event", start: $0.startDate, end: $0.endDate,
                      isAllDay: $0.isAllDay, color: $0.calendar.map { NSColor(cgColor: $0.cgColor) ?? .systemBlue } ?? .systemBlue)
        }
    }
}
