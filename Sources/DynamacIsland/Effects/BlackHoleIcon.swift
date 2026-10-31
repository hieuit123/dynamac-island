import SwiftUI

/// Procedural black hole (dark shadow, swirling orange accretion flow, thin photon ring that is
/// brighter on the lower side). Static unless `spinning`, so it costs nothing at rest.
struct BlackHoleIcon: View {
    var size: CGFloat = 72
    var spinning = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let ember = Color(red: 0.55, green: 0.05, blue: 0.0)
    private static let flame = Color(red: 1.0, green: 0.42, blue: 0.05)
    private static let gold = Color(red: 1.0, green: 0.78, blue: 0.35)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !spinning || reduceMotion)) { context in
            let t = spinning ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600) : 0
            ZStack {
                // Diffuse red halo.
                Circle()
                    .fill(RadialGradient(colors: [Self.flame.opacity(0.5), Self.ember.opacity(0.45), .clear],
                                         center: .center, startRadius: size * 0.16, endRadius: size * 0.5))

                // Swirling accretion flow: offset arcs drifting around the hole.
                ForEach(0..<7, id: \.self) { k in
                    let kd = Double(k)
                    Circle()
                        .trim(from: 0, to: 0.42 + 0.05 * (kd.truncatingRemainder(dividingBy: 3)))
                        .stroke(AngularGradient(colors: [.clear, Self.ember, Self.flame, Self.gold.opacity(0.8), .clear],
                                                center: .center),
                                style: StrokeStyle(lineWidth: size * (0.035 + 0.01 * (kd.truncatingRemainder(dividingBy: 2))), lineCap: .round))
                        .frame(width: size * (0.5 + 0.055 * kd), height: size * (0.5 + 0.055 * kd))
                        .rotationEffect(.degrees(kd * 52 + t * (70 - kd * 6)))
                        .blur(radius: size * 0.012 * (1 + kd * 0.4))
                        .opacity(1 - kd * 0.1)
                }

                // Bright emission ring – Doppler-boosted on the lower side.
                Circle()
                    .stroke(AngularGradient(stops: [
                        .init(color: Self.flame, location: 0), .init(color: Self.gold, location: 0.22),
                        .init(color: Self.flame, location: 0.45), .init(color: Self.ember, location: 0.72),
                        .init(color: Self.flame, location: 1),
                    ], center: .center, angle: .degrees(20)), lineWidth: size * 0.11)
                    .frame(width: size * 0.42, height: size * 0.42)
                    .blur(radius: size * 0.02)

                // Thin photon ring.
                Circle()
                    .stroke(Self.gold.opacity(0.9), lineWidth: max(0.8, size * 0.012))
                    .frame(width: size * 0.47, height: size * 0.47)
                    .blur(radius: 0.3)

                // Event-horizon shadow.
                Circle()
                    .fill(RadialGradient(colors: [.black, .black, Color(red: 0.12, green: 0, blue: 0)],
                                         center: .center, startRadius: 0, endRadius: size * 0.14))
                    .frame(width: size * 0.27, height: size * 0.27)
                    .offset(x: size * 0.008, y: -size * 0.006)
            }
            .frame(width: size, height: size)
            .compositingGroup()
        }
    }
}
