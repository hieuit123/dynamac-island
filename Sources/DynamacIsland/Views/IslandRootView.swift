import IslandCore
import SwiftUI

enum CollapsedActivity: Equatable {
    case hud(HUDKind)
    case transient(TransientActivity)
    case timer
    case event(CalendarService.EventInfo)
    case music
    case pet
}

struct IslandRootView: View {
    @ObservedObject var vm: IslandViewModel
    @ObservedObject var center: ActivityCenter
    @ObservedObject var settings: AppSettings
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var battery: BatteryService
    @ObservedObject var calendar: CalendarService
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var pet: PetStore

    private var activity: CollapsedActivity? {
        if let hud = center.hud { return .hud(hud) }
        if let transient = center.transient { return .transient(transient) }
        if center.timer.isActive { return .timer }
        if let event = center.upcomingEvent, center.dismissedActivityID != "event:" + event.id { return .event(event) }
        if settings.showMusic, let track = nowPlaying.track, nowPlaying.isPlaying || settings.showMusicWhenPaused,
           center.dismissedActivityID != "music:" + track.title {
            return .music
        }
        return settings.showPet ? .pet : nil
    }

    private func sideWidth(_ activity: CollapsedActivity) -> CGFloat {
        switch activity {
        case .hud: return settings.hudShowPercentage ? 118 : 92
        case let .transient(t): return t.isWide ? 100 : 46
        case .event: return 60
        default: return 46
        }
    }

    private var radii: (top: CGFloat, bottom: CGFloat) {
        if vm.pillMode {
            let h = vm.notchSize.height
            switch vm.state {
            case .expanded: return (0, 30)
            case .peek: return (0, (h + 6) / 2)
            case .collapsed: return (0, h / 2)
            }
        }
        switch vm.state {
        case .expanded: return (14, 32)
        case .peek: return (8, 14)
        case .collapsed: return (6, 10)
        }
    }

    private var effectPalette: [Color]? {
        guard settings.albumTintedEffects, settings.showMusic, nowPlaying.isPlaying, nowPlaying.track != nil else { return nil }
        return nowPlaying.palette
    }

    private var islandSize: CGSize {
        if vm.state == .expanded {
            let base = IslandMetrics.expandedSize, limit = IslandMetrics.maxExpandedSize
            return CGSize(width: min(base.width + settings.expandedWidthOffset, limit.width),
                          height: min(base.height + settings.expandedHeightOffset, limit.height))
        }
        var width = vm.notchSize.width + 2 * radii.top
        var height = vm.notchSize.height
        if let activity { width += 2 * sideWidth(activity) }
        if vm.state == .peek { width += 28; height += 6 }
        return CGSize(width: width, height: height)
    }

    var body: some View {
        let size = islandSize
        let r = radii
        let shape = NotchShape(topRadius: r.top, bottomRadius: r.bottom, pill: vm.pillMode)

        ZStack(alignment: .top) {
            content(flare: r.top)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .background {
            ZStack {
                if vm.isEffectMounted {
                    BlackHoleEffect(style: settings.effectStyle, intensity: vm.effectIntensity, topRadius: r.top,
                                    bottomRadius: r.bottom, layer: .glow, palette: effectPalette, pill: vm.pillMode)
                        .transition(.opacity)
                }
                shape.fill(Color.black)
            }
        }
        .overlay {
            if vm.isEffectMounted {
                BlackHoleEffect(style: settings.effectStyle, intensity: vm.effectIntensity, topRadius: r.top,
                                bottomRadius: r.bottom, layer: .border, palette: effectPalette, pill: vm.pillMode)
                    .transition(.opacity)
            }
        }
        .padding(.top, vm.pillMode ? 4 : 0)
        // Invisible hit-slop so the tiny notch is easy to hover and to drop files onto.
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.001))
        .background(HoverTracker(onChange: { vm.hoverChanged($0) },
                                 onMake: { view in vm.mouseInsideProbe = { [weak view] in view?.isMouseInside ?? false } }))
        .contentShape(Rectangle())
        // Tap-to-expand only while collapsed/peeking; when expanded, buttons inside must get the clicks.
        .gesture(TapGesture().onEnded { vm.expand() }, including: vm.state == .expanded ? .subviews : .all)
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
    private func content(flare: CGFloat) -> some View {
        if vm.state == .expanded {
            ExpandedView(vm: vm, center: center, settings: settings, nowPlaying: nowPlaying, battery: battery,
                         calendar: calendar, shelf: shelf, pet: pet)
                .padding(.horizontal, flare)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
        } else if let activity {
            CollapsedActivityView(activity: activity, vm: vm, center: center, settings: settings, nowPlaying: nowPlaying, pet: pet)
                .frame(height: vm.notchSize.height)
                .padding(.horizontal, flare + (vm.pillMode ? 12 : 10))
                .transition(.opacity)
        }
    }
}

