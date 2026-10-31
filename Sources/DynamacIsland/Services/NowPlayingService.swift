import AppKit
import Combine
import IslandCore
import SwiftUI

/// Event-driven Now Playing for Apple Music and Spotify (no polling).
@MainActor
final class NowPlayingService: ObservableObject {
    enum Source: String {
        case music = "Music", spotify = "Spotify"
        var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
        var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    }

    enum RepeatMode: String { case off, all, one }

    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var source: Source
    }

    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    /// Vivid colors extracted from the artwork, used to theme the player and the black-hole effect.
    @Published private(set) var palette: [Color] = ArtworkPalette.fallback.map(\.color)
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var shuffle = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var isFavorite = false
    /// Position at `positionDate`; the UI extrapolates while playing instead of polling the player.
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var positionDate = Date()

    var canFavorite: Bool { track?.source == .music }
    var supportsRepeatOne: Bool { track?.source == .music }

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

    func elapsed(at date: Date = Date()) -> TimeInterval {
        let value = position + (isPlaying ? date.timeIntervalSince(positionDate) : 0)
        return duration > 0 ? min(max(value, 0), duration) : max(value, 0)
    }

    // MARK: Controls

    func playPause() {
        position = elapsed(); positionDate = Date()
        send("playpause", fallbackKey: MediaKeyPoster.play)
    }
    func next() { send("next track", fallbackKey: MediaKeyPoster.next) }
    func previous() { send("previous track", fallbackKey: MediaKeyPoster.previous) }

    func seek(to seconds: TimeInterval) {
        guard let source = runningSource else { return }
        position = seconds
        positionDate = Date()
        runScript("tell application \"\(source.rawValue)\" to set player position to \(String(format: "%.2f", seconds))") { _ in }
    }

    func toggleShuffle() {
        guard let source = runningSource else { return }
        shuffle.toggle()
        let property = source == .music ? "shuffle enabled" : "shuffling"
        runScript("tell application \"\(source.rawValue)\" to set \(property) to \(shuffle)") { _ in }
    }

    func cycleRepeat() {
        guard let source = runningSource else { return }
        switch source {
        case .music:
            repeatMode = repeatMode == .off ? .all : repeatMode == .all ? .one : .off
            runScript("tell application \"Music\" to set song repeat to \(repeatMode.rawValue)") { _ in }
        case .spotify:
            repeatMode = repeatMode == .off ? .all : .off
            runScript("tell application \"Spotify\" to set repeating to \(repeatMode != .off)") { _ in }
        }
    }

    func toggleFavorite() {
        guard runningSource == .music else { return }
        isFavorite.toggle()
        let value = isFavorite
        runScript("""
        tell application "Music"
            try
                set favorited of current track to \(value)
            on error
                set loved of current track to \(value)
            end try
        end tell
        """) { _ in }
    }

    /// Refreshes position, shuffle, repeat and favorite. Called on track/state changes and when the island expands.
    func refreshDetails() {
        guard let source = runningSource else { return }
        let script: String
        switch source {
        case .music:
            script = """
            tell application "Music"
                if player state is stopped then return ""
                set f to false
                try
                    set f to favorited of current track
                on error
                    try
                        set f to loved of current track
                    end try
                end try
                return (player position as text) & linefeed & (duration of current track as text) & linefeed & (shuffle enabled as text) & linefeed & (song repeat as text) & linefeed & (f as text)
            end tell
            """
        case .spotify:
            script = """
            tell application "Spotify"
                if player state is stopped then return ""
                return (player position as text) & linefeed & ((duration of current track) / 1000 as text) & linefeed & (shuffling as text) & linefeed & (repeating as text) & linefeed & "false"
            end tell
            """
        }
        let requestDate = Date()
        runScript(script) { [weak self] result in
            guard let self, let lines = result?.stringValue?.components(separatedBy: "\n"), lines.count >= 5 else { return }
            let number = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
            self.position = number(lines[0])
            self.positionDate = requestDate
            if number(lines[1]) > 0 { self.duration = number(lines[1]) }
            self.shuffle = lines[2] == "true"
            switch lines[3] {
            case "one": self.repeatMode = .one
            case "all", "true": self.repeatMode = .all
            default: self.repeatMode = .off
            }
            self.isFavorite = lines[4] == "true"
        }
    }

    private var runningSource: Source? {
        guard let source = track?.source, source.isRunning else { return nil }
        return source
    }

    private func send(_ command: String, fallbackKey: Int32) {
        if let source = runningSource {
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
        if let ms = (info["Total Time"] ?? info["Duration"]) as? Double, ms > 0 { duration = ms / 1000 }
        if let seconds = info["Playback Position"] as? Double {
            position = seconds
            positionDate = Date()
        } else if newTrack != track {
            position = 0
            positionDate = Date()
        }
        if newTrack != track {
            track = newTrack
            artwork = nil
            fetchArtwork(for: newTrack)
        }
        isPlaying = playing
        refreshDetails()
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

    private func setArtwork(_ image: NSImage, for track: Track) {
        guard self.track == track else { return }
        artwork = image
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        DispatchQueue.global(qos: .utility).async {
            let colors = ArtworkPalette.extract(from: cg)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.track == track else { return }
                self.palette = colors.map(\.color)
            }
        }
    }

    private func fetchArtwork(for track: Track) {
        guard track.source.isRunning else { return }
        switch track.source {
        case .music:
            runScript("tell application \"Music\" to get raw data of artwork 1 of current track") { [weak self] result in
                guard let data = result?.data, let image = NSImage(data: data) else { return }
                self?.setArtwork(image, for: track)
            }
        case .spotify:
            runScript("tell application \"Spotify\" to get artwork url of current track") { [weak self] result in
                guard let string = result?.stringValue, let url = URL(string: string) else { return }
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async { self?.setArtwork(image, for: track) }
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

extension RGB {
    var color: Color { Color(red: r, green: g, blue: b) }
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
