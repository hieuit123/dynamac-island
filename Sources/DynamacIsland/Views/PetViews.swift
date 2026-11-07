import IslandCore
import SwiftUI

extension Pet.Species {
    var emoji: String {
        switch self {
        case .cat: return "🐱"
        case .dog: return "🐶"
        case .rabbit: return "🐰"
        case .chick: return "🐥"
        case .panda: return "🐼"
        case .fox: return "🦊"
        }
    }
}

extension Pet.Mood {
    var emoji: String {
        switch self {
        case .sleeping: return "💤"
        case .hungry: return "🍖"
        case .tired: return "🥱"
        case .sad: return "💧"
        case .happy: return "❤️"
        case .content: return "🙂"
        }
    }

    var line: String {
        switch self {
        case .sleeping: return "Zzz…"
        case .hungry: return "I'm hungry!"
        case .tired: return "So sleepy…"
        case .sad: return "Play with me?"
        case .happy: return "Yay!"
        case .content: return "Hi there!"
        }
    }
}

/// Pet face that bobs gently; the timeline ticks slowly so an idle island stays cheap.
struct PetGlyph: View {
    @ObservedObject var store: PetStore
    let size: CGFloat
    private let period = 1.2

    var body: some View {
        TimelineView(.periodic(from: .now, by: period)) { context in
            let pet = store.current(at: context.date)
            let phase = Int(context.date.timeIntervalSinceReferenceDate / period) % 2
            Text(pet.species.emoji)
                .font(.system(size: size))
                .opacity(pet.isSleeping ? 0.55 : 1)
                .offset(y: pet.isSleeping ? 0 : (phase == 0 ? 0 : -size * 0.08))
                .scaleEffect(y: pet.isSleeping && phase == 1 ? 0.95 : 1, anchor: .bottom)
                .animation(.easeInOut(duration: period), value: phase)
        }
    }
}

struct PetMoodBadge: View {
    @ObservedObject var store: PetStore

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(store.current(at: context.date).mood.emoji).font(.system(size: 13))
        }
    }
}

private struct FloatingEmoji: View {
    let text: String
    @State private var up = false

    var body: some View {
        Text(text)
            .font(.system(size: 22))
            .offset(y: up ? -46 : -6)
            .opacity(up ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1)) { up = true } }
    }
}

struct PetPanel: View {
    @ObservedObject var store: PetStore
    @State private var name = ""
    @State private var bounce = 0
    @State private var burst: Burst?

    private struct Burst: Equatable {
        let id = UUID()
        let emoji: String
        let message: String
    }

    var body: some View {
        Card {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let pet = store.current(at: context.date)
                HStack(spacing: 18) {
                    VStack(spacing: 4) {
                        ZStack {
                            PetGlyph(store: store, size: 60)
                                .keyframeAnimator(initialValue: CGFloat(1), trigger: bounce) { content, scale in
                                    content.scaleEffect(scale)
                                } keyframes: { _ in
                                    KeyframeTrack(\.self) {
                                        SpringKeyframe(1.25, duration: 0.12)
                                        SpringKeyframe(1, duration: 0.4, spring: .bouncy)
                                    }
                                }
                            if let burst, !burst.emoji.isEmpty { FloatingEmoji(text: burst.emoji).id(burst.id) }
                        }
                        .frame(width: 110, height: 76)
                        Text(burst?.message ?? statusLine(pet))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(height: 14)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            TextField("Name", text: $name)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: 110)
                                .onSubmit { store.rename(name); name = store.pet.name }
                            Text("Lv \(pet.level)")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                            Spacer(minLength: 0)
                            Menu {
                                ForEach(Pet.Species.allCases, id: \.self) { species in
                                    Button("\(species.emoji) \(species.rawValue.capitalized)") { store.setSpecies(species) }
                                }
                            } label: {
                                Text(pet.species.emoji)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Change pet")
                        }
                        statBar("Food", pet.fullness, .orange)
                        statBar("Happy", pet.happiness, .pink)
                        statBar("Energy", pet.energy, .cyan)
                        HStack(spacing: 8) {
                            action("Feed", "fork.knife", .orange) {
                                react(store.feed(), "🍖", "Yum!", refused: store.pet.isSleeping ? "Shh, sleeping" : "Not hungry")
                            }
                            action("Play", "tennisball.fill", .pink) {
                                react(store.play(), "❤️", "Wheee!", refused: store.pet.isSleeping ? "Shh, sleeping" : "Too tired")
                            }
                            action(pet.isSleeping ? "Wake" : "Sleep", pet.isSleeping ? "sun.max.fill" : "moon.zzz.fill", .cyan) {
                                store.toggleSleep()
                                react(true, store.pet.isSleeping ? "💤" : "☀️", store.pet.isSleeping ? "Zzz…" : "Morning!")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { name = store.pet.name }
    }

    private func statusLine(_ pet: Pet) -> String {
        guard let remaining = pet.sleepRemaining else { return pet.mood.line }
        let minutes = max(Int((remaining / 60).rounded(.up)), 1)
        return minutes < 60 ? "Zzz… wakes in \(minutes)m" : "Zzz… wakes in \(minutes / 60)h \(minutes % 60)m"
    }

    private func react(_ ok: Bool, _ emoji: String, _ message: String, refused: String = "") {
        let next = Burst(emoji: ok ? emoji : "", message: ok ? message : refused)
        burst = next
        if ok { bounce += 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if burst == next { burst = nil } }
    }

    private func statBar(_ title: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.18))
                    Capsule().fill(color).frame(width: max(geo.size.width * value, 4))
                        .animation(.easeOut(duration: 0.3), value: value)
                }
            }
            .frame(height: 6)
        }
    }

    private func action(_ title: String, _ symbol: String, _ tint: Color, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(Capsule().fill(tint.opacity(0.18)))
                .foregroundStyle(tint)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}