struct CollapsedActivityView: View {
    let activity: CollapsedActivity
    @ObservedObject var vm: IslandViewModel
    @ObservedObject var center: ActivityCenter
    @ObservedObject var settings: AppSettings
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var pet: PetStore

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(maxWidth: .infinity, alignment: .leading)
            trailing.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .lineLimit(1)
    }

    @ViewBuilder private var leading: some View {
        switch activity {
        case let .hud(.volume(level, muted)):
            Image(systemName: muted ? "speaker.slash.fill" : level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                .foregroundStyle(muted ? .red.opacity(0.9) : .white)
                .contentTransition(.symbolEffect(.replace))
        case let .hud(.brightness(level)):
            Image(systemName: level < 0.34 ? "sun.min.fill" : "sun.max.fill")
                .contentTransition(.symbolEffect(.replace))
        case .transient(.charging):
            Image(systemName: "bolt.fill").foregroundStyle(.green)
        case .transient(.timerDone):
            Image(systemName: "bell.fill").foregroundStyle(.orange).symbolEffect(.pulse)
        case .transient(.lowBattery):
            Image(systemName: "battery.25percent").foregroundStyle(.red).symbolEffect(.pulse)
        case let .transient(.lowPowerMode(on)):
            Image(systemName: on ? "leaf.fill" : "leaf").foregroundStyle(.yellow)
        case let .transient(.bluetooth(_, symbol, _, connected)):
            Image(systemName: symbol).foregroundStyle(connected ? .white : .white.opacity(0.5))
        case let .transient(.focus(_, symbol, tint, on)):
            Image(systemName: symbol).foregroundStyle(on ? FocusTint.color(tint) : .white.opacity(0.5))
        case let .transient(.eventSoon(_, _, color)):
            Image(systemName: "calendar.badge.clock").foregroundStyle(Color(nsColor: color))
        case .transient(.linkCopied):
            Image(systemName: "link").foregroundStyle(.cyan)
        case .timer:
            Image(systemName: "timer").foregroundStyle(.orange)
        case let .event(event):
            Image(systemName: "calendar").foregroundStyle(Color(nsColor: event.color))
        case .music:
            AlbumArtwork(image: nowPlaying.artwork, palette: nowPlaying.palette, isPlaying: nowPlaying.isPlaying,
                         size: 22, cornerRadius: 6, trackID: nowPlaying.track.map { $0.title + $0.artist } ?? "")
                .offset(x: vm.swipeOffset * 0.3)
        case .pet:
            PetGlyph(store: pet, size: 16)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch activity {
        case let .hud(.volume(level, muted)):
            LevelBar(level: level, muted: muted, bump: center.hudBump, settings: settings)
        case let .hud(.brightness(level)):
            LevelBar(level: level, muted: false, bump: center.hudBump, settings: settings)
        case let .transient(.charging(level)):
            Text("\(level)%").foregroundStyle(.green)
        case .transient(.timerDone):
            Text("Done").foregroundStyle(.orange)
        case let .transient(.lowBattery(level)):
            Text("\(level)%").foregroundStyle(.red)
        case let .transient(.lowPowerMode(on)):
            Text(on ? "Low Power" : "Power Normal").foregroundStyle(.yellow)
        case let .transient(.bluetooth(_, _, battery, connected)):
            if connected, let battery {
                Text("\(battery)%").foregroundStyle(battery <= 20 ? .red : .green)
            } else {
                Text(connected ? "Connected" : "Disconnected").foregroundStyle(.white.opacity(connected ? 0.9 : 0.5))
            }
        case let .transient(.focus(name, _, tint, on)):
            Text(on ? name : "\(name) Off").foregroundStyle(on ? FocusTint.color(tint) : .white.opacity(0.6))
        case let .transient(.eventSoon(_, minutes, _)):
            Text(minutes <= 0 ? "Starting" : "In \(minutes)m").foregroundStyle(.white.opacity(0.9))
        case .transient(.linkCopied):
            Text("Link Copied").foregroundStyle(.cyan)
        case .timer:
            Group {
                if let end = center.timer.endDate {
                    Text(timerInterval: Date()...end, countsDown: true)
                } else {
                    Text(CountdownTimer.format(center.timer.remaining())).opacity(0.6)
                }
            }
            .monospacedDigit()
            .foregroundStyle(.orange)
            .frame(minWidth: 44, alignment: .trailing)
            .fixedSize()
        case let .event(event):
            TimelineView(.everyMinute) { context in
                let minutes = Int(ceil(event.start.timeIntervalSince(context.date) / 60))
                Text(minutes <= 0 ? "Now" : "\(minutes)m")
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: event.color))
            }
        case .music:
            MusicWaveform(palette: nowPlaying.palette, animate: settings.animatedWaveform && nowPlaying.isPlaying)
        case .pet:
            PetMoodBadge(store: pet)
        }
    }
}

