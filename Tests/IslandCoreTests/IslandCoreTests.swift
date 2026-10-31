import CoreGraphics
import Foundation
import Testing
@testable import IslandCore

@Suite struct ShelfStoreTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    @Test func persistsAcrossInstancesAndDedupes() throws {
        let store = dir.appendingPathComponent("shelf.json")
        let a = try makeFile("a.txt")
        let shelf = ShelfStore(fileURL: store)
        #expect(shelf.add([a, a, dir.appendingPathComponent("missing.txt")]) == 1)
        #expect(shelf.add([a]) == 0)

        let reloaded = ShelfStore(fileURL: store)
        #expect(reloaded.items.map(\.name) == ["a.txt"])
        #expect(reloaded.allURLs.first?.standardizedFileURL.path == a.standardizedFileURL.path)
    }

    @Test func prunesDeletedFiles() throws {
        let store = dir.appendingPathComponent("shelf.json")
        let a = try makeFile("a.txt"), b = try makeFile("b.txt")
        let shelf = ShelfStore(fileURL: store)
        shelf.add([a, b])
        try FileManager.default.removeItem(at: a)
        shelf.prune()
        #expect(shelf.items.map(\.name) == ["b.txt"])
        #expect(ShelfStore(fileURL: store).items.count == 1)
    }

    @Test func tracksRenamedFiles() throws {
        let store = dir.appendingPathComponent("shelf.json")
        let a = try makeFile("a.txt")
        let shelf = ShelfStore(fileURL: store)
        shelf.add([a])
        try FileManager.default.moveItem(at: a, to: dir.appendingPathComponent("renamed.txt"))
        shelf.prune()
        #expect(shelf.items.map(\.name) == ["renamed.txt"])
    }
}

@Suite struct CountdownTimerTests {
    @Test func pauseResumeKeepsRemaining() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var timer = CountdownTimer()
        timer.start(duration: 60, now: t0)
        timer.pause(now: t0.addingTimeInterval(20))
        #expect(timer.remaining(now: t0.addingTimeInterval(500)) == 40)
        timer.resume(now: t0.addingTimeInterval(100))
        #expect(timer.remaining(now: t0.addingTimeInterval(110)) == 30)
        #expect(timer.isFinished(now: t0.addingTimeInterval(140)))
    }

    @Test func ignoresInvalidTransitions() {
        var timer = CountdownTimer()
        timer.start(duration: 0)
        #expect(!timer.isActive)
        timer.resume()
        #expect(timer.state == .idle)
    }

    @Test func formats() {
        #expect(CountdownTimer.format(59.2) == "1:00")
        #expect(CountdownTimer.format(3725) == "1:02:05")
    }
}

@Suite struct ArtworkPaletteTests {
    private func image(_ halves: [(UInt8, UInt8, UInt8)]) -> CGImage {
        let w = 20, h = 20
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let c = halves[x < w / 2 ? 0 : halves.count - 1]
            let i = (y * w + x) * 4
            px[i] = c.0; px[i + 1] = c.1; px[i + 2] = c.2
        } }
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    @Test func picksDistinctDominantHues() {
        let colors = ArtworkPalette.extract(from: image([(220, 30, 30), (30, 40, 210)]))
        #expect(colors.count == 3)
        #expect(colors.contains { $0.r > 0.7 && $0.b < 0.4 })
        #expect(colors.contains { $0.b > 0.7 && $0.r < 0.4 })
    }

    @Test func grayscaleArtworkStaysNeutralAndBright() {
        let colors = ArtworkPalette.extract(from: image([(20, 20, 20), (200, 200, 200)]))
        #expect(colors[0].hsb.s <= 0.16)
        #expect(colors[0].hsb.v >= 0.85)
    }
}
