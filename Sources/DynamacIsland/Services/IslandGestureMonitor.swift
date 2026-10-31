import AppKit
import SwiftUI

/// Trackpad and mouse gestures on the island. Local monitors only see events already routed to this app,
/// so they cost nothing while the pointer is elsewhere.
///  - Two-finger swipe left/right: skip track.
///  - Swipe down: expand, or cycle panels when expanded.  Swipe up: collapse, or dismiss the live activity.
///  - Middle click: expand / cycle panels.
@MainActor
final class IslandGestureMonitor {
    private var monitors: [Any] = []
    private var accX: CGFloat = 0
    private var accY: CGFloat = 0
    private var fired = false
    private let island: (NSWindow?) -> IslandViewModel?
    private let nowPlaying: NowPlayingService
    private let center: ActivityCenter
    private let settings: AppSettings

    init(island: @escaping (NSWindow?) -> IslandViewModel?, nowPlaying: NowPlayingService, center: ActivityCenter,
         settings: AppSettings) {
        self.island = island
        self.nowPlaying = nowPlaying
        self.center = center
        self.settings = settings
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handleScroll(event) ?? false }
            return consumed ? nil : event
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handleMiddleClick(event) ?? false }
            return consumed ? nil : event
        } as Any)
    }

    private func handleMiddleClick(_ event: NSEvent) -> Bool {
        guard settings.middleClickCycle, event.buttonNumber == 2, let vm = island(event.window) else { return false }
        vm.cycleTab()
        return true
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        guard let vm = island(event.window), event.hasPreciseScrollingDeltas else { return false }
        if event.phase == .began { accX = 0; accY = 0; fired = false }
        if event.momentumPhase != [] { return fired }

        accX += event.scrollingDeltaX
        accY += event.scrollingDeltaY
        let isEnd = event.phase == .ended || event.phase == .cancelled
        let inverted = event.isDirectionInvertedFromDevice
        let fingerX = inverted ? accX : -accX
        let fingerY = inverted ? accY : -accY

        if abs(accX) > abs(accY) {
            return handleHorizontal(vm, finger: fingerX, isEnd: isEnd)
        }
        guard settings.verticalSwipeGestures else { return false }
        if !fired, abs(fingerY) > 40 {
            fired = true
            fingerY > 0 ? swipeDown(vm) : swipeUp(vm)
        }
        return true
    }

    private func handleHorizontal(_ vm: IslandViewModel, finger: CGFloat, isEnd: Bool) -> Bool {
        guard settings.swipeToSkip, settings.showMusic, nowPlaying.track != nil,
              !(vm.state == .expanded && vm.tab != .home) else { return false }
        if !fired {
            vm.swipeOffset = max(-44, min(44, finger * 0.45))
            if abs(finger) > 80 {
                fired = true
                skip(vm, next: finger < 0)
            } else if isEnd {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { vm.swipeOffset = 0 }
            }
        }
        return true
    }

    private func swipeDown(_ vm: IslandViewModel) {
        haptic()
        vm.cycleTab()
    }

    private func swipeUp(_ vm: IslandViewModel) {
        haptic()
        if vm.state != .collapsed {
            vm.dismiss()
            return
        }
        // Dismiss whichever live activity is showing until it changes.
        if center.transient != nil {
            center.dismissTransient()
        } else if let event = center.upcomingEvent {
            center.dismissedActivityID = "event:" + event.id
        } else if let track = nowPlaying.track {
            center.dismissedActivityID = "music:" + track.title
        }
    }

    private func haptic() {
        if settings.hapticsEnabled { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
    }

    /// Card-swap: fling the artwork out, bring it back from the other side.
    private func skip(_ vm: IslandViewModel, next: Bool) {
        haptic()
        next ? nowPlaying.next() : nowPlaying.previous()
        let out: CGFloat = next ? -90 : 90
        withAnimation(.easeIn(duration: 0.14)) { vm.swipeOffset = out }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { vm.swipeOffset = -out }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { vm.swipeOffset = 0 }
        }
    }
}
