import SwiftUI

/// Animated "black hole" border. Only instantiated while the island is hovered / expanded / drop-targeted,
/// so the TimelineView (and GPU work) stops completely when the island is idle.
struct BlackHoleEffect: View, Animatable {
    enum Layer { case glow, border }

    let style: EffectStyle
    /// Animatable so the ring smoothly grows/fades with the island instead of popping.
    var intensity: Double
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    let layer: Layer
    /// Album colors; when set, the effect is tinted to match the playing artwork.
    var palette: [Color]? = nil

    var animatableData: Double {
        get { intensity }
        set { intensity = newValue }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var outline: NotchShape { NotchShape(topRadius: topRadius, bottomRadius: bottomRadius, closed: false) }

    var body: some View {
        let interval = ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.0 / 30 : 1.0 / 60
        TimelineView(.animation(minimumInterval: interval, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            switch style {
            case .accretion: accretion(t)
            case .eventHorizon: eventHorizon(t)
            case .vortex: vortex(t)
            }
        }
        .opacity(min(1, max(0, intensity) / 0.5))
        .allowsHitTesting(false)
    }

    // MARK: Accretion disk – hot rotating ring of light

    private func accretionGradient(_ t: Double) -> AngularGradient {
        let colors: [Color] = palette.map { p in [p[0], p[1], p[2], p[1], p[0]] }
            ?? [.orange, .pink, .purple, .indigo, .cyan, .yellow, .orange]
        return AngularGradient(colors: colors, center: .center, angle: .degrees(t * 80))
    }

    @ViewBuilder private func accretion(_ t: Double) -> some View {
        let g = accretionGradient(t)
        switch layer {
        case .glow:
            ZStack {
                outline.stroke(g, lineWidth: 12 * intensity).blur(radius: 16 * intensity).opacity(0.65)
                outline.stroke(g, lineWidth: 4 * intensity).blur(radius: 4).opacity(0.9)
            }
        case .border:
            outline.stroke(g, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }

    // MARK: Event horizon – dark lensing shadow and a shimmering photon ring

    private func photonRing(_ t: Double) -> AngularGradient {
        AngularGradient(stops: [
            .init(color: .clear, location: 0), .init(color: .white, location: 0.07), .init(color: .clear, location: 0.16),
            .init(color: .clear, location: 0.5), .init(color: palette?[0] ?? Color(red: 0.75, green: 0.85, blue: 1), location: 0.57),
            .init(color: .clear, location: 0.66), .init(color: .clear, location: 1),
        ], center: .center, angle: .degrees(t * 110))
    }

    @ViewBuilder private func eventHorizon(_ t: Double) -> some View {
        switch layer {
        case .glow:
            ZStack {
                outline.stroke(Color.black, lineWidth: 28 * intensity).blur(radius: 20 * intensity).opacity(0.9)
                outline.stroke((palette?[1] ?? .white).opacity(0.22), lineWidth: 3).blur(radius: 7)
                outline.stroke(photonRing(t), lineWidth: 3 * intensity).blur(radius: 3)
            }
            .scaleEffect(1 + 0.012 * sin(t * 2.2) * intensity, anchor: .top)
        case .border:
            ZStack {
                outline.stroke(Color.white.opacity(0.16), lineWidth: 1)
                outline.stroke(photonRing(t), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }
    }

    // MARK: Vortex – counter-rotating dashed spirals flowing into the island

    private var vortexColors: [Color] {
        let p = palette ?? [.purple, .cyan, .pink]
        return [p[0], .clear, p[1], .clear, p[2], .clear, p[0]]
    }

    @ViewBuilder private func vortex(_ t: Double) -> some View {
        switch layer {
        case .glow:
            ZStack {
                ForEach(0..<3, id: \.self) { k in
                    let kd = Double(k)
                    let dir: Double = k.isMultiple(of: 2) ? 1 : -1
                    outline
                        .stroke(AngularGradient(colors: vortexColors,
                                                center: .center, angle: .degrees(t * (60 + 40 * kd) * dir)),
                                style: StrokeStyle(lineWidth: (3 + 2 * kd) * intensity, lineCap: .round,
                                                   dash: [10 + 8 * kd, 14 + 6 * kd], dashPhase: t * 40 * (kd + 1) * dir))
                        .blur(radius: kd * 3 + 1)
                        .scaleEffect(1 + kd * 0.035 * intensity, anchor: .top)
                        .opacity(0.9 - kd * 0.22)
                }
            }
        case .border:
            outline.stroke(AngularGradient(colors: palette.map { [$0[0], $0[1], $0[2], $0[0]] } ?? [.purple, .cyan, .pink, .purple],
                                           center: .center, angle: .degrees(-t * 90)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }
}
