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
                case .home: HomeView(vm: vm, settings: settings, nowPlaying: nowPlaying)
                case .shelf: ShelfView(vm: vm, shelf: shelf)
                case .calendar: CalendarPanel(calendar: calendar)
                case .timer: TimerPanel(vm: vm)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .frame(maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: vm.tab)
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

            HStack(spacing: 4) {
                if settings.showCalendar {
                    HeaderIcon(symbol: "calendar", selected: vm.tab == .calendar,
                               badge: calendar.nextEvent.map { Color(nsColor: $0.color) }) { toggle(.calendar) }
                }
                HeaderIcon(symbol: "timer", selected: vm.tab == .timer,
                           badge: vm.timer.isActive ? .orange : nil) { toggle(.timer) }
                if settings.showBattery, battery.hasBattery {
                    HStack(spacing: 3) {
                        Text("\(battery.level)%").font(.system(size: 11, weight: .medium)).monospacedDigit()
                        Image(systemName: battery.symbolName)
                            .foregroundStyle(battery.isPluggedIn ? .green : battery.level <= 20 ? .red : .white)
                    }
                    .padding(.leading, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
    }

    private func toggle(_ tab: ExpandedTab) {
        vm.tab = vm.tab == tab ? .home : tab
        if tab == .calendar { calendar.refresh() }
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
        .buttonStyle(PressableStyle())
    }
}

/// Icon button in the right corner; a small dot shows live state (next event color / running timer).
private struct HeaderIcon: View {
    let symbol: String
    let selected: Bool
    var badge: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? .white : .secondary)
                .frame(width: 26, height: 22)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : 0)))
                .overlay(alignment: .topTrailing) {
                    if let badge { Circle().fill(badge).frame(width: 5, height: 5).offset(x: -3, y: 2) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
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

    var body: some View {
        if settings.showMusic {
            NowPlayingCard(nowPlaying: nowPlaying, vm: vm, gradientProgress: settings.gradientProgress)
        } else {
            Card {
                VStack(spacing: 4) {
                    Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 18, weight: .bold))
                    Text("Drop files on the island to keep them on the Shelf")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: Calendar

struct CalendarPanel: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text("Next 24 hours").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                switch calendar.access {
                case .notDetermined:
                    message("See your upcoming events here.") {
                        Button("Allow Calendar") { calendar.requestAccess() }.controlSize(.small)
                    }
                case .denied:
                    message("Calendar access is off.") {
                        Button("Open Settings") { calendar.openPrivacySettings() }.controlSize(.small)
                    }
                case .granted:
                    if calendar.upcoming.isEmpty {
                        message("No events in the next 24 hours.") { EmptyView() }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(calendar.upcoming.enumerated()), id: \.offset) { _, event in
                                EventRow(event: event)
                            }
                        }
                    }
                }
            }
        }
    }

    private func message<A: View>(_ text: String, @ViewBuilder action: () -> A) -> some View {
        VStack(spacing: 8) {
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            action()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EventRow: View {
    let event: CalendarService.EventInfo

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(Color(nsColor: event.color)).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(timeText).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        if event.start <= Date() { return "Now · until \(event.end.formatted(date: .omitted, time: .shortened))" }
        let range = "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
        let minutes = Int(event.start.timeIntervalSinceNow / 60)
        return minutes < 60 ? "In \(max(minutes, 1)) min · \(range)" : range
    }
}

// MARK: Timer

struct TimerPanel: View {
    @ObservedObject var vm: IslandViewModel
    private let presets: [Double] = [1, 3, 5, 10, 15, 25, 45, 60]

    var body: some View {
        Card {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Color.orange.opacity(0.18), lineWidth: 6)
                    TimelineView(.animation(minimumInterval: 1, paused: vm.timer.endDate == nil)) { context in
                        let fraction = vm.timer.duration > 0 ? vm.timer.remaining(now: context.date) / vm.timer.duration : 0
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: fraction)
                    }
                    timeText
                }
                .frame(width: 118, height: 118)

                VStack(alignment: .leading, spacing: 10) {
                    if vm.timer.isActive {
                        HStack(spacing: 10) {
                            let paused = vm.timer.endDate == nil
                            pill(paused ? "Resume" : "Pause", symbol: paused ? "play.fill" : "pause.fill") {
                                paused ? vm.resumeTimer() : vm.pauseTimer()
                            }
                            pill("Cancel", symbol: "xmark", tint: .white.opacity(0.7)) { vm.stopTimer() }
                        }
                    } else {
                        Text("Start a timer").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(presets, id: \.self) { minutes in
                                Button { vm.startTimer(minutes: minutes) } label: {
                                    Text(minutes >= 60 ? "1h" : "\(Int(minutes))m")
                                        .font(.system(size: 12, weight: .semibold))
                                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                                        .foregroundStyle(.orange)
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var timeText: some View {
        Group {
            switch vm.timer.state {
            case .idle: Text("0:00").opacity(0.4)
            case let .running(end): Text(timerInterval: Date()...end, countsDown: true)
            case let .paused(remaining): Text(CountdownTimer.format(remaining)).opacity(0.6)
            }
        }
        .font(.system(size: 24, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.orange)
        .multilineTextAlignment(.center)
        .frame(width: 96)
    }

    private func pill(_ title: String, symbol: String, tint: Color = .orange, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(tint.opacity(0.18)))
                .foregroundStyle(tint)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}
