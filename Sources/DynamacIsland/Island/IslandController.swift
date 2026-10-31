import AppKit
import Combine
import IslandCore
import SwiftUI

final class IslandPanel: NSPanel {
    init(size: CGSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum IslandMetrics {
    /// Fixed transparent window; fully transparent pixels are click-through, so only the island captures input.
    static let windowSize = CGSize(width: 900, height: 340)
    static let expandedSize = CGSize(width: 740, height: 236)
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }
}

@MainActor
final class IslandController {
    private let panel = IslandPanel(size: IslandMetrics.windowSize)
    private let vm: IslandViewModel
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    init<Content: View>(vm: IslandViewModel, settings: AppSettings, content: Content) {
        self.vm = vm
        self.settings = settings
        let hosting = IslandHostingView(rootView: content)
        hosting.sizingOptions = []
        panel.contentView = hosting

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)
        settings.$displayID.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)
        vm.$isSuspended.removeDuplicates().sink { [weak self] suspended in
            guard let self else { return }
            // Ordering the window out removes it from the compositor entirely while the display sleeps.
            if suspended { self.panel.orderOut(nil) } else { self.panel.orderFrontRegardless() }
        }.store(in: &cancellables)

        reposition()
    }

    static func targetScreen(for displayID: UInt32) -> NSScreen? {
        let screens = NSScreen.screens
        if displayID != 0, let match = screens.first(where: { $0.displayID == displayID }) { return match }
        return screens.first ?? NSScreen.main
    }

    func reposition() {
        guard let screen = Self.targetScreen(for: settings.displayID) else { return }
        if let notch = screen.notchSize {
            vm.hasNotch = true
            vm.notchSize = notch
        } else {
            vm.hasNotch = false
            vm.notchSize = CGSize(width: 190, height: max(screen.frame.maxY - screen.visibleFrame.maxY, 26))
        }
        let size = IslandMetrics.windowSize
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        if !vm.isSuspended { panel.orderFrontRegardless() }
    }
}
