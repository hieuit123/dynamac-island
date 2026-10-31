import AppKit

/// Suspends the island while the display sleeps, the Mac sleeps or the user session is inactive.
@MainActor
final class PowerStateMonitor {
    var onChange: ((_ suspended: Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        let suspend: [Notification.Name] = [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification,
                                            NSWorkspace.sessionDidResignActiveNotification]
        let resume: [Notification.Name] = [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification,
                                           NSWorkspace.sessionDidBecomeActiveNotification]
        for name in suspend {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?(true) }
            })
        }
        for name in resume {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?(false) }
            })
        }
    }
}
