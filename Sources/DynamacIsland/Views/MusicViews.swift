import IslandCore
import SwiftUI

/// Album art with an ambient color glow, a glare sweep (on appear, track change, resume and hover),
/// and a dim/shrink treatment while paused.
struct AlbumArtwork: View {
    let image: NSImage?
    let palette: [Color]
    let isPlaying: Bool
    let size: CGFloat
    var cornerRadius: CGFloat = 14
    var trackID: String = ""

    @State private var glare: CGFloat = -1.2

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").font(.system(size: size * 0.32, weight: .semibold)))
            }
            LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .white.opacity(0.55), location: 0.5),
                                   .init(color: .clear, location: 0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .offset(x: glare * size, y: glare * size)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .contentShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .saturation(isPlaying ? 1 : 0.35)
        .opacity(isPlaying ? 1 : 0.6)
        .scaleEffect(isPlaying ? 1 : 0.88)
        .shadow(color: (palette.first ?? .clear).opacity(isPlaying ? 0.55 : 0.15), radius: isPlaying ? size * 0.18 : 4, y: size * 0.04)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: isPlaying)
        .onAppear(perform: sweep)
        .onChange(of: trackID) { sweep() }
        .onChange(of: isPlaying) { if isPlaying { sweep() } }
        .onHover { if $0 { sweep() } }
    }

    private func sweep() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { glare = -1.2 }
        withAnimation(.easeInOut(duration: 1.1).delay(0.05)) { glare = 1.2 }
    }
}

/// Scrubbable progress bar. Extrapolates time locally (2 Hz) only while visible and playing.
struct ProgressScrubber: View {
    @ObservedObject var nowPlaying: NowPlayingService
    let palette: [Color]
    let gradient: Bool

    @State private var scrub: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !nowPlaying.isPlaying || scrub != nil)) { context in
            let duration = max(nowPlaying.duration, 1)
            let elapsed = scrub ?? nowPlaying.elapsed(at: context.date)
            VStack(spacing: 3) {
                GeometryReader { geo in
                    let fraction = CGFloat(min(max(elapsed / duration, 0), 1))
                    let active = hovering || scrub != nil
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(gradient ? AnyShapeStyle(LinearGradient(colors: palette, startPoint: .leading, endPoint: .trailing))
                                           : AnyShapeStyle(palette.first ?? .white))
                            .frame(width: max(geo.size.width * fraction, active ? 6 : 4))
                            .shadow(color: (palette.last ?? .clear).opacity(0.6), radius: active ? 6 : 3)
                    }
                    .frame(height: active ? 7 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrub = Double(min(max(value.location.x / geo.size.width, 0), 1)) * duration
                        }
                        .onEnded { _ in
                            if let scrub { nowPlaying.seek(to: scrub) }
                            scrub = nil
                        })
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: active)
                }
                .frame(height: 12)
                .onHover { hovering = $0 }

                HStack {
                    Text(Self.format(elapsed))
                    Spacer()
                    Text("-" + Self.format(max(duration - elapsed, 0)))
                }
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Small equalizer for the collapsed island. Animated with Core Animation keyframes, which run in the
/// render server (capped at ~24 fps), so the app process stays near 0% CPU while music plays.
struct MusicWaveform: NSViewRepresentable {
    let palette: [Color]
    let animate: Bool

    func makeNSView(context: Context) -> WaveformView { WaveformView() }

    func updateNSView(_ view: WaveformView, context: Context) {
        view.update(colors: palette.map { NSColor($0) },
                    animate: animate && !ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WaveformView, context: Context) -> CGSize? {
        CGSize(width: 22, height: 14)
    }
}

final class WaveformView: NSView {
    private let barCount = 5
    private let restLevels: [CGFloat] = [0.35, 0.6, 0.85, 0.55, 0.3]
    private var bars: [CALayer] = []
    private var isAnimating = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for i in 0..<barCount {
            let bar = CALayer()
            bar.transform = CATransform3DMakeScale(1, restLevels[i], 1)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let gap: CGFloat = 2
        let width = (bounds.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(i) * (width + gap) + width / 2, y: bounds.midY)
            bar.cornerRadius = width / 2
        }
        CATransaction.commit()
    }

    func update(colors: [NSColor], animate: Bool) {
        let srgb = colors.compactMap { $0.usingColorSpace(.sRGB) }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.6)
        for (i, bar) in bars.enumerated() {
            bar.backgroundColor = Self.color(at: CGFloat(i) / CGFloat(barCount - 1), in: srgb).cgColor
        }
        CATransaction.commit()

        guard animate != isAnimating else { return }
        isAnimating = animate
        for (i, bar) in bars.enumerated() {
            if animate {
                let anim = CAKeyframeAnimation(keyPath: "transform.scale.y")
                var values = (0..<8).map { _ in CGFloat.random(in: 0.22...1) }
                values.append(values[0])
                anim.values = values
                anim.duration = 0.85 + Double(i) * 0.17
                anim.calculationMode = .cubic
                anim.repeatCount = .infinity
                anim.isRemovedOnCompletion = false
                anim.preferredFrameRateRange = CAFrameRateRange(minimum: 12, maximum: 24, preferred: 24)
                bar.add(anim, forKey: "wave")
            } else {
                bar.removeAnimation(forKey: "wave")
                bar.transform = CATransform3DMakeScale(1, restLevels[i], 1)
            }
        }
    }

    private static func color(at t: CGFloat, in colors: [NSColor]) -> NSColor {
        guard colors.count > 1 else { return colors.first ?? .white }
        let scaled = t * CGFloat(colors.count - 1)
        let index = min(Int(scaled), colors.count - 2)
        return colors[index].blended(withFraction: scaled - CGFloat(index), of: colors[index + 1]) ?? colors[index]
    }
}

