import AppKit
import Combine
import IslandCore
import CoreBluetooth
import SwiftUI

@main
enum DynamacIslandApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// Tracks whether the media-key tap is running; retries cheaply until Accessibility is granted.
@MainActor
final class HUDPermissionState: ObservableObject {
    @Published private(set) var isActive = false
    private let keys: MediaKeyService
    private var retryTimer: Timer?

    init(keys: MediaKeyService) { self.keys = keys }

    func apply(enabled: Bool) {
        retryTimer?.invalidate()
        retryTimer = nil
        guard enabled else {
            keys.stop()
            isActive = false
            return
        }
        isActive = keys.start()
        if !isActive {
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.keys.start() else { return }
                    self.isActive = true
                    self.retryTimer?.invalidate()
                    self.retryTimer = nil
                }
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            retryTimer = timer
        }
    }

    func requestPermission() {
        _ = MediaKeyService.isTrusted(prompt: true)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = AppSettings.shared
    private lazy var center = ActivityCenter(settings: settings)
    private lazy var nowPlaying = NowPlayingService(settings: settings)
    private let battery = BatteryService()
    private lazy var calendar = CalendarService(settings: settings, center: center)
    private let shelf = ShelfStore(fileURL: ShelfStore.defaultFileURL())
    private let pet = PetStore(fileURL: PetStore.defaultFileURL())
    private lazy var activities = AppActivities(center: center, nowPlaying: nowPlaying, battery: battery,
                                                calendar: calendar, shelf: shelf, pet: pet)
    private let mediaKeys = MediaKeyService()
    private lazy var hudState = HUDPermissionState(keys: mediaKeys)
    private let power = PowerStateMonitor()
    private let visibility = VisibilityMonitor()
    private let bluetooth = BluetoothMonitor()
    private let focus = FocusMonitor()
    private let permissions = PermissionStatus()
    private var islands: [IslandController] = []
    private var gestures: IslandGestureMonitor?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        wireActivities()
        rebuildIslands()
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.rebuildIslands() }
            .store(in: &cancellables)
        Publishers.Merge(settings.$showOnAllDisplays.map { _ in () }, settings.$displayID.map { _ in () })
            .dropFirst(2)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.rebuildIslands() }
            .store(in: &cancellables)

        gestures = IslandGestureMonitor(island: { [weak self] window in
            self?.islands.first { $0.window === window }?.vm
        }, nowPlaying: nowPlaying, center: center, settings: settings)

        mediaKeys.handler = { [weak self] key, isDown, fine in
            self?.handleMediaKey(key, isDown: isDown, fine: fine) ?? false
        }
        settings.$hudEnabled.removeDuplicates()
            .sink { [weak self] enabled in self?.hudState.apply(enabled: enabled) }
            .store(in: &cancellables)

        setUpStatusItem()
        if !settings.onboardingDone { showOnboarding() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        nowPlaying.stop()
    }

    private func wireActivities() {
        battery.onPluggedIn = { [weak self] in
            guard let self, self.settings.showBattery else { return }
            self.center.showTransient(.charging(level: self.battery.level), sound: self.settings.chargingSound ? "Pop" : nil)
        }
        battery.onLowBattery = { [weak self] level in
            guard let self, self.settings.lowBatteryAlerts else { return }
            self.center.showTransient(.lowBattery(level: level), duration: 5, sound: self.settings.lowBatterySound ? "Sosumi" : nil)
        }
        battery.onLowPowerModeChange = { [weak self] on in
            guard let self, self.settings.lowPowerModeAlert else { return }
            self.center.showTransient(.lowPowerMode(on: on))
        }
        bluetooth.onChange = { [weak self] name, symbol, level, connected in
            guard let self, self.settings.bluetoothActivity else { return }
            self.center.showTransient(.bluetooth(name: name, symbol: symbol, battery: level, connected: connected), duration: 4)
        }
        focus.onChange = { [weak self] mode, on in
            guard let self, self.settings.focusActivity else { return }
            self.center.showTransient(.focus(name: mode.name, symbol: mode.symbol, tint: mode.tint, on: on))
        }
        nowPlaying.onLinkCopied = { [weak self] in self?.center.showTransient(.linkCopied, duration: 2) }
        power.onChange = { [weak self] suspended in
            self?.center.setSuspended(suspended)
            if !suspended { self?.calendar.refresh() }
        }
        settings.$bluetoothActivity.sink { [weak self] enabled in
            // Only start automatically once allowed, so launching never triggers a surprise permission prompt.
            if enabled, CBManager.authorization == .allowedAlways { self?.bluetooth.start() } else if !enabled { self?.bluetooth.stop() }
        }.store(in: &cancellables)
        settings.$focusActivity.sink { [weak self] enabled in
            enabled ? self?.focus.start() : self?.focus.stop()
        }.store(in: &cancellables)
    }

    // MARK: Islands (one per display when "show on all displays" is on)

    private func rebuildIslands() {
        let wanted: [CGDirectDisplayID] = settings.showOnAllDisplays
            ? NSScreen.screens.map(\.displayID)
            : IslandController.preferredDisplayID(settings.displayID).map { [$0] } ?? []
        for island in islands where !wanted.contains(island.displayID) { island.close() }
        islands.removeAll { !wanted.contains($0.displayID) }
        for id in wanted {
            if let existing = islands.first(where: { $0.displayID == id }) {
                existing.reposition()
                continue
            }
            let vm = IslandViewModel(settings: settings, activities: activities)
            vm.onExpand = { [weak self] in
                self?.calendar.refresh()
                self?.nowPlaying.refreshDetails()
            }
            let root = IslandRootView(vm: vm, center: center, settings: settings, nowPlaying: nowPlaying, battery: battery,
                                      calendar: calendar, shelf: shelf, pet: pet)
            islands.append(IslandController(displayID: id, vm: vm, settings: settings, visibility: visibility, content: root))
        }
    }

    // MARK: HUD

    private func handleMediaKey(_ key: MediaKey, isDown: Bool, fine: Bool) -> Bool {
        let step: Float = fine ? 1.0 / 64 : 1.0 / 16
        switch key {
        case .soundUp, .soundDown, .mute:
            guard VolumeControl.isAvailable else { return false }
            if isDown {
                let before = VolumeControl.volume
                switch key {
                case .mute:
                    VolumeControl.isMuted.toggle()
                case .soundUp:
                    VolumeControl.isMuted = false
                    VolumeControl.volume = ((before + step) / step).rounded() * step
                default:
                    let value = ((before - step) / step).rounded() * step
                    VolumeControl.volume = value
                    if value <= 0.001 { VolumeControl.isMuted = true }
                }
                let atLimit = (key == .soundUp && before >= 0.999) || (key == .soundDown && before <= 0.001)
                center.showHUD(.volume(level: VolumeControl.volume, muted: VolumeControl.isMuted), atLimit: atLimit)
            }
            return true
        case .brightnessUp, .brightnessDown:
            guard let current = BrightnessControl.brightness else { return false }
            if isDown {
                let delta = key == .brightnessUp ? step : -step
                let value = min(max(((current + delta) / step).rounded() * step, 0), 1)
                guard BrightnessControl.set(value) else { return false }
                let atLimit = (key == .brightnessUp && current >= 0.999) || (key == .brightnessDown && current <= 0.001)
                center.showHUD(.brightness(level: value), atLimit: atLimit)
            }
            return true
        }
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamac Island")
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Set Up Permissions…", action: #selector(showOnboarding), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Clear Shelf", action: #selector(clearShelf), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Dynamac Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func clearShelf() { shelf.clear() }

    @objc private func showSettings() {
        islands.forEach { $0.vm.collapse() }
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, hud: hudState, focusAvailable: FocusMonitor.hasAccess,
                                    usingMediaRemote: nowPlaying.usingMediaRemote)
            settingsWindow = makeWindow(title: "Dynamac Island Settings", content: view)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(status: permissions, calendar: calendar, requestBluetooth: { [weak self] in
                self?.bluetooth.start()
            }, finish: { [weak self] in
                self?.settings.onboardingDone = true
                self?.onboardingWindow?.close()
            })
            onboardingWindow = makeWindow(title: "Welcome", content: view)
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow<Content: View>(title: String, content: Content) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        // Drop closed window hierarchies so their previews/timers stop; retry monitors that may now be permitted.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if closing === self.settingsWindow { self.settingsWindow = nil }
            if closing === self.onboardingWindow {
                self.onboardingWindow = nil
                self.settings.onboardingDone = true
            }
            if self.settings.focusActivity { self.focus.start() }
            if self.settings.bluetoothActivity, CBManager.authorization == .allowedAlways { self.bluetooth.start() }
        }
    }
}
