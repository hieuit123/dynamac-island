import IslandCore
import SwiftUI

struct ExpandedView: View {
    @ObservedObject var vm: IslandViewModel
    @ObservedObject var center: ActivityCenter
    @ObservedObject var settings: AppSettings
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var battery: BatteryService
    @ObservedObject var calendar: CalendarService
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var pet: PetStore

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: vm.notchSize.height).zIndex(1)
            Group {
                switch vm.tab {
                case .home: HomeView(vm: vm, center: center, settings: settings, nowPlaying: nowPlaying)
                case .shelf: ShelfView(vm: vm, shelf: shelf)
                case .calendar: CalendarPanel(calendar: calendar)
                case .timer: TimerPanel(center: center)
                case .battery: BatteryPanel(battery: battery)
                case .pet: PetPanel(store: pet)
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
            HStack(spacing: 4) {
                HeaderIcon(symbol: "house.fill", title: "Home", selected: vm.tab == .home) { vm.tab = .home }
                HeaderIcon(symbol: "tray.full.fill",
                           title: shelf.items.isEmpty ? "Shelf" : "Shelf (\(shelf.items.count))",
                           selected: vm.tab == .shelf, badge: shelf.items.isEmpty ? nil : .white) { vm.tab = .shelf }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if vm.hasNotch { Color.clear.frame(width: vm.notchSize.width) }

            HStack(spacing: 4) {
                if settings.showPet {
                    HeaderIcon(symbol: "pawprint.fill", title: "Pet", selected: vm.tab == .pet) { toggle(.pet) }
                }
                if settings.showCalendar {
                    HeaderIcon(symbol: "calendar", title: "Calendar", selected: vm.tab == .calendar,
                               badge: calendar.nextEvent.map { Color(nsColor: $0.color) }) { toggle(.calendar) }
                }
                if settings.showTimer {
                    HeaderIcon(symbol: "timer", title: "Timer", selected: vm.tab == .timer,
                               badge: center.timer.isActive ? .orange : nil) { toggle(.timer) }
                }
                if settings.showBattery, battery.hasBattery {
                    Button { toggle(.battery) } label: {
                        HStack(spacing: 3) {
                            Text("\(battery.level)%").font(.system(size: 11, weight: .medium)).monospacedDigit()
                            Image(systemName: battery.symbolName)
                                .foregroundStyle(battery.isPluggedIn ? .green : battery.level <= 20 ? .red : battery.isLowPowerMode ? .yellow : .white)
                        }
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.white.opacity(vm.tab == .battery ? 0.16 : 0)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .instantTooltip("Battery")
                    .padding(.leading, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
    }

    private func toggle(_ tab: ExpandedTab) {
        vm.tab = vm.tab == tab ? .home : tab
        if tab == .calendar { calendar.syncNow() }
    }
}

/// Native `.help` waits about a second; this label shows as soon as the pointer is over the view.
private struct InstantTooltip: ViewModifier {
    let text: String
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .overlay(alignment: .bottom) {
                if hovering {
                    Text(text)
                        .font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color(white: 0.22)))
                        .fixedSize()
                        .offset(y: 28)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

private extension View {
    func instantTooltip(_ text: String) -> some View { modifier(InstantTooltip(text: text)) }
}

/// Icon-only header button with a tooltip; a small dot shows live state (next event color / running timer / shelf not empty).
private struct HeaderIcon: View {
    let symbol: String
    let title: String
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
        .instantTooltip(title)
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
    @ObservedObject var center: ActivityCenter
    @ObservedObject var settings: AppSettings
    @ObservedObject var nowPlaying: NowPlayingService

    var body: some View {
        if settings.showMusic {
            NowPlayingCard(nowPlaying: nowPlaying, vm: vm, settings: settings)
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
                    Button { calendar.open(nil) } label: {
                        Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.system(size: 13, weight: .bold))
                    }
                    .buttonStyle(PressableStyle())
                    .help("Open calendar")
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
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(calendar.upcoming.enumerated()), id: \.offset) { _, event in
                                    Button { calendar.open(event) } label: { EventRow(event: event) }
                                        .buttonStyle(PressableStyle())
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
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
    @ObservedObject var center: ActivityCenter
    // Remembered between launches so a favorite duration is one click away.
    @AppStorage("timerHours") private var hours = 0
    @AppStorage("timerMinutes") private var minutes = 5
    @AppStorage("timerSeconds") private var seconds = 0

    private var totalSeconds: Int { hours * 3600 + minutes * 60 + seconds }
    private let quickMinutes = [1, 5, 10, 15, 30, 60]

    private enum Unit { case hours, minutes, seconds }
    @State private var hoveredUnit: Unit?
    @State private var scrollMonitor: Any?
    @State private var scrollAccumulator: CGFloat = 0

    private struct ScrollInput: Sendable {
        var deltaY: CGFloat
        var inverted: Bool
        var precise: Bool
        var isMomentum: Bool
    }

    /// Scrolling over a unit changes it: up increases, down decreases (clamped, no wrap-around). Returns true when consumed.
    private func handleScroll(_ input: ScrollInput) -> Bool {
        guard let unit = hoveredUnit, !center.timer.isActive else { return false }
        guard !input.isMomentum else { return true }
        let finger = input.inverted ? input.deltaY : -input.deltaY
        var steps = 0
        if input.precise {
            scrollAccumulator += finger
            steps = -Int(scrollAccumulator / 10)
            scrollAccumulator -= CGFloat(-steps) * 10
        } else if finger != 0 {
            steps = finger < 0 ? 1 : -1
        }
        if steps != 0 { adjust(unit, by: steps) }
        return true
    }

    private func adjust(_ unit: Unit, by steps: Int) {
        switch unit {
        case .hours: hours = min(max(hours + steps, 0), 24)
        case .minutes: minutes = min(max(minutes + steps, 0), 59)
        case .seconds: seconds = min(max(seconds + steps, 0), 59)
        }
        normalize()
    }

    /// Quick buttons start right away and also fill the picker, so the same duration is remembered.
    private func startQuick(minutes quick: Int) {
        hours = quick / 60
        minutes = quick % 60
        seconds = 0
        center.startTimer(seconds: quick * 60)
    }

    var body: some View {
        Card {
            GeometryReader { geo in
            HStack(spacing: 0) {
                ZStack {
                    Circle().stroke(Color.orange.opacity(0.18), lineWidth: 6)
                    // Removed when idle: a running linear animation already targets 0 and can't be "reset" to 0.
                    if center.timer.isActive {
                        CountdownRing(state: center.timer.state, duration: center.timer.duration)
                            .transition(.opacity)
                    }
                    timeText
                }
                .frame(width: 118, height: 118)
                // The ring takes 3 parts of the width and the controls 7.
                .frame(width: geo.size.width * 0.3, height: geo.size.height)

                VStack(alignment: .leading, spacing: 10) {
                    if center.timer.isActive {
                        Text(center.timer.endDate == nil ? "Paused" : "Running")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            let paused = center.timer.endDate == nil
                            pill(paused ? "Resume" : "Pause", symbol: paused ? "play.fill" : "pause.fill") {
                                paused ? center.resumeTimer() : center.pauseTimer()
                            }
                            pill("Cancel", symbol: "xmark", tint: .white.opacity(0.7)) { center.stopTimer() }
                        }
                    } else {
                        Text("Set a timer").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        HStack(alignment: .top, spacing: 6) {
                            unitPicker($hours, max: 24, label: "hr", unit: .hours)
                            colon
                            unitPicker($minutes, max: 59, label: "min", unit: .minutes)
                            colon
                            unitPicker($seconds, max: 59, label: "sec", unit: .seconds)
                            Spacer(minLength: 8)
                            pill("Start", symbol: "play.fill") { center.startTimer(seconds: totalSeconds) }
                                .opacity(totalSeconds > 0 ? 1 : 0.4)
                                .disabled(totalSeconds == 0)
                                .padding(.top, 22)
                        }
                        HStack(spacing: 6) {
                            ForEach(quickMinutes, id: \.self) { quick in
                                Button { startQuick(minutes: quick) } label: {
                                    Text(quick >= 60 ? "\(quick / 60)h" : "\(quick)m")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                                        .foregroundStyle(.orange)
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                // Fixed share of the width so the ring doesn't jump sideways when switching between setup and controls.
                .padding(.leading, 28)
                .padding(.trailing, 8)
                .frame(width: geo.size.width * 0.7, height: geo.size.height, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: center.timer.isActive)
            }
            }
            .onAppear {
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    let input = ScrollInput(deltaY: event.scrollingDeltaY, inverted: event.isDirectionInvertedFromDevice,
                                            precise: event.hasPreciseScrollingDeltas, isMomentum: event.momentumPhase != [])
                    let consumed = MainActor.assumeIsolated { handleScroll(input) }
                    return consumed ? nil : event
                }
            }
            .onDisappear {
                if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
                scrollMonitor = nil
                hoveredUnit = nil
            }
        }
    }

    private var colon: some View {
        Text(":").font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(.secondary).padding(.top, 22)
    }

    /// 24:00:00 is the longest timer, so at 24 hours the minutes and seconds are forced to zero.
    private func normalize() {
        if hours >= 24 { hours = 24; minutes = 0; seconds = 0 }
    }

    private func unitPicker(_ value: Binding<Int>, max limit: Int, label: String, unit: Unit) -> some View {
        VStack(spacing: 2) {
            stepButton("chevron.up") { value.wrappedValue = value.wrappedValue >= limit ? 0 : value.wrappedValue + 1; normalize() }
            TextField("00", text: Binding(
                get: { String(format: "%02d", value.wrappedValue) },
                set: { text in
                    let digits = text.filter(\.isNumber).suffix(2)
                    value.wrappedValue = min(Int(digits) ?? 0, limit)
                    normalize()
                }))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.orange)
                .frame(width: 52)
            stepButton("chevron.down") { value.wrappedValue = value.wrappedValue <= 0 ? limit : value.wrappedValue - 1; normalize() }
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .onHover { inside in
            if inside { hoveredUnit = unit } else if hoveredUnit == unit { hoveredUnit = nil }
        }
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .foregroundStyle(.orange)
                .frame(width: 52, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder private var timeText: some View {
        Group {
            switch center.timer.state {
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

// MARK: Battery

struct BatteryPanel: View {
    @ObservedObject var battery: BatteryService
    @State private var keyboardLevel = 0.0
    @State private var keyboardAuto = false
    private let keyboardAvailable = KeyboardBacklight.isAvailable

    var body: some View {
        Card {
            HStack(spacing: 0) {
                batteryInfo.frame(maxWidth: .infinity)
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1).padding(.vertical, 8)
                keyboardControl.frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { battery.refresh() }
            // The remaining-time estimate changes without a power-source event, so re-read it while the panel is open.
            .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in battery.refresh() }
        }
    }

    private var batteryInfo: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 2.5)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [fill.opacity(0.75), fill], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(CGFloat(battery.level) / 100 * 98, 6))
                    .padding(5)
                if battery.isPluggedIn {
                    Image(systemName: "bolt.fill").font(.system(size: 24, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .shadow(radius: 4)
                }
            }
            .frame(width: 108, height: 62)
            .overlay(alignment: .trailing) {
                Capsule().fill(Color.white.opacity(0.35)).frame(width: 5, height: 20).offset(x: 7)
            }
            .padding(.trailing, 6)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: battery.level)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(battery.level)%").font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                Text(battery.statusText).font(.system(size: 13, weight: .semibold))
                if let remaining = battery.remainingText {
                    Text(remaining).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                if battery.isLowPowerMode {
                    Label("Low Power Mode", systemImage: "leaf.fill")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.yellow)
                }
            }
        }
    }

    @ViewBuilder private var keyboardControl: some View {
        if keyboardAvailable {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Keyboard backlight", systemImage: "keyboard")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("\(Int((keyboardLevel * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
                HStack(spacing: 8) {
                    Image(systemName: "light.min").foregroundStyle(.secondary)
                    LevelSlider(value: $keyboardLevel, tint: .white) { level in
                        // With auto brightness on, the light sensor would undo a manual level.
                        if keyboardAuto { KeyboardBacklight.setAuto(false); keyboardAuto = false }
                        KeyboardBacklight.set(Float(level))
                    }
                    Image(systemName: "light.max").foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                Button {
                    keyboardAuto.toggle()
                    KeyboardBacklight.setAuto(keyboardAuto)
                    keyboardLevel = Double(KeyboardBacklight.level ?? 0)
                } label: {
                    Label(keyboardAuto ? "Auto brightness on" : "Auto brightness off", systemImage: "sun.max")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(keyboardAuto ? 0.18 : 0.08)))
                        .foregroundStyle(keyboardAuto ? .white : .secondary)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.leading, 22)
            .onAppear {
                keyboardLevel = Double(KeyboardBacklight.level ?? 0)
                keyboardAuto = KeyboardBacklight.isAutoEnabled
            }
        } else {
            Label("No keyboard backlight", systemImage: "keyboard")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var fill: Color {
        if battery.isPluggedIn { return .green }
        if battery.isLowPowerMode { return .yellow }
        return battery.level <= 20 ? .red : .white
    }
}

/// Draggable level bar that matches the island's look; the whole track is the hit area.
private struct LevelSlider: View {
    @Binding var value: Double
    let tint: Color
    /// Called only for changes made by the user, not when the value is set from outside.
    var onUserChange: (Double) -> Void = { _ in }
    private let knob: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - knob, 1)
            let x = travel * value
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18)).frame(height: 8)
                Capsule().fill(tint).frame(width: x + knob / 2, height: 8)
                Circle().fill(tint)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = min(max((drag.location.x - knob / 2) / travel, 0), 1)
                onUserChange(value)
            })
        }
        .frame(height: knob)
    }
}

/// Progress ring driven by one linear animation to zero over the remaining time, so it moves smoothly
/// while Core Animation does the work (no per-second SwiftUI updates).
private struct CountdownRing: View {
    let state: CountdownTimer.State
    let duration: TimeInterval
    @State private var fraction: Double = 0
    @State private var generation = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: fraction)
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .onAppear(perform: sync)
            .onChange(of: state) { sync() }
    }

    private func sync() {
        let now = Date()
        generation += 1
        let token = generation
        let current: Double
        switch state {
        case .idle: current = 0
        case let .running(end): current = duration > 0 ? max(end.timeIntervalSince(now), 0) / duration : 0
        case let .paused(remaining): current = duration > 0 ? remaining / duration : 0
        }
        let isStart = fraction == 0 && current > 0
        if isStart {
            // Fill the ring once on start, then begin the countdown.
            withAnimation(.easeOut(duration: 0.35)) { fraction = current }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { fraction = current }
        }
        guard case let .running(end) = state else { return }
        let delay = isStart ? 0.35 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard token == generation else { return }
            withAnimation(.linear(duration: max(end.timeIntervalSinceNow, 0))) { fraction = 0 }
        }
    }
}
