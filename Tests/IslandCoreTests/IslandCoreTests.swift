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
