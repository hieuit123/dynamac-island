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

/// Small equalizer for the collapsed island. ~15 fps while playing, frozen when paused or in Low Power Mode.
struct MusicWaveform: View {
    let palette: [Color]
    let animate: Bool

    var body: some View {
        let paused = !animate || ProcessInfo.processInfo.isLowPowerModeEnabled
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let bars = 5
                let gap: CGFloat = 2
                let width = (size.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
                for i in 0..<bars {
                    let d = Double(i)
                    let level = paused ? [0.35, 0.6, 0.85, 0.55, 0.3][i]
                        : 0.25 + 0.75 * abs(sin(t * (3.1 + d * 0.9) + d * 1.7) * 0.6 + sin(t * (5.3 - d * 0.7) + d) * 0.4)
                    let h = max(size.height * level, width)
                    let rect = CGRect(x: CGFloat(i) * (width + gap), y: (size.height - h) / 2, width: width, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: width / 2),
                             with: .linearGradient(Gradient(colors: palette), startPoint: CGPoint(x: 0, y: size.height),
                                                   endPoint: CGPoint(x: size.width, y: 0)))
                }
            }
        }
        .frame(width: 22, height: 14)
    }
}

struct NowPlayingCard: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var vm: IslandViewModel
    let gradientProgress: Bool

    var body: some View {
        let palette = nowPlaying.palette
        HStack(spacing: 14) {
            AlbumArtwork(image: nowPlaying.artwork, palette: palette, isPlaying: nowPlaying.isPlaying, size: 104,
                         trackID: nowPlaying.track.map { $0.title + $0.artist } ?? "")
                .offset(x: vm.swipeOffset)
                .opacity(1 - Double(min(abs(vm.swipeOffset) / 120, 0.5)))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowPlaying.track?.title ?? "Nothing playing")
                            .font(.system(size: 14, weight: .bold)).lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if nowPlaying.canFavorite {
                        iconButton(nowPlaying.isFavorite ? "star.fill" : "star", size: 13,
                                   tint: nowPlaying.isFavorite ? palette[0] : .white.opacity(0.6)) { nowPlaying.toggleFavorite() }
                            .symbolEffect(.bounce, value: nowPlaying.isFavorite)
                    }
                }

                ProgressScrubber(nowPlaying: nowPlaying, palette: palette, gradient: gradientProgress)
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
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(LinearGradient(colors: [palette[0].opacity(0.45), .clear, palette[2].opacity(0.3)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
        .animation(.easeInOut(duration: 0.6), value: palette)
    }

    private var subtitle: String {
        guard let track = nowPlaying.track else { return "Play something in Music or Spotify" }
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
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