struct NowPlayingCard: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var vm: IslandViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        let palette = nowPlaying.palette
        HStack(spacing: 14) {
            AlbumArtwork(image: nowPlaying.artwork, palette: palette, isPlaying: nowPlaying.isPlaying, size: 104,
                         trackID: nowPlaying.track.map { $0.title + $0.artist } ?? "")
                .overlay(alignment: .bottomTrailing) {
                    // Which app is playing (useful now that every media source is supported).
                    if let icon = nowPlaying.appIcon, nowPlaying.track != nil {
                        Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                            .shadow(color: .black.opacity(0.5), radius: 3)
                            .offset(x: 7, y: 7)
                    }
                }
                .offset(x: vm.swipeOffset)
                .opacity(1 - Double(min(abs(vm.swipeOffset) / 120, 0.5)))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(text: nowPlaying.track?.title ?? "Nothing playing",
                                    font: .system(size: 14, weight: .bold), enabled: settings.marqueeTitles)
                        MarqueeText(text: subtitle, font: .system(size: 11.5, weight: .medium), enabled: settings.marqueeTitles)
                            .foregroundStyle(.white.opacity(0.6))
                        if settings.showAudioBadges, let badge = nowPlaying.audioBadge {
                            Text(badge.uppercased())
                                .font(.system(size: 8.5, weight: .heavy))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.5), lineWidth: 0.8))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                    if nowPlaying.supportsSpeed {
                        Button { nowPlaying.cycleSpeed() } label: {
                            Text("\(Int(nowPlaying.playbackRate))×")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6).frame(height: 20)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(PressableStyle())
                        .help("Playback speed")
                    }
                    if nowPlaying.track != nil {
                        iconButton("link", size: 12, tint: .white.opacity(0.6)) { nowPlaying.copyLink() }
                            .help("Copy song link")
                    }
                    if nowPlaying.canFavorite {
                        iconButton(nowPlaying.isFavorite ? "star.fill" : "star", size: 13,
                                   tint: nowPlaying.isFavorite ? palette[0] : .white.opacity(0.6)) { nowPlaying.toggleFavorite() }
                            .symbolEffect(.bounce, value: nowPlaying.isFavorite)
                    }
                }

                ProgressScrubber(nowPlaying: nowPlaying, palette: palette, gradient: settings.gradientProgress)
                    .disabled(nowPlaying.track == nil)

                HStack(spacing: 0) {
                    iconButton("shuffle", size: 12, tint: nowPlaying.shuffle ? palette[0] : .white.opacity(0.45)) { nowPlaying.toggleShuffle() }
                    Spacer()
                    iconButton("backward.fill", size: 15) { nowPlaying.previous() }
                    Spacer()
                    Button { nowPlaying.playPause() } label: {
                        Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(LinearGradient(colors: [palette[0].opacity(0.55), palette[1].opacity(0.35)],
                                                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    Spacer()
                    iconButton("forward.fill", size: 15) { nowPlaying.next() }
                    Spacer()
                    iconButton(nowPlaying.repeatMode == .one ? "repeat.1" : "repeat", size: 12,
                               tint: nowPlaying.repeatMode == .off ? .white.opacity(0.45) : palette[0]) { nowPlaying.cycleRepeat() }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(ambient)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(LinearGradient(colors: [palette[0].opacity(0.45), .clear, palette[2].opacity(0.3)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
        .animation(.easeInOut(duration: 0.6), value: palette)
    }

    private var subtitle: String {
        guard let track = nowPlaying.track else { return "Play something in any app" }
        return [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    /// Blurred artwork + palette wash: rendered once per track, no ongoing animation cost.
    private var ambient: some View {
        ZStack {
            Color.black
            if let art = nowPlaying.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                    .blur(radius: 38, opaque: true)
                    .saturation(1.4)
                    .opacity(nowPlaying.isPlaying ? 0.55 : 0.3)
            }
            LinearGradient(colors: [nowPlaying.palette[0].opacity(0.28), .clear, nowPlaying.palette[2].opacity(0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
        // The fill-scaled artwork overflows the card; clipping is visual only, so it must not take clicks.
        .allowsHitTesting(false)
    }

    private func iconButton(_ symbol: String, size: CGFloat, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Single-line text that scrolls when it doesn't fit (like iOS). Animates only while visible and overflowing.
struct MarqueeText: View {
    let text: String
    let font: Font
    var enabled = true

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private let gap: CGFloat = 36
    private var overflows: Bool { enabled && textWidth > containerWidth + 1 && containerWidth > 0 }

    var body: some View {
        Text(text).font(font).lineLimit(1).hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { geo in Color.clear.onAppear { containerWidth = geo.size.width }
                .onChange(of: geo.size.width) { containerWidth = geo.size.width } })
            .overlay(alignment: .leading) {
                HStack(spacing: gap) {
                    label.background(GeometryReader { geo in Color.clear.onAppear { textWidth = geo.size.width }
                        .onChange(of: geo.size.width) { textWidth = geo.size.width } })
                    if overflows { label }
                }
                .offset(x: offset)
                .fixedSize()
            }
            .clipped()
            .mask(LinearGradient(stops: overflows ? [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                                    .init(color: .black, location: 0.92), .init(color: .clear, location: 1)]
                                                 : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .onChange(of: text) { restart() }
            .onChange(of: overflows) { restart() }
            .onAppear(perform: restart)
    }

    private var label: some View { Text(text).font(font).lineLimit(1).fixedSize() }

    private func restart() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { offset = 0 }
        guard overflows else { return }
        let distance = textWidth + gap
        withAnimation(.linear(duration: Double(distance) / 30).delay(1.5).repeatForever(autoreverses: false)) {
            offset = -distance
        }
    }
}
