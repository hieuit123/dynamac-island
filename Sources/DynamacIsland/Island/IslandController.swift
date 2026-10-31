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
    static let expandedSize = CGSize(width: 640, height: 236)
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
    let displayID: CGDirectDisplayID
    let vm: IslandViewModel
    private let panel = IslandPanel(size: IslandMetrics.windowSize)
    private let settings: AppSettings
    private let visibility: VisibilityMonitor
    private var cancellables = Set<AnyCancellable>()

    init<Content: View>(displayID: CGDirectDisplayID, vm: IslandViewModel, settings: AppSettings,
                        visibility: VisibilityMonitor, content: Content) {
        self.displayID = displayID
        self.vm = vm
        self.settings = settings
        self.visibility = visibility
        let hosting = IslandHostingView(rootView: content)
        hosting.sizingOptions = []
        panel.contentView = hosting

        let relayout = Publishers.MergeMany(
            settings.$notchWidthOffset.map { _ in () }.eraseToAnyPublisher(),
            settings.$notchHeightOffset.map { _ in () }.eraseToAnyPublisher(),
            settings.$simulatedNotch.map { _ in () }.eraseToAnyPublisher())
        relayout.dropFirst(3).receive(on: RunLoop.main)
            .sink { [weak self] in self?.reposition() }
            .store(in: &cancellables)

        let visibilityInputs = Publishers.MergeMany(
            vm.activities.center.$isSuspended.map { _ in () }.eraseToAnyPublisher(),
            visibility.$fullscreenDisplays.map { _ in () }.eraseToAnyPublisher(),
            visibility.$isGaming.map { _ in () }.eraseToAnyPublisher(),
            settings.$hideInFullscreen.map { _ in () }.eraseToAnyPublisher(),
            settings.$hideWhileGaming.map { _ in () }.eraseToAnyPublisher())
        visibilityInputs.receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateVisibility() }
            .store(in: &cancellables)

        settings.$hideInMissionControl.sink { [weak self] hide in
            // Stationary windows stay visible in Mission Control; transient ones are hidden by it.
            self?.panel.collectionBehavior = [.canJoinAllSpaces, hide ? .transient : .stationary, .fullScreenAuxiliary, .ignoresCycle]
        }.store(in: &cancellables)
        settings.$hideFromCapture.sink { [weak self] hide in
            self?.panel.sharingType = hide ? .none : .readOnly
        }.store(in: &cancellables)

        reposition()
    }

    var window: NSWindow { panel }

    func close() {
        cancellables.removeAll()
        panel.orderOut(nil)
        panel.close()
    }

    private var shouldHide: Bool {
        if vm.activities.center.isSuspended { return true }
        if settings.hideInFullscreen && visibility.fullscreenDisplays.contains(displayID) { return true }
        if settings.hideWhileGaming && visibility.isGaming { return true }
        return false
    }

    /// Ordering the window out removes it from the compositor entirely while hidden.
    private func updateVisibility() {
        if shouldHide {
            vm.collapse()
            panel.orderOut(nil)
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    static func preferredDisplayID(_ selected: UInt32) -> CGDirectDisplayID? {
        let screens = NSScreen.screens
        if selected != 0, screens.contains(where: { $0.displayID == selected }) { return selected }
        return (screens.first ?? NSScreen.main)?.displayID
    }

    func reposition() {
        guard let screen = Self.screen(for: displayID) else { return }
        let widthOffset = CGFloat(settings.notchWidthOffset), heightOffset = CGFloat(settings.notchHeightOffset)
        if let notch = screen.notchSize {
            vm.hasNotch = true
            vm.pillMode = false
            vm.notchSize = CGSize(width: max(notch.width + widthOffset, 80), height: max(notch.height + heightOffset, 20))
        } else {
            vm.hasNotch = false
            vm.pillMode = !settings.simulatedNotch
            let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, 26)
            let height = settings.simulatedNotch ? menuBar : 28
            vm.notchSize = CGSize(width: max(190 + widthOffset, 80), height: max(height + heightOffset, 20))
        }
        let size = IslandMetrics.windowSize
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        updateVisibility()
    }
}
