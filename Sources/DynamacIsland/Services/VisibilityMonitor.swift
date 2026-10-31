import AppKit
import Combine

/// Decides when islands should hide: a fullscreen app on that display, or a game in front.
/// Re-evaluated only on app activation / Space changes / screen changes (no polling).
@MainActor
final class VisibilityMonitor: ObservableObject {
    @Published private(set) var fullscreenDisplays = Set<CGDirectDisplayID>()
    @Published private(set) var isGaming = false

    private var observers: [NSObjectProtocol] = []

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleEvaluate() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleEvaluate() }
        })
        evaluate()
    }

    /// Space switches animate; evaluate right away and again once the transition settles.
    private func scheduleEvaluate() {
        evaluate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.evaluate() }
    }

    func evaluate() {
        let front = NSWorkspace.shared.frontmostApplication
        isGaming = front.map(Self.isGame) ?? false

        var displays = Set<CGDirectDisplayID>()
        if let pid = front?.processIdentifier, pid != ProcessInfo.processInfo.processIdentifier,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            let screens = NSScreen.screens.map { ($0.displayID, CGDisplayBounds($0.displayID)) }
            for window in windows where (window[kCGWindowOwnerPID as String] as? pid_t) == pid
                && (window[kCGWindowLayer as String] as? Int) == 0 {
                guard let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
                for (id, frame) in screens where bounds.equalTo(frame) {
                    displays.insert(id)
                }
            }
        }
        if displays != fullscreenDisplays { fullscreenDisplays = displays }
    }

    private static func isGame(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL, let info = Bundle(url: url)?.infoDictionary else { return false }
        let category = (info["LSApplicationCategoryType"] as? String ?? "").lowercased()
        return category.contains("games")
    }
}