enum FocusTint {
    static func color(_ name: String) -> Color {
        let map: [String: Color] = [
            "systemBlueColor": .blue, "systemIndigoColor": .indigo, "systemPurpleColor": .purple, "systemPinkColor": .pink,
            "systemRedColor": .red, "systemOrangeColor": .orange, "systemYellowColor": .yellow, "systemGreenColor": .green,
            "systemTealColor": .teal, "systemMintColor": .mint, "systemCyanColor": .cyan, "systemBrownColor": .brown,
            "systemGrayColor": .gray,
        ]
        return map[name] ?? .indigo
    }
}

/// HUD level with optional percentage, glow, visible mute, overshoot bounce and speed setting.
struct LevelBar: View {
    let level: Float
    let muted: Bool
    let bump: Int
    @ObservedObject var settings: AppSettings

    private var animation: Animation? {
        switch settings.hudSpeed {
        case .smooth: return .spring(response: 0.28, dampingFraction: 0.82)
        case .fast: return .easeOut(duration: 0.08)
        case .instant: return nil
        }
    }

    var body: some View {
        let value = CGFloat(min(max(level, 0), 1))
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule()
                        .fill(muted ? Color.white.opacity(0.3) : Color.white)
                        .frame(width: geo.size.width * (muted ? 0 : value))
                        .shadow(color: .white.opacity(settings.hudGlow && !muted ? 0.8 : 0), radius: 4)
                }
            }
            .frame(width: 64, height: 5)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: bump) { content, scale in
                content.scaleEffect(x: scale, y: 2 - scale, anchor: value >= 0.5 ? .leading : .trailing)
            } keyframes: { _ in
                KeyframeTrack(\.self) {
                    SpringKeyframe(1.12, duration: 0.09)
                    SpringKeyframe(1, duration: 0.35, spring: .bouncy)
                }
            }
            if settings.hudShowPercentage {
                Text(muted ? "Mute" : "\(Int((value * 100).rounded()))")
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
                    .foregroundStyle(muted ? .red.opacity(0.9) : .white)
            }
        }
        .animation(animation, value: level)
        .animation(animation, value: muted)
    }
}
