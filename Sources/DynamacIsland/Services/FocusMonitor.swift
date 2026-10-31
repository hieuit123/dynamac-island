import AppKit

/// Watches the Focus (Do Not Disturb) database for changes with a kernel vnode source – no polling.
/// Reading it requires Full Disk Access; `isAvailable` is false until that is granted.
@MainActor
final class FocusMonitor {
    struct Mode: Equatable {
        var name: String
        var symbol: String
        var tint: String
    }

    var onChange: ((_ mode: Mode, _ on: Bool) -> Void)?
    private(set) var isAvailable = false
    private var source: DispatchSourceFileSystemObject?
    private var current: Mode?
    private var debounce: DispatchWorkItem?

    private static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)

    static var hasAccess: Bool {
        FileManager.default.isReadableFile(atPath: directory.appendingPathComponent("Assertions.json").path)
            && (try? Data(contentsOf: directory.appendingPathComponent("Assertions.json"))) != nil
    }

    func start() {
        guard source == nil else { return }
        let fd = open(Self.directory.path, O_EVTONLY)
        guard fd >= 0, Self.hasAccess else {
            if fd >= 0 { close(fd) }
            isAvailable = false
            return
        }
        isAvailable = true
        current = Self.readActiveMode()
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .extend],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRead() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func scheduleRead() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let mode = Self.readActiveMode()
            guard mode != self.current else { return }
            if let mode {
                self.onChange?(mode, true)
            } else if let previous = self.current {
                self.onChange?(previous, false)
            }
            self.current = mode
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private static func json(_ name: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func readActiveMode() -> Mode? {
        guard let assertions = json("Assertions.json"),
              let records = ((assertions["data"] as? [[String: Any]])?.first?["storeAssertionRecords"] as? [[String: Any]]),
              let details = records.first?["assertionDetails"] as? [String: Any],
              let identifier = details["assertionDetailsModeIdentifier"] as? String else { return nil }
        let configs = (json("ModeConfigurations.json")?["data"] as? [[String: Any]])?.first?["modeConfigurations"] as? [String: Any]
        let mode = (configs?[identifier] as? [String: Any])?["mode"] as? [String: Any]
        return Mode(name: mode?["name"] as? String ?? "Do Not Disturb",
                    symbol: mode?["symbolImageName"] as? String ?? "moon.fill",
                    tint: mode?["tintColorName"] as? String ?? "systemIndigoColor")
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
