import SwiftUI

/// Samples the outline once per size/radius change so the per-frame drawing never walks the path.
private final class OutlineSampler {
    private var key = ""
    private var points: [CGPoint] = []

    func samples(for outline: NotchShape, size: CGSize) -> [CGPoint] {
        let k = "\(Int(size.width / 4))x\(Int(size.height / 4))-\(Int(outline.topRadius))-\(Int(outline.bottomRadius))-\(outline.pill)"
        if k != key {
            key = k
            let path = outline.path(in: CGRect(origin: .zero, size: size))
            let count = 240
            points = (0..<count).compactMap { i in
                path.trimmedPath(from: 0, to: max(Double(i) / Double(count - 1), 0.0005)).currentPoint
            }
        }
        return points
    }
}

private typealias Frame = (p: CGPoint, d: CGPoint, out: CGPoint)

/// Point at `along` (direction of travel) and `up` (away from the island) from the frame origin.
private func place(_ f: Frame, _ along: CGFloat, _ up: CGFloat) -> CGPoint {
    CGPoint(x: f.p.x + f.d.x * along + f.out.x * up, y: f.p.y + f.d.y * along + f.out.y * up)
}

/// A golden dragon that runs along the island outline: it enters at one top corner, leaves at the other, then repeats.
/// Its back faces away from the island, its belly and legs face the island.
struct DragonCanvas: View {
    let outline: NotchShape
    let layer: BlackHoleEffect.Layer
    let t: Double
    let intensity: Double

    @State private var sampler = OutlineSampler()

    private static let gold = Color(red: 1, green: 0.8, blue: 0.25)
    private static let deepGold = Color(red: 0.96, green: 0.68, blue: 0.14)
    private static let amber = Color(red: 0.72, green: 0.4, blue: 0.05)
    private static let pale = Color(red: 1, green: 0.95, blue: 0.7)
    /// Canvas drawing may be clipped to its bounds, so leave room for horns, fins and whiskers outside the outline.
    private static let pad: CGFloat = 50
    private static let bodyLength = 0.42
    private static let segments = 90

    var body: some View {
        Canvas { ctx, canvasSize in
            let pad = Self.pad
            let size = CGSize(width: canvasSize.width - 2 * pad, height: canvasSize.height - 2 * pad)
            guard size.width > 20, size.height > 10 else { return }
            ctx.translateBy(x: pad, y: pad)
            let pts = sampler.samples(for: outline, size: size)
            guard pts.count > 8 else { return }
            let n = pts.count
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let head = (t * 0.14).truncatingRemainder(dividingBy: 1 + Self.bodyLength)

            func frame(_ f: Double) -> Frame {
                let x = min(max(f, 0), 1) * Double(n - 1)
                let i = Int(x), j = min(i + 1, n - 1), w = CGFloat(x - Double(i))
                let p = CGPoint(x: pts[i].x + (pts[j].x - pts[i].x) * w, y: pts[i].y + (pts[j].y - pts[i].y) * w)
                let a = pts[max(i - 2, 0)], b = pts[min(i + 3, n - 1)]
                var dx = b.x - a.x, dy = b.y - a.y
                let len = max(hypot(dx, dy), 0.001)
                dx /= len; dy /= len
                var nx = -dy, ny = dx
                if nx * (p.x - center.x) + ny * (p.y - center.y) < 0 { nx = -nx; ny = -ny }
                return (p, CGPoint(x: dx, y: dy), CGPoint(x: nx, y: ny))
            }

            switch layer {
            case .glow: drawGlow(&ctx, head: head, frame: frame)
            case .border: drawDragon(&ctx, size: size, head: head, frame: frame)
            }
        }
        .padding(-Self.pad)
    }

    // MARK: Glow

    private func drawGlow(_ ctx: inout GraphicsContext, head: Double, frame: (Double) -> Frame) {
        var path = Path()
        var started = false
        for k in 0...Self.segments {
            let f = head - Self.bodyLength * Double(k) / Double(Self.segments)
            guard f >= 0, f <= 1 else { continue }
            let p = frame(f).p
            if started { path.addLine(to: p) } else { path.move(to: p); started = true }
        }
        var glow = ctx
        glow.addFilter(.blur(radius: 9))
        glow.stroke(path, with: .color(Self.gold.opacity(0.5)),
                    style: StrokeStyle(lineWidth: 12 * min(intensity, 1.3), lineCap: .round, lineJoin: .round))
        if head > 0.01, head <= 1 {
            let h = frame(head).p
            glow.fill(Path(ellipseIn: CGRect(x: h.x - 18, y: h.y - 18, width: 36, height: 36)),
                      with: .color(Color.orange.opacity(0.45)))
        }
    }

