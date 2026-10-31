import AppKit
import Combine
import IslandCore
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
    private lazy var vm = IslandViewModel(settings: settings)
    private let nowPlaying = NowPlayingService()
    private let battery = BatteryService()
    private let calendar = CalendarService()
    private let shelf = ShelfStore(fileURL: ShelfStore.defaultFileURL())
    private let mediaKeys = MediaKeyService()
    private lazy var hudState = HUDPermissionState(keys: mediaKeys)
    private let power = PowerStateMonitor()
    private var island: IslandController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        vm.openSettings = { [weak self] in self?.showSettings() }
        vm.onExpand = { [weak self] in self?.calendar.refresh() }
        battery.onPluggedIn = { [weak self] in
            guard let self, self.settings.showBattery else { return }
            self.vm.showTransient(.charging(level: self.battery.level))
        }
        power.onChange = { [weak self] suspended in self?.vm.setSuspended(suspended) }

        let root = IslandRootView(vm: vm, settings: settings, nowPlaying: nowPlaying, battery: battery,
                                  calendar: calendar, shelf: shelf)
        island = IslandController(vm: vm, settings: settings, content: root)

        mediaKeys.handler = { [weak self] key, isDown, fine in
            self?.handleMediaKey(key, isDown: isDown, fine: fine) ?? false
        }
        settings.$hudEnabled.removeDuplicates()
            .sink { [weak self] enabled in self?.hudState.apply(enabled: enabled) }
            .store(in: &cancellables)
        if settings.hudEnabled, !MediaKeyService.isTrusted(prompt: false) {
            hudState.requestPermission()
        }

        setUpStatusItem()
    }

    // MARK: HUD

    private func handleMediaKey(_ key: MediaKey, isDown: Bool, fine: Bool) -> Bool {
        let step: Float = fine ? 1.0 / 64 : 1.0 / 16
        switch key {
        case .soundUp, .soundDown, .mute:
            guard VolumeControl.isAvailable else { return false }
            if isDown {
                switch key {
                case .mute:
                    VolumeControl.isMuted.toggle()
                case .soundUp:
                    VolumeControl.isMuted = false
                    VolumeControl.volume = ((VolumeControl.volume + step) / step).rounded() * step
                default:
                    let value = ((VolumeControl.volume - step) / step).rounded() * step
                    VolumeControl.volume = value
                    if value <= 0.001 { VolumeControl.isMuted = true }
                }
                vm.showHUD(.volume(level: VolumeControl.volume, muted: VolumeControl.isMuted))
            }
            return true
        case .brightnessUp, .brightnessDown:
            guard let current = BrightnessControl.brightness else { return false }
            if isDown {
                let delta = key == .brightnessUp ? step : -step
                let value = min(max(((current + delta) / step).rounded() * step, 0), 1)
                guard BrightnessControl.set(value) else { return false }
                vm.showHUD(.brightness(level: value))
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
        menu.addItem(withTitle: "Clear Shelf", action: #selector(clearShelf), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Dynamac Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func clearShelf() { shelf.clear() }

    @objc private func showSettings() {
        vm.collapse()
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(settings: settings, hud: hudState))
            let window = NSWindow(contentViewController: controller)
            window.title = "Dynamac Island Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Drop the settings view hierarchy so its live preview stops rendering.
        DispatchQueue.main.async { [weak self] in self?.settingsWindow = nil }
    }
}
