import IslandCore
import SwiftUI

struct ExpandedView: View {
    @ObservedObject var vm: IslandViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var battery: BatteryService
    @ObservedObject var calendar: CalendarService
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: vm.notchSize.height)
            Group {
                switch vm.tab {
                case .home: HomeView(vm: vm, settings: settings, nowPlaying: nowPlaying, calendar: calendar)
                case .shelf: ShelfView(vm: vm, shelf: shelf)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .frame(maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                TabButton(title: "Home", symbol: "house.fill", selected: vm.tab == .home) { vm.tab = .home }
                TabButton(title: shelf.items.isEmpty ? "Shelf" : "Shelf \(shelf.items.count)", symbol: "tray.full.fill",
                          selected: vm.tab == .shelf) { vm.tab = .shelf }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if vm.hasNotch { Color.clear.frame(width: vm.notchSize.width) }

            HStack(spacing: 10) {
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                if settings.showBattery, battery.hasBattery {
                    HStack(spacing: 3) {
                        Text("\(battery.level)%").font(.system(size: 11, weight: .medium)).monospacedDigit()
                        Image(systemName: battery.symbolName)
                            .foregroundStyle(battery.isPluggedIn ? .green : battery.level <= 20 ? .red : .white)
                    }
                }
                Button { vm.openSettings() } label: { Image(systemName: "gearshape.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
    }
}

private struct TabButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : 0)))
                .foregroundStyle(selected ? .white : .secondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

// MARK: Home

struct HomeView: View {
    @ObservedObject var vm: IslandViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var calendar: CalendarService

    var body: some View {
        HStack(spacing: 10) {
            if settings.showMusic { NowPlayingCard(nowPlaying: nowPlaying).frame(maxWidth: .infinity) }
            if settings.showCalendar { CalendarCard(calendar: calendar).frame(maxWidth: 170) }
            TimerCard(vm: vm).frame(maxWidth: 170)
        }
    }
}

struct NowPlayingCard: View {
    @ObservedObject var nowPlaying: NowPlayingService

    var body: some View {
        Card {
            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text(nowPlaying.track?.title ?? "Nothing playing")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(nowPlaying.track.map { $0.artist.isEmpty ? $0.source.rawValue : $0.artist } ?? "Play something in Music or Spotify")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 6)
                    HStack(spacing: 18) {
                        control("backward.fill", size: 14) { nowPlaying.previous() }
                        control(nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 20) { nowPlaying.playPause() }
                            .contentTransition(.symbolEffect(.replace))
                        control("forward.fill", size: 14) { nowPlaying.next() }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var artwork: some View {
        Group {
            if let art = nowPlaying.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").font(.system(size: 26, weight: .semibold)))
            }
        }
        .frame(width: 78, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(nowPlaying.isPlaying ? 1 : 0.9)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: nowPlaying.isPlaying)
    }

    private func control(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold)).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CalendarCard: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label("Up next", systemImage: "calendar").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                switch calendar.access {
                case .notDetermined:
                    Spacer(minLength: 0)
                    Button("Allow Calendar") { calendar.requestAccess() }.controlSize(.small)
                case .denied:
                    Text("Calendar access is off").font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Open Settings") { calendar.openPrivacySettings() }.controlSize(.small)
                case .granted:
                    if let event = calendar.nextEvent {
                        HStack(alignment: .top, spacing: 6) {
                            Capsule().fill(Color(nsColor: event.color)).frame(width: 3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                Text(timeText(event)).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No events in the next 24 hours").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func timeText(_ event: CalendarService.EventInfo) -> String {
        if event.isAllDay { return "All day" }
        if event.start <= Date() { return "Now · until \(event.end.formatted(date: .omitted, time: .shortened))" }
        let range = "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
        let minutes = Int(event.start.timeIntervalSinceNow / 60)
        return minutes < 60 ? "In \(max(minutes, 1)) min · \(range)" : range
    }
}

struct TimerCard: View {
    @ObservedObject var vm: IslandViewModel
    private let presets: [Double] = [1, 5, 10, 25]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label("Timer", systemImage: "timer").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                switch vm.timer.state {
                case .idle:
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(presets, id: \.self) { minutes in
                            Button { vm.startTimer(minutes: minutes) } label: {
                                Text("\(Int(minutes))m").font(.system(size: 12, weight: .semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                                    .foregroundStyle(.orange)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                case let .running(end):
                    Text(timerInterval: Date()...end, countsDown: true).timerFont
                    controls(paused: false)
                case let .paused(remaining):
                    Text(CountdownTimer.format(remaining)).timerFont.opacity(0.6)
                    controls(paused: true)
                }
            }
        }
    }

    private func controls(paused: Bool) -> some View {
        HStack(spacing: 14) {
            Button { paused ? vm.resumeTimer() : vm.pauseTimer() } label: { Image(systemName: paused ? "play.fill" : "pause.fill") }
            Button { vm.stopTimer() } label: { Image(systemName: "xmark") }
        }
        .buttonStyle(.plain)
        .font(.system(size: 14, weight: .semibold))
    }
}

private extension Text {
    var timerFont: some View {
        font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.orange)
    }
}