    // MARK: Body

    private func drawDragon(_ ctx: inout GraphicsContext, size: CGSize, head: Double, frame: (Double) -> Frame) {
        ctx.stroke(outline.path(in: CGRect(origin: .zero, size: size)), with: .color(Self.gold.opacity(0.18)), lineWidth: 1)

        let m = Self.segments
        let tailF = head - Self.bodyLength
        if tailF >= 0, tailF <= 1 { drawTailTuft(&ctx, fr: frame(tailF)) }

        for k in stride(from: m - 1, through: 0, by: -1) {
            let f = head - Self.bodyLength * Double(k) / Double(m)
            guard f >= 0, f <= 1 else { continue }
            let fr = frame(f)
            let taper = 1 - Double(k) / Double(m)
            let r = CGFloat(1.6 + 5.0 * pow(taper, 0.7))
            let wave = CGFloat(sin(f * 38 - t * 4) * 4.5 * min(taper * 2, 1))
            let c = place(fr, 0, wave)

            if k % 2 == 0, k >= 2 {
                let h = CGFloat(4 + 8 * taper)
                var fin = Path()
                fin.move(to: place(fr, 2.4, wave + r * 0.7))
                fin.addQuadCurve(to: place(fr, -8, wave + r + h), control: place(fr, 1, wave + r + h * 0.85))
                fin.addQuadCurve(to: place(fr, -2.4, wave + r * 0.7), control: place(fr, -3, wave + r + h * 0.3))
                fin.closeSubpath()
                ctx.fill(fin, with: .color(k % 4 == 0 ? Self.pale : Self.gold))
                ctx.stroke(fin, with: .color(Self.amber.opacity(0.7)), lineWidth: 0.5)
            }
            if k == 24 || k == 62 { drawLeg(&ctx, fr: fr, at: c, scale: CGFloat(0.65 + 0.5 * taper), phase: Double(k)) }

            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(k.isMultiple(of: 2) ? Self.gold : Self.deepGold))
            let belly = place(fr, 0, wave - r * 0.45)
            ctx.fill(Path(ellipseIn: CGRect(x: belly.x - r * 0.5, y: belly.y - r * 0.5, width: r, height: r)),
                     with: .color(Self.pale.opacity(0.6)))
            let back = place(fr, 0, wave + r * 0.55)
            ctx.fill(Path(ellipseIn: CGRect(x: back.x - r * 0.4, y: back.y - r * 0.4, width: r * 0.8, height: r * 0.8)),
                     with: .color(Self.amber.opacity(0.45)))
            if k % 3 == 0 {
                var scale = Path()
                scale.move(to: place(fr, 1.2, wave + r * 0.9))
                scale.addQuadCurve(to: place(fr, 1.2, wave - r * 0.9), control: place(fr, -2.4, wave))
                ctx.stroke(scale, with: .color(Self.amber.opacity(0.6)), lineWidth: 0.7)
            }
        }

