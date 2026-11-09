import IslandCore
import SwiftUI
import UniformTypeIdentifiers

/// Loads dropped items; the screenshot thumbnail offers a short-lived temp file or only image data.
enum ShelfDrop {
    static let types: [UTType] = [.fileURL, .image]

    private static var storeDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Dynamac Island/Dropped", isDirectory: true)
    }

    static func load(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    let stored = isTemporary(url) ? copyToStore(url) : url
                    if let stored { DispatchQueue.main.async { completion([stored]) } }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let type = [UTType.png, .jpeg, .tiff].first { provider.hasItemConformingToTypeIdentifier($0.identifier) } ?? .image
                provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                    guard let url else { return }
                    let name = provider.suggestedName.map { $0.contains(".") ? $0 : "\($0).\(type.preferredFilenameExtension ?? "png")" }
                    if let stored = copyToStore(url, name: name) { DispatchQueue.main.async { completion([stored]) } }
                }
            }
        }
    }

    private static func isTemporary(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.contains("/TemporaryItems/") || path.hasPrefix("/var/folders/") || path.hasPrefix("/private/var/folders/")
    }

    private static func copyToStore(_ source: URL, name: String? = nil) -> URL? {
        let fm = FileManager.default
        let dir = storeDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = dir.appendingPathComponent(name ?? source.lastPathComponent)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: target)
            return target
        } catch {
            return nil
        }
    }
}

struct ShelfView: View {
    @ObservedObject var vm: IslandViewModel
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        Group {
            if vm.isDropTargeted || shelf.items.isEmpty {
                DropZone(active: vm.isDropTargeted)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(shelf.items) { item in
                                ShelfTile(item: item, url: shelf.url(for: item),
                                          onRemove: { shelf.remove(id: item.id) },
                                          onDragging: { vm.isDraggingOut = $0 })
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Text("Drag out to copy anywhere · double-click to open")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        ZStack {
                            Label("Drag all", systemImage: "hand.draw.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                            FileDragSource(urls: shelf.allURLs) { vm.isDraggingOut = $0 }
                        }
                        .fixedSize()
                        Button("Clear") { shelf.clear() }
                            .buttonStyle(PressableStyle())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { shelf.prune() }
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    let url: URL?
    let onRemove: () -> Void
    let onDragging: (Bool) -> Void

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
                .resizable()
                .frame(width: 48, height: 48)
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 76)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay { if let url { FileDragSource(urls: [url], onDragging: onDragging) } }
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(PressableStyle())
            .padding(3)
        }
        .help(url?.path ?? item.name)
    }
}

/// Shown while files hover over the island: a spinning singularity pulling them in.
private struct DropZone: View {
    let active: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.white.opacity(active ? 0.5 : 0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .overlay {
                VStack(spacing: 2) {
                    BlackHoleIcon(size: active ? 84 : 64, spinning: active)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: active)
                    Text(active ? "Release to drop into the black hole" : "Drop files into the black hole")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(active ? .white : .secondary)
                }
            }
    }
}
