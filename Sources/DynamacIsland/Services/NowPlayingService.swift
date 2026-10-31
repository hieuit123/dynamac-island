import AppKit
import Combine

/// Event-driven Now Playing for Apple Music and Spotify (no polling).
@MainActor
final class NowPlayingService: ObservableObject {
    enum Source: String {
        case music = "Music", spotify = "Spotify"
        var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
        var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    }

    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var source: Source
    }

    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?

    private let scriptQueue = DispatchQueue(label: "dynamac.nowplaying.script", qos: .utility)
    private var observers: [NSObjectProtocol] = []

    init() {
        let dnc = DistributedNotificationCenter.default()
        let pairs: [(String, Source)] = [("com.apple.Music.playerInfo", .music), ("com.spotify.client.PlaybackStateChanged", .spotify)]
        for (name, source) in pairs {
            observers.append(dnc.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                MainActor.assumeIsolated { self?.handle(info, source: source) }
            })
        }
        loadInitialState()
    }

    // MARK: Controls

    func playPause() { send("playpause", fallbackKey: MediaKeyPoster.play) }
    func next() { send("next track", fallbackKey: MediaKeyPoster.next) }
    func previous() { send("previous track", fallbackKey: MediaKeyPoster.previous) }

    private func send(_ command: String, fallbackKey: Int32) {
        if let source = track?.source, source.isRunning {
            runScript("tell application \"\(source.rawValue)\" to \(command)") { _ in }
        } else {
            MediaKeyPoster.post(fallbackKey)
        }
    }

    // MARK: State

    private func handle(_ info: [AnyHashable: Any], source: Source) {
        let state = (info["Player State"] as? String ?? "").lowercased()
        if state == "stopped" || state.isEmpty {
            if track?.source == source { track = nil; isPlaying = false; artwork = nil }
            return
        }
        let playing = state == "playing"
        // Ignore a paused event from another player while the current one keeps playing.
        if !playing, isPlaying, let current = track, current.source != source { return }

        let newTrack = Track(title: info["Name"] as? String ?? "",
                             artist: info["Artist"] as? String ?? "",
                             album: info["Album"] as? String ?? "",
                             source: source)
        if newTrack != track {
            track = newTrack
            artwork = nil
            fetchArtwork(for: newTrack)
        }
        isPlaying = playing
    }

    private func loadInitialState() {
        for source in [Source.spotify, .music] where source.isRunning {
            let script = """
            tell application "\(source.rawValue)"
                if player state is stopped then return ""
                set t to current track
                return (player state as text) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t)
            end tell
            """
            runScript(script) { [weak self] result in
                guard let lines = result?.stringValue?.components(separatedBy: "\n"), lines.count >= 4 else { return }
                self?.handle(["Player State": lines[0], "Name": lines[1], "Artist": lines[2], "Album": lines[3]], source: source)
            }
        }
    }

    private func fetchArtwork(for track: Track) {
        guard track.source.isRunning else { return }
        switch track.source {
        case .music:
            runScript("tell application \"Music\" to get raw data of artwork 1 of current track") { [weak self] result in
                guard let self, self.track == track, let data = result?.data, let image = NSImage(data: data) else { return }
                self.artwork = image
            }
        case .spotify:
            runScript("tell application \"Spotify\" to get artwork url of current track") { [weak self] result in
                guard let string = result?.stringValue, let url = URL(string: string) else { return }
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async {
                        guard let self, self.track == track else { return }
                        self.artwork = image
                    }
                }.resume()
            }
        }
    }

    private func runScript(_ source: String, completion: @escaping @MainActor (NSAppleEventDescriptor?) -> Void) {
        scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.async { completion(error == nil ? result : nil) }
        }
    }
}

/// Posts hardware media-key events (fallback for players other than Music/Spotify).
enum MediaKeyPoster {
    static let play: Int32 = 16, next: Int32 = 17, previous: Int32 = 18

    static func post(_ key: Int32) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
