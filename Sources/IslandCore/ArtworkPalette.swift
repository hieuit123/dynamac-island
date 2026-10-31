import CoreGraphics
import Foundation

public struct RGB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    var hsb: (h: Double, s: Double, v: Double) {
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { h = (b - r) / delta + 2 }
            else { h = (r - g) / delta + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, maxC == 0 ? 0 : delta / maxC, maxC)
    }

    init(h: Double, s: Double, v: Double) {
        let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: self.init(r: v, g: t, b: p)
        case 1: self.init(r: q, g: v, b: p)
        case 2: self.init(r: p, g: v, b: t)
        case 3: self.init(r: p, g: q, b: v)
        case 4: self.init(r: t, g: p, b: v)
        default: self.init(r: v, g: p, b: q)
        }
    }
}

/// Extracts vivid accent colors from album artwork (tiny downsample, runs in well under 1 ms).
public enum ArtworkPalette {
    public static let fallback = [RGB(r: 0.98, g: 0.36, b: 0.62), RGB(r: 0.62, g: 0.4, b: 1), RGB(r: 0.35, g: 0.78, b: 1)]

    public static func extract(from image: CGImage, count: Int = 3) -> [RGB] {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return fallback }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        let binCount = 18
        var weight = [Double](repeating: 0, count: binCount)
        var sums = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: binCount)
        var gray = RGB(r: 0, g: 0, b: 0), grayCount = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let c = RGB(r: Double(pixels[i]) / 255, g: Double(pixels[i + 1]) / 255, b: Double(pixels[i + 2]) / 255)
            let (h, s, v) = c.hsb
            gray.r += c.r; gray.g += c.g; gray.b += c.b; grayCount += 1
            guard v > 0.18, s > 0.2 else { continue }
            let w = s * v * v
            let bin = min(Int(h * Double(binCount)), binCount - 1)
            weight[bin] += w
            sums[bin].r += c.r * w; sums[bin].g += c.g * w; sums[bin].b += c.b * w
        }

        let total = weight.reduce(0, +)
        var picked: [Int] = []
        for bin in weight.indices.sorted(by: { weight[$0] > weight[$1] }) {
            guard weight[bin] > total * 0.04, picked.count < count else { break }
            let far = picked.allSatisfy { other in
                let d = abs(bin - other)
                return min(d, binCount - d) >= 2
            }
            if far { picked.append(bin) }
        }

        var colors = picked.map { bin -> RGB in
            let w = weight[bin]
            return vivid(RGB(r: sums[bin].r / w, g: sums[bin].g / w, b: sums[bin].b / w))
        }
        if colors.isEmpty {
            guard grayCount > 0 else { return fallback }
            let avg = RGB(r: gray.r / grayCount, g: gray.g / grayCount, b: gray.b / grayCount)
            let (h, s, _) = avg.hsb
            colors = [RGB(h: h, s: min(s, 0.15), v: 0.9)]
        }
        // Fill the palette with hue-shifted siblings so gradients always have depth.
        var shift = 0.07
        while colors.count < count {
            let (h, s, v) = colors[0].hsb
            colors.append(RGB(h: (h + shift + 1).truncatingRemainder(dividingBy: 1), s: s, v: v))
            shift = -shift * 1.6
        }
        return colors
    }

    /// Keeps colors readable on a black island.
    static func vivid(_ c: RGB) -> RGB {
        let (h, s, v) = c.hsb
        return RGB(h: h, s: min(max(s, 0.45), 0.9), v: max(v, 0.8))
    }
}
