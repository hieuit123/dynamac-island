import IslandCore
import SwiftUI

enum CollapsedActivity: Equatable {
    case hud(HUDKind)
    case transient(TransientActivity)
    case timer
    case music

    var sideWidth: CGFloat {
        if case .hud = self { return 92 }
        return 46
    }
}

struct IslandRootView: View {
    @ObservedObject var vm: IslandViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var battery: BatteryService
    @ObservedObject var calendar: CalendarService
    @ObservedObject var shelf: ShelfStore

    private var activity: CollapsedActivity? {
        if let hud = vm.hud { return .hud(hud) }
        if let transient = vm.transient { return .transient(transient) }
        if vm.timer.isActive { return .timer }
        if settings.showMusic, nowPlaying.isPlaying, nowPlaying.track != nil { return .music }
        return nil
    }

    private var radii: (top: CGFloat, bottom: CGFloat) {
        switch vm.state {
        case .expanded: return (14, 32)
        case .peek: return (8, 14)
        case .collapsed: return (6, 10)
        }
    }

    private var islandSize: CGSize {
        if vm.state == .expanded { return IslandMetrics.expandedSize }
        var width = vm.notchSize.width + 2 * radii.top
        var height = vm.notchSize.height
        if let activity { width += 2 * activity.sideWidth }
        if vm.state == .peek { width += 28; height += 6 }
        return CGSize(width: width, height: height)
    }

    var body: some View {
        let size = islandSize
        let r = radii
        let shape = NotchShape(topRadius: r.top, bottomRadius: r.bottom)

        ZStack(alignment: .top) {
            content(size: size, flare: r.top)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .background {
            ZStack {
                if vm.isEffectMounted {
                    BlackHoleEffect(style: settings.effectStyle, intensity: vm.effectIntensity,
                                    topRadius: r.top, bottomRadius: r.bottom, layer: .glow)
                        .transition(.opacity)
                }
                shape.fill(Color.black)
            }
        }
        .overlay {
            if vm.isEffectMounted {
                BlackHoleEffect(style: settings.effectStyle, intensity: vm.effectIntensity,
                                topRadius: r.top, bottomRadius: r.bottom, layer: .border)
                    .transition(.opacity)
            }
        }
        // Invisible hit-slop so the tiny notch is easy to hover and to drop files onto.
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.001))
        .background(HoverTracker(onChange: { vm.hoverChanged($0) },
                                 onMake: { view in vm.mouseInsideProbe = { [weak view] in view?.isMouseInside ?? false } }))
        .contentShape(Rectangle())
        .onTapGesture { if vm.state != .expanded { vm.expand() } }
        .onDrop(of: [.fileURL], isTargeted: $vm.isDropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { shelf.add([url]) }
                }
            }
            vm.didDropFiles()
            return true
        }
        .animation(vm.state == .collapsed ? IslandAnimation.collapse : IslandAnimation.expand, value: vm.state)
        .animation(IslandAnimation.collapse, value: activity)
        .animation(.easeInOut(duration: 0.25), value: vm.isDropTargeted)
        .animation(IslandAnimation.collapse, value: vm.isEffectMounted)
        .preferredColorScheme(.dark)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func content(size: CGSize, flare: CGFloat) -> some View {
        if vm.state == .expanded {
            ExpandedView(vm: vm, settings: settings, nowPlaying: nowPlaying, battery: battery,
                         calendar: calendar, shelf: shelf)
                .padding(.horizontal, flare)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
        } else if let activity {
            CollapsedActivityView(activity: activity, vm: vm, nowPlaying: nowPlaying,
                                  isPeeking: vm.state == .peek)
                .frame(height: vm.notchSize.height)
                .padding(.horizontal, flare + 10)
                .transition(.opacity)
        }
    }
}

struct CollapsedActivityView: View {
    let activity: CollapsedActivity
    @ObservedObject var vm: IslandViewModel
    @ObservedObject var nowPlaying: NowPlayingService
    let isPeeking: Bool

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(maxWidth: .infinity, alignment: .leading)
            trailing.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
    }

    @ViewBuilder private var leading: some View {
        switch activity {
        case let .hud(.volume(level, muted)):
            Image(systemName: muted ? "speaker.slash.fill" : level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                .contentTransition(.symbolEffect(.replace))
        case .hud(.brightness):
            Image(systemName: "sun.max.fill")
        case .transient(.charging):
            Image(systemName: "bolt.fill").foregroundStyle(.green)
        case .transient(.timerDone):
            Image(systemName: "bell.fill").foregroundStyle(.orange).symbolEffect(.pulse)
        case .timer:
            Image(systemName: "timer").foregroundStyle(.orange)
        case .music:
            Group {
                if let art = nowPlaying.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").font(.system(size: 11)).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.15))
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder private var trailing: some View {
        switch activity {
        case let .hud(.volume(level, muted)):
            LevelBar(level: muted ? 0 : level)
        case let .hud(.brightness(level)):
            LevelBar(level: level)
        case let .transient(.charging(level)):
            Text("\(level)%").foregroundStyle(.green)
        case .transient(.timerDone):
            Text("Done").foregroundStyle(.orange)
        case .timer:
            Group {
                if let end = vm.timer.endDate {
                    Text(timerInterval: Date()...end, countsDown: true)
                } else {
                    Text(CountdownTimer.format(vm.timer.remaining())).opacity(0.6)
                }
            }
            .monospacedDigit()
            .foregroundStyle(.orange)
            .frame(width: 44, alignment: .trailing)
        case .music:
            Image(systemName: "waveform")
                .foregroundStyle(.pink)
                .symbolEffect(.variableColor.iterative, isActive: isPeeking)
        }
    }
}

struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(Color.white).frame(width: geo.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
        .frame(width: 64, height: 5)
        .animation(.easeOut(duration: 0.12), value: level)
    }
}
