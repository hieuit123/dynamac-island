import Combine
import Foundation

/// Virtual pet. Stats decay lazily from `updatedAt`, so nothing has to tick while the app is idle.
public struct Pet: Codable, Equatable, Sendable {
    public enum Species: String, Codable, CaseIterable, Sendable {
        case cat, dog, rabbit, chick, panda, fox
    }

    public enum Mood: Equatable, Sendable {
        case sleeping, hungry, tired, sad, happy, content
    }

    public var species: Species
    public var name: String
    public var fullness: Double
    public var happiness: Double
    public var energy: Double
    public var isSleeping: Bool
    public var xp: Int
    public var updatedAt: Date

    /// Hours of absence after which stats stop decaying, so a long break never leaves the pet hopeless.
    static let maxAbsenceHours = 12.0

    public init(species: Species = .cat, name: String = "Mochi", now: Date = Date()) {
        self.species = species
        self.name = name
        fullness = 0.8
        happiness = 0.8
        energy = 1
        isSleeping = false
        xp = 0
        updatedAt = now
    }

    public var level: Int { xp / 10 + 1 }

    /// Time until a sleeping pet wakes on its own (energy back to full); nil while awake.
    public var sleepRemaining: TimeInterval? {
        isSleeping ? (1 - energy) * Self.fullSleepHours * 3600 : nil
    }

    /// Hours of sleep to refill energy from empty.
    static let fullSleepHours = 0.5

    public var mood: Mood {
        if isSleeping { return .sleeping }
        if fullness < 0.25 { return .hungry }
        if energy < 0.2 { return .tired }
        if happiness < 0.25 { return .sad }
        return happiness > 0.75 && fullness > 0.5 ? .happy : .content
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    /// Applies the time elapsed since `updatedAt`.
    public mutating func advance(to now: Date) {
        let hours = min(max(now.timeIntervalSince(updatedAt), 0) / 3600, Self.maxAbsenceHours)
        updatedAt = now
        guard hours > 0 else { return }
        if isSleeping {
            energy = Self.clamp(energy + hours / Self.fullSleepHours)
            fullness = Self.clamp(fullness - hours / 16)
            happiness = Self.clamp(happiness - hours / 24)
            if energy >= 1 { isSleeping = false }
        } else {
            fullness = Self.clamp(fullness - hours / 8)
            happiness = Self.clamp(happiness - hours / (fullness < 0.2 ? 6 : 12))
            energy = Self.clamp(energy - hours / 16)
            if energy <= 0.05 { isSleeping = true }
        }
    }

    public func advanced(to now: Date) -> Pet {
        var copy = self
        copy.advance(to: now)
        return copy
    }

    /// Returns false when the pet refuses (asleep or not hungry).
    @discardableResult
    public mutating func feed(now: Date = Date()) -> Bool {
        advance(to: now)
        guard !isSleeping, fullness <= 0.9 else { return false }
        fullness = Self.clamp(fullness + 0.35)
        happiness = Self.clamp(happiness + 0.05)
        xp += 1
        return true
    }

    /// Returns false when the pet refuses (asleep or too tired).
    @discardableResult
    public mutating func play(now: Date = Date()) -> Bool {
        advance(to: now)
        guard !isSleeping, energy >= 0.15 else { return false }
        happiness = Self.clamp(happiness + 0.25)
        energy = Self.clamp(energy - 0.12)
        fullness = Self.clamp(fullness - 0.05)
        xp += 2
        return true
    }

    public mutating func toggleSleep(now: Date = Date()) {
        advance(to: now)
        isSleeping.toggle()
    }
}

/// Persists the pet as JSON next to the shelf.
public final class PetStore: ObservableObject {
    @Published public private(set) var pet: Pet
    private let fileURL: URL

    public init(fileURL: URL, now: Date = Date()) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode(Pet.self, from: data) {
            pet = saved
        } else {
            pet = Pet(now: now)
        }
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Dynamac Island", isDirectory: true).appendingPathComponent("pet.json")
    }

    /// Current stats without mutating the stored pet; cheap enough to call from a view.
    public func current(at date: Date = Date()) -> Pet { pet.advanced(to: date) }

    @discardableResult
    public func feed(now: Date = Date()) -> Bool { mutate { $0.feed(now: now) } }

    @discardableResult
    public func play(now: Date = Date()) -> Bool { mutate { $0.play(now: now) } }

    public func toggleSleep(now: Date = Date()) { _ = mutate { $0.toggleSleep(now: now); return true } }

    public func setSpecies(_ species: Pet.Species) {
        guard pet.species != species else { return }
        pet.species = species
        save()
    }

    public func rename(_ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
        guard !trimmed.isEmpty, trimmed != pet.name else { return }
        pet.name = trimmed
        save()
    }

    private func mutate(_ change: (inout Pet) -> Bool) -> Bool {
        var next = pet
        let result = change(&next)
        pet = next
        save()
        return result
    }

    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(pet) { try? data.write(to: fileURL, options: .atomic) }
    }
}
