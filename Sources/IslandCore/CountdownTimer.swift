import Foundation

public struct CountdownTimer: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
    }

    public private(set) var state: State = .idle
    public private(set) var duration: TimeInterval = 0

    public init() {}

    public var isActive: Bool { state != .idle }

    public var endDate: Date? {
        if case let .running(end) = state { return end }
        return nil
    }

    public mutating func start(duration: TimeInterval, now: Date = Date()) {
        guard duration > 0 else { return }
        self.duration = duration
        state = .running(endDate: now.addingTimeInterval(duration))
    }

    public mutating func pause(now: Date = Date()) {
        guard case let .running(end) = state else { return }
        state = .paused(remaining: max(0, end.timeIntervalSince(now)))
    }

    public mutating func resume(now: Date = Date()) {
        guard case let .paused(remaining) = state else { return }
        state = .running(endDate: now.addingTimeInterval(remaining))
    }

    public mutating func stop() {
        state = .idle
        duration = 0
    }

    public func remaining(now: Date = Date()) -> TimeInterval {
        switch state {
        case .idle: return 0
        case let .running(end): return max(0, end.timeIntervalSince(now))
        case let .paused(remaining): return remaining
        }
    }

    public func isFinished(now: Date = Date()) -> Bool {
        if case let .running(end) = state { return end <= now }
        return false
    }

    public static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
