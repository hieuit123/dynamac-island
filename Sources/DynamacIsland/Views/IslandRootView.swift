import IslandCore
import SwiftUI

enum CollapsedActivity: Equatable {
    case hud(HUDKind)
    case transient(TransientActivity)
    case timer
    case events([CalendarService.EventInfo])
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
        let events = center.visibleEvents
        if !events.isEmpty { return .events(Array(events.prefix(CollapsedActivityView.maxEventRows))) }
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
        case .events: return 130
        case .timer: return 62
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
        // The countdown and the meeting list add rows below the notch row.
        if let activity { height += CollapsedActivityView.extraHeight(activity) }
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
        .onDrop(of: ShelfDrop.types, isTargeted: $vm.isDropTargeted) { providers in
            ShelfDrop.load(providers) { urls in shelf.add(urls) }
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
                .frame(height: vm.notchSize.height + CollapsedActivityView.extraHeight(activity), alignment: .top)
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
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading.frame(maxWidth: .infinity, alignment: .leading)
                trailing.frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: vm.notchSize.height)
            if activity == .timer { timerControls }
            if case let .events(events) = activity { eventRows(events) }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .lineLimit(1)
    }

    static let timerControlsHeight: CGFloat = 34
    static let eventRowHeight: CGFloat = 28
    static let maxEventRows = 5

    static func extraHeight(_ activity: CollapsedActivity) -> CGFloat {
        switch activity {
        case .timer: return timerControlsHeight
        case let .events(events): return CGFloat(events.count) * eventRowHeight + 8
        default: return 0
        }
    }

    private func eventRows(_ events: [CalendarService.EventInfo]) -> some View {
        VStack(spacing: 0) {
            ForEach(events, id: \.id) { event in
                HStack(spacing: 8) {
                    Circle().fill(Color(nsColor: event.color)).frame(width: 7, height: 7)
                    Text(event.title).frame(maxWidth: .infinity, alignment: .leading)
                    TimelineView(.everyMinute) { context in
                        let minutes = Int(ceil(event.start.timeIntervalSince(context.date) / 60))
                        Text(minutes <= 0 ? "Now" : "\(minutes)m")
                            .monospacedDigit()
                            .foregroundStyle(Color(nsColor: event.color))
                    }
                    Button { center.dismissEvent(event.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Dismiss \(event.title)")
                }
                .frame(height: Self.eventRowHeight)
            }
        }
        .padding(.horizontal, 4)
    }

    /// Pause keeps the timer (and this view) as it is; Cancel ends it, which collapses the island.
    private var timerControls: some View {
        let paused = center.timer.endDate == nil
        return HStack(spacing: 8) {
            timerButton(paused ? "Resume" : "Pause", symbol: paused ? "play.fill" : "pause.fill", tint: .orange) {
                paused ? center.resumeTimer() : center.pauseTimer()
            }
            timerButton("Cancel", symbol: "xmark", tint: .white.opacity(0.75)) { center.stopTimer() }
        }
        .frame(height: Self.timerControlsHeight, alignment: .center)
    }

    private func timerButton(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Capsule().fill(tint.opacity(0.2)))
                .foregroundStyle(tint)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
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
        case let .events(events):
            Image(systemName: "calendar").foregroundStyle(Color(nsColor: events.first?.color ?? .systemBlue))
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
        case let .events(events):
            Text(events.count == 1 ? "Meeting" : "\(events.count) meetings").foregroundStyle(.white.opacity(0.9))
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
