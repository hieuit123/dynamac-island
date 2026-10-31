import AppKit
import Combine
import IslandCore
import SwiftUI

/// Now Playing for every media source via MediaRemote (bundled adapter), with an AppleScript fallback for
/// Music/Spotify. Fully event-driven: no polling.
@MainActor
final class NowPlayingService: ObservableObject {
    enum Source: String {
        case music = "Music", spotify = "Spotify"
        var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
        var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
        init?(bundleID: String) {
            switch bundleID {
            case "com.apple.Music": self = .music
            case "com.spotify.client": self = .spotify
            default: return nil
            }
        }
    }

    enum RepeatMode: String { case off, all, one }

    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var bundleID: String
        var scriptSource: Source? { Source(bundleID: bundleID) }
    }

    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var appIcon: NSImage?
    /// Vivid colors extracted from the artwork, used to theme the player and the black-hole effect.
    @Published private(set) var palette: [Color] = ArtworkPalette.fallback.map(\.color)
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var shuffle = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var isFavorite = false
    @Published private(set) var playbackRate: Double = 1
    /// "Lossless" / "Hi-Res Lossless" when the player exposes the stream quality (Apple Music files).
    @Published private(set) var audioBadge: String?
    /// Position at `positionDate`; the UI extrapolates while playing instead of polling the player.
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var positionDate = Date()
    @Published private(set) var usingMediaRemote = false

    var onLinkCopied: () -> Void = {}

    var canFavorite: Bool { track?.scriptSource == .music }
    var supportsRepeatOne: Bool { track?.scriptSource != .spotify }
    /// Speed control is offered for podcasts, video and browser media (MediaRemote only accepts whole numbers).
    var supportsSpeed: Bool { usingMediaRemote && track != nil && track?.scriptSource == nil }

    private let settings: AppSettings
    private let scriptQueue = DispatchQueue(label: "dynamac.nowplaying.script", qos: .utility)
    private var observers: [NSObjectProtocol] = []
    private var bridge: MediaRemoteBridge?
    private var mrState: [String: Any] = [:]
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(settings: AppSettings) {
        self.settings = settings
        let dnc = DistributedNotificationCenter.default()
        let pairs: [(String, Source)] = [("com.apple.Music.playerInfo", .music), ("com.spotify.client.PlaybackStateChanged", .spotify)]
        for (name, source) in pairs {
            observers.append(dnc.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                MainActor.assumeIsolated {
                    guard let self, !self.usingMediaRemote else { return }
                    self.handleScriptNotification(info, source: source)
                }
            })
        }
        if settings.useMediaRemote, let bridge = MediaRemoteBridge() {
            startMediaRemote(bridge)
        } else {
            loadInitialScriptState()
        }
    }

    func stop() { bridge?.stop() }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        let value = position + (isPlaying ? date.timeIntervalSince(positionDate) * playbackRate : 0)
        return duration > 0 ? min(max(value, 0), duration) : max(value, 0)
    }

    // MARK: Controls

    func playPause() {
        position = elapsed(); positionDate = Date()
        command(mr: ["send", "2"], script: "playpause", key: MediaKeyPoster.play)
    }
    func next() { command(mr: ["send", "4"], script: "next track", key: MediaKeyPoster.next) }
    func previous() { command(mr: ["send", "5"], script: "previous track", key: MediaKeyPoster.previous) }

    func seek(to seconds: TimeInterval) {
        position = seconds
        positionDate = Date()
        if usingMediaRemote, let bridge {
            bridge.run(["seek", String(Int(seconds * 1_000_000))])
        } else if let source = runningScriptSource {
            runScript("tell application \"\(source.rawValue)\" to set player position to \(String(format: "%.2f", seconds))") { _ in }
        }
    }

    func toggleShuffle() {
        shuffle.toggle()
        if let source = runningScriptSource {
            let property = source == .music ? "shuffle enabled" : "shuffling"
            runScript("tell application \"\(source.rawValue)\" to set \(property) to \(shuffle)") { _ in }
        } else {
            bridge?.run(["shuffle", shuffle ? "3" : "1"])
        }
    }

    func cycleRepeat() {
        repeatMode = repeatMode == .off ? .all : (repeatMode == .all && supportsRepeatOne) ? .one : .off
        switch runningScriptSource {
        case .music?:
            runScript("tell application \"Music\" to set song repeat to \(repeatMode.rawValue)") { _ in }
        case .spotify?:
            runScript("tell application \"Spotify\" to set repeating to \(repeatMode != .off)") { _ in }
        case nil:
            bridge?.run(["repeat", repeatMode == .off ? "1" : repeatMode == .one ? "2" : "3"])
        }
    }

    func cycleSpeed() {
        guard supportsSpeed else { return }
        playbackRate = playbackRate >= 2 ? 1 : 2
        position = elapsed(); positionDate = Date()
        bridge?.run(["speed", String(Int(playbackRate))])
    }

    func toggleFavorite() {
        guard runningScriptSource == .music else { return }
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

    /// Copies a shareable link: Spotify URL, Apple Music link (via the iTunes Search API), or "Title — Artist".
    func copyLink() {
        guard let track else { return }
        let fallback = [track.title, track.artist].filter { !$0.isEmpty }.joined(separator: " — ")
        switch runningScriptSource {
        case .spotify?:
            runScript("tell application \"Spotify\" to get spotify url of current track") { [weak self] result in
                let uri = result?.stringValue ?? ""
                let id = uri.split(separator: ":").last.map(String.init) ?? ""
                self?.copy(id.isEmpty ? fallback : "https://open.spotify.com/track/\(id)")
            }
        default:
            var components = URLComponents(string: "https://itunes.apple.com/search")!
            components.queryItems = [.init(name: "term", value: "\(track.title) \(track.artist)"),
                                     .init(name: "entity", value: "song"), .init(name: "limit", value: "1")]
            URLSession.shared.dataTask(with: components.url!) { data, _, _ in
                let link = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    .flatMap { ($0["results"] as? [[String: Any]])?.first?["trackViewUrl"] as? String }
                DispatchQueue.main.async { [weak self] in self?.copy(link ?? fallback) }
            }.resume()
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        onLinkCopied()
    }

    private var runningScriptSource: Source? {
        guard let source = track?.scriptSource, source.isRunning else { return nil }
        return source
    }

    private func command(mr: [String], script: String, key: Int32) {
        if usingMediaRemote, let bridge {
            bridge.run(mr)
        } else if let source = runningScriptSource {
            runScript("tell application \"\(source.rawValue)\" to \(script)") { _ in }
        } else {
            MediaKeyPoster.post(key)
        }
    }

    // MARK: MediaRemote backend

    private func startMediaRemote(_ bridge: MediaRemoteBridge) {
        self.bridge = bridge
        usingMediaRemote = true
        bridge.onPayload = { [weak self] payload, diff in
            MainActor.assumeIsolated { self?.applyMediaRemote(payload, diff: diff) }
        }
        bridge.onFailure = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                NSLog("Dynamac Island: MediaRemote adapter unavailable, using AppleScript")
                self.usingMediaRemote = false
                self.bridge = nil
                self.loadInitialScriptState()
            }
        }
        bridge.start()
    }

    private func applyMediaRemote(_ payload: [String: Any], diff: Bool) {
        if !diff { mrState.removeAll() }
        for (key, value) in payload {
            if value is NSNull { mrState[key] = nil } else { mrState[key] = value }
        }
        guard let title = mrState["title"] as? String, let bundleID = mrState["bundleIdentifier"] as? String else {
            track = nil
            isPlaying = false
            artwork = nil
            return
        }
        let appID = mrState["parentApplicationBundleIdentifier"] as? String ?? bundleID
        let newTrack = Track(title: title, artist: mrState["artist"] as? String ?? "",
                             album: mrState["album"] as? String ?? "", bundleID: appID)
        let changed = newTrack != track
        if changed {
            if appIcon == nil || track?.bundleID != appID { loadAppIcon(appID) }
            track = newTrack
            audioBadge = nil
            if payload["artworkData"] == nil { artwork = nil }
        }
        isPlaying = mrState["playing"] as? Bool ?? false
        // Paused players report a rate of 0; keep the last real speed for display and extrapolation.
        if let rate = mrState["playbackRate"] as? Double, rate > 0 { playbackRate = rate }
        duration = mrState["duration"] as? Double ?? 0
        if let elapsed = mrState["elapsedTime"] as? Double {
            position = elapsed
            positionDate = (mrState["timestamp"] as? String).flatMap(parseDate) ?? Date()
        }
        if let mode = mrState["shuffleMode"] as? Int { shuffle = mode > 1 }
        if let mode = mrState["repeatMode"] as? Int { repeatMode = mode == 2 ? .one : mode == 3 ? .all : .off }
        if mrState["supportsIsLiked"] as? Bool == true { isFavorite = mrState["isLiked"] as? Bool ?? false }
        if let base64 = payload["artworkData"] as? String, let data = Data(base64Encoded: base64), let image = NSImage(data: data) {
            setArtwork(image, for: newTrack)
        }
        if changed, newTrack.scriptSource != nil { refreshDetails() }
    }

    private func parseDate(_ string: String) -> Date? {
        if let date = isoFormatter.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    private func loadAppIcon(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { appIcon = nil; return }
        appIcon = NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: AppleScript backend / extras

    /// Reads shuffle, repeat, favorite and audio quality from Music/Spotify (and position when not on MediaRemote).
    func refreshDetails() {
        guard let source = runningScriptSource else { return }
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
                set sr to 0
                set br to 0
                try
                    set sr to sample rate of current track
                    set br to bit rate of current track
                end try
                return (player position as text) & linefeed & (duration of current track as text) & linefeed & (shuffle enabled as text) & linefeed & (song repeat as text) & linefeed & (f as text) & linefeed & (sr as text) & linefeed & (br as text)
            end tell
            """
        case .spotify:
            script = """
            tell application "Spotify"
                if player state is stopped then return ""
                return (player position as text) & linefeed & ((duration of current track) / 1000 as text) & linefeed & (shuffling as text) & linefeed & (repeating as text) & linefeed & "false" & linefeed & "0" & linefeed & "0"
            end tell
            """
        }
        let requestDate = Date()
        runScript(script) { [weak self] result in
            guard let self, let lines = result?.stringValue?.components(separatedBy: "\n"), lines.count >= 7 else { return }
            let number = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
            if !self.usingMediaRemote {
                self.position = number(lines[0])
                self.positionDate = requestDate
                if number(lines[1]) > 0 { self.duration = number(lines[1]) }
            }
            self.shuffle = lines[2] == "true"
            switch lines[3] {
            case "one": self.repeatMode = .one
            case "all", "true": self.repeatMode = .all
            default: self.repeatMode = .off
            }
            if source == .music { self.isFavorite = lines[4] == "true" }
            let sampleRate = number(lines[5]), bitRate = number(lines[6])
            self.audioBadge = sampleRate > 48000 ? "Hi-Res Lossless" : bitRate >= 700 ? "Lossless" : nil
        }
    }

    private func handleScriptNotification(_ info: [AnyHashable: Any], source: Source) {
        let state = (info["Player State"] as? String ?? "").lowercased()
        if state == "stopped" || state.isEmpty {
            if track?.scriptSource == source { track = nil; isPlaying = false; artwork = nil }
            return
        }
        let playing = state == "playing"
        if !playing, isPlaying, let current = track, current.scriptSource != source { return }

        let newTrack = Track(title: info["Name"] as? String ?? "", artist: info["Artist"] as? String ?? "",
                             album: info["Album"] as? String ?? "", bundleID: source.bundleID)
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
            audioBadge = nil
            loadAppIcon(source.bundleID)
            fetchScriptArtwork(for: newTrack)
        }
        isPlaying = playing
        refreshDetails()
    }

    private func loadInitialScriptState() {
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
                self?.handleScriptNotification(["Player State": lines[0], "Name": lines[1], "Artist": lines[2], "Album": lines[3]],
                                               source: source)
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

    private func fetchScriptArtwork(for track: Track) {
        guard let source = track.scriptSource, source.isRunning else { return }
        switch source {
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

/// Posts hardware media-key events (last-resort fallback).
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
