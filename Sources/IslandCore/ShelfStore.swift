import Combine
import Foundation

public struct ShelfItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var bookmark: Data
    public var name: String
    public let addedAt: Date
}

/// Keeps references (bookmarks) to files dropped on the island. Original files are never moved.
public final class ShelfStore: ObservableObject {
    @Published public private(set) var items: [ShelfItem] = []
    private var urlCache: [UUID: URL] = [:]
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        load()
        prune()
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Dynamac Island", isDirectory: true).appendingPathComponent("shelf.json")
    }

    public func url(for item: ShelfItem) -> URL? { urlCache[item.id] }

    public var allURLs: [URL] { items.compactMap { urlCache[$0.id] } }

    @discardableResult
    public func add(_ urls: [URL]) -> Int {
        var known = Set(urlCache.values.map { $0.standardizedFileURL.path })
        var added = 0
        for url in urls where url.isFileURL {
            let path = url.standardizedFileURL.path
            guard !known.contains(path), FileManager.default.fileExists(atPath: path),
                  let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            else { continue }
            let item = ShelfItem(id: UUID(), bookmark: data, name: url.lastPathComponent, addedAt: Date())
            items.append(item)
            urlCache[item.id] = url
            known.insert(path)
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    public func remove(id: UUID) {
        items.removeAll { $0.id == id }
        urlCache[id] = nil
        save()
    }

    public func clear() {
        items.removeAll()
        urlCache.removeAll()
        save()
    }

    /// Drops items whose file no longer exists, refreshes stale bookmarks and renamed files.
    public func prune() {
        var changed = false
        var kept: [ShelfItem] = []
        for var item in items {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: item.bookmark, options: [.withoutUI],
                                     relativeTo: nil, bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path)
            else {
                urlCache[item.id] = nil
                changed = true
                continue
            }
            if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                item.bookmark = fresh
                changed = true
            }
            if item.name != url.lastPathComponent {
                item.name = url.lastPathComponent
                changed = true
            }
            urlCache[item.id] = url
            kept.append(item)
        }
        if changed {
            items = kept
            save()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Dynamac Island: failed to save shelf: \(error)")
        }
    }
}
