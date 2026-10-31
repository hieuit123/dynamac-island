import Foundation

/// Runs the bundled ungive/mediaremote-adapter (BSD-3-Clause) through `/usr/bin/perl`, which is entitled to
/// use MediaRemote on macOS 15.4+. Streams JSON now-playing updates for every media source.
final class MediaRemoteBridge: @unchecked Sendable {
    private let script: URL
    private let framework: URL
    private var process: Process?
    private var buffer = Data()
    private var stopping = false
    private var restarts: [Date] = []
    private var lifeline: Pipe?

    /// Called on the main queue with (payload, isDiff).
    var onPayload: (([String: Any], Bool) -> Void)?
    /// Called on the main queue when the adapter keeps failing; the caller should fall back to AppleScript.
    var onFailure: (() -> Void)?

    init?(bundle: Bundle = .main) {
        guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let framework = bundle.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
              FileManager.default.fileExists(atPath: framework.path) else { return nil }
        self.script = script
        self.framework = framework
    }

    func start() {
        stopping = false
        let process = Process()
        // The shell waits on our stdin pipe; when this app exits for any reason (even a crash or kill -9)
        // the pipe closes, `cat` returns and the adapter is terminated. No polling needed.
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "/usr/bin/perl \"$0\" \"$1\" stream --debounce=40 & child=$!; cat >/dev/null; kill $child 2>/dev/null",
                             script.path, framework.path]
        let lifeline = Pipe()
        process.standardInput = lifeline
        self.lifeline = lifeline
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        buffer.removeAll()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.consume(data)
        }
        process.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { self?.handleExit(status: proc.terminationStatus) }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            DispatchQueue.main.async { self.onFailure?() }
        }
    }

    func stop() {
        stopping = true
        try? lifeline?.fileHandleForWriting.close()
        lifeline = nil
        process = nil
    }

    /// Fire-and-forget command such as `send 2`, `seek 1000000`, `shuffle 1`, `repeat 3`, `speed 2`.
    func run(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, framework.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else { continue }
            let diff = object["diff"] as? Bool ?? false
            DispatchQueue.main.async { [weak self] in self?.onPayload?(payload, diff) }
        }
    }

    private func handleExit(status: Int32) {
        process = nil
        guard !stopping else { return }
        let now = Date()
        restarts = restarts.filter { now.timeIntervalSince($0) < 60 } + [now]
        if restarts.count > 3 {
            onFailure?()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.start() }
        }
    }
}