        if head > 0.01, head <= 1 {
            let fr = frame(head)
            var hc = ctx
            hc.translateBy(x: fr.p.x, y: fr.p.y)
            hc.rotate(by: .radians(atan2(fr.d.y, fr.d.x)))
            // Local -y must point away from the island.
            if fr.out.x * -fr.d.y + fr.out.y * fr.d.x > 0 { hc.scaleBy(x: 1, y: -1) }
            hc.scaleBy(x: 1.25, y: 1.25)
            drawHead(&hc)
        }
    }

    private func drawTailTuft(_ ctx: inout GraphicsContext, fr: Frame) {
        for i in 0..<6 {
            let spread = CGFloat(i - 3) * 2.6
            let sway = CGFloat(sin(t * 5 + Double(i))) * 2.5
            var strand = Path()
            strand.move(to: fr.p)
            strand.addQuadCurve(to: place(fr, -(15 + CGFloat(i % 3) * 3), spread * 1.5 + sway),
                                control: place(fr, -7, spread * 0.5 + sway * 0.4))
            ctx.stroke(strand, with: .color(i.isMultiple(of: 2) ? Self.gold : Self.pale),
                       style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }
    }

    /// Five-clawed leg reaching toward the island, claws tipped with pearls.
    private func drawLeg(_ ctx: inout GraphicsContext, fr: Frame, at c: CGPoint, scale s: CGFloat, phase: Double) {
        let swing = CGFloat(sin(t * 7 + phase)) * 2
        let knee = place(fr, -3 * s + swing * 0.5, -5 * s)
        let foot = place(fr, 2 * s + swing, -11 * s)
        var leg = Path()
        leg.move(to: c)
        leg.addQuadCurve(to: foot, control: knee)
        ctx.stroke(leg, with: .color(Self.amber), style: StrokeStyle(lineWidth: 3.6 * s, lineCap: .round))
        ctx.stroke(leg, with: .color(Self.gold), style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round))
        for i in 0..<5 {
            let spread = CGFloat(i - 2) * 2.4 * s
            let tip = place(fr, 2 * s + swing + spread * 1.2, -11 * s - 5 * s + abs(spread) * 0.35)
            var claw = Path()
            claw.move(to: foot)
            claw.addLine(to: tip)
            ctx.stroke(claw, with: .color(Self.gold), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 1.1 * s, y: tip.y - 1.1 * s, width: 2.2 * s, height: 2.2 * s)),
                     with: .color(Self.pale))
        }
    }

    // MARK: Head

    /// Side-view head. Local space: +x is the direction of travel, -y points away from the island.
    private func drawHead(_ ctx: inout GraphicsContext) {
        let sway = CGFloat(sin(t * 4))

        var glow = ctx
        glow.addFilter(.blur(radius: 6))
        glow.fill(Path(ellipseIn: CGRect(x: -12, y: -14, width: 36, height: 28)), with: .color(Color.orange.opacity(0.5)))

        for i in 0..<7 {
            let bx = CGFloat(-7 + i) * 1.1, by = -5 - CGFloat(i) * 0.5
            let wob = CGFloat(sin(t * 5 + Double(i))) * 2.5
            let tip = CGPoint(x: bx - 15 - CGFloat(i) * 1.6, y: by - 3 + wob)
            let ctl = CGPoint(x: bx - 7, y: by - 8 + wob * 0.5)
            var mane = Path()
            mane.move(to: CGPoint(x: bx, y: by))
            mane.addQuadCurve(to: tip, control: ctl)
            mane.addQuadCurve(to: CGPoint(x: bx + 1, y: by + 3.4), control: CGPoint(x: ctl.x + 2, y: ctl.y + 4.5))
            mane.closeSubpath()
            ctx.fill(mane, with: .color(i.isMultiple(of: 2) ? Self.pale : Self.gold))
            ctx.stroke(mane, with: .color(Self.amber.opacity(0.6)), lineWidth: 0.4)
        }

        var horn = Path()
        horn.move(to: CGPoint(x: -1, y: -6))
        horn.addQuadCurve(to: CGPoint(x: -19, y: -19), control: CGPoint(x: -8, y: -19))
        horn.addQuadCurve(to: CGPoint(x: -5, y: -4.5), control: CGPoint(x: -12, y: -11))
        horn.closeSubpath()
        var branch = Path()
        branch.move(to: CGPoint(x: -9.5, y: -11.5))
        branch.addQuadCurve(to: CGPoint(x: -8, y: -22), control: CGPoint(x: -13, y: -17))
        branch.addQuadCurve(to: CGPoint(x: -6, y: -10), control: CGPoint(x: -7, y: -16))
        branch.closeSubpath()
        for p in [horn, branch] {
            ctx.fill(p, with: .color(Self.pale))
            ctx.stroke(p, with: .color(Self.amber), lineWidth: 0.6)
        }

        for i in 0..<3 {
            var beard = Path()
            beard.move(to: CGPoint(x: 15, y: 6.5))
            beard.addQuadCurve(to: CGPoint(x: 3 - CGFloat(i) * 3, y: 15 + CGFloat(i) * 2 + sway * 2), control: CGPoint(x: 12, y: 13))
            ctx.stroke(beard, with: .color(i == 1 ? Self.pale : Self.gold), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
        for i in 0..<2 {
            let side = CGFloat(i) * 5
            var whisker = Path()
            whisker.move(to: CGPoint(x: 22, y: -2.5))
            whisker.addQuadCurve(to: CGPoint(x: 44, y: -10 - side + sway * 4), control: CGPoint(x: 32, y: -1 - side * 0.4 + sway * 3))
            ctx.stroke(whisker, with: .color(Self.gold), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }

        var mouth = Path()
        mouth.addLines([CGPoint(x: 3, y: 1.5), CGPoint(x: 24, y: -0.6), CGPoint(x: 22, y: 5.8), CGPoint(x: 3, y: 4)])
        mouth.closeSubpath()
        ctx.fill(mouth, with: .color(Color(red: 0.45, green: 0.08, blue: 0.05)))

        var jaw = Path()
        jaw.move(to: CGPoint(x: 3, y: 2))
        jaw.addQuadCurve(to: CGPoint(x: 23, y: 5.5), control: CGPoint(x: 12, y: 3.8))
        jaw.addLine(to: CGPoint(x: 21.5, y: 7.4))
        jaw.addQuadCurve(to: CGPoint(x: -3, y: 6.5), control: CGPoint(x: 11, y: 9))
        jaw.closeSubpath()
        ctx.fill(jaw, with: .color(Self.deepGold))
        ctx.stroke(jaw, with: .color(Self.amber), lineWidth: 0.6)

        var upper = Path()
        upper.move(to: CGPoint(x: -9, y: -1))
        upper.addQuadCurve(to: CGPoint(x: 3, y: -7.5), control: CGPoint(x: -6, y: -8))
        upper.addQuadCurve(to: CGPoint(x: 14, y: -5.5), control: CGPoint(x: 8, y: -8.5))
        upper.addQuadCurve(to: CGPoint(x: 24, y: -3.2), control: CGPoint(x: 19, y: -7.5))
        upper.addLine(to: CGPoint(x: 24.5, y: -0.6))
        upper.addQuadCurve(to: CGPoint(x: 12, y: 1), control: CGPoint(x: 18, y: -1.5))
        upper.addLine(to: CGPoint(x: 3, y: 1.8))
        upper.addLine(to: CGPoint(x: -9, y: 3))
        upper.closeSubpath()
        ctx.fill(upper, with: .linearGradient(Gradient(colors: [Self.pale, Self.gold, Self.deepGold]),
                                              startPoint: CGPoint(x: 0, y: -8), endPoint: CGPoint(x: 0, y: 3)))
        ctx.stroke(upper, with: .color(Self.amber), style: StrokeStyle(lineWidth: 0.7, lineJoin: .round))

        for x in [13.0, 17.5, 21.5] {
            var tooth = Path()
            tooth.addLines([CGPoint(x: x, y: 0.4), CGPoint(x: x + 2, y: 0), CGPoint(x: x + 1.2, y: 3.2)])
            tooth.closeSubpath()
            ctx.fill(tooth, with: .color(.white))
            var low = Path()
            low.addLines([CGPoint(x: x + 1, y: 5.3), CGPoint(x: x + 3, y: 5.1), CGPoint(x: x + 2.2, y: 2.6)])
            low.closeSubpath()
            ctx.fill(low, with: .color(.white))
        }

        ctx.fill(Path(ellipseIn: CGRect(x: 3.6, y: -5.2, width: 5.2, height: 4)), with: .color(.white))
        ctx.fill(Path(ellipseIn: CGRect(x: 5, y: -4.8, width: 3.2, height: 3.2)), with: .color(.red))
        ctx.fill(Path(ellipseIn: CGRect(x: 5.9, y: -4.2, width: 1.5, height: 2)), with: .color(.black))
        var brow = Path()
        brow.move(to: CGPoint(x: 1.5, y: -6.2))
        brow.addLine(to: CGPoint(x: 10.5, y: -4.1))
        ctx.stroke(brow, with: .color(Self.amber), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: 20.5, y: -3.6, width: 2, height: 1.4)), with: .color(Color.black.opacity(0.75)))

        let pearl = CGPoint(x: 38, y: 3 + sway * 2)
        var pearlGlow = ctx
        pearlGlow.addFilter(.blur(radius: 4))
        pearlGlow.fill(Path(ellipseIn: CGRect(x: pearl.x - 7, y: pearl.y - 7, width: 14, height: 14)), with: .color(Color.yellow.opacity(0.8)))
        ctx.fill(Path(ellipseIn: CGRect(x: pearl.x - 2.8, y: pearl.y - 2.8, width: 5.6, height: 5.6)), with: .color(Self.pale))
    }
}
