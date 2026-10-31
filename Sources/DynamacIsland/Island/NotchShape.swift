import SwiftUI

/// Notch-like shape: flares outward at the top corners, rounded at the bottom.
/// With `closed == false` it produces only the visible outline (no top edge), used for border effects.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var closed = true

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let tr = min(topRadius, w / 4, h / 2)
        let br = min(bottomRadius, (w - 2 * tr) / 2, h - tr)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY + tr), control: CGPoint(x: rect.minX + tr, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + tr, y: rect.minY + h - br))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr + br, y: rect.minY + h), control: CGPoint(x: rect.minX + tr, y: rect.minY + h))
        p.addLine(to: CGPoint(x: rect.minX + w - tr - br, y: rect.minY + h))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w - tr, y: rect.minY + h - br), control: CGPoint(x: rect.minX + w - tr, y: rect.minY + h))
        p.addLine(to: CGPoint(x: rect.minX + w - tr, y: rect.minY + tr))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w, y: rect.minY), control: CGPoint(x: rect.minX + w - tr, y: rect.minY))
        if closed { p.closeSubpath() }
        return p
    }
}
