import AppKit
import SwiftUI

/// Two-finger horizontal swipe over the island skips tracks. A local monitor only sees events
/// already routed to this app, so it costs nothing while the pointer is elsewhere.
@MainActor
final class SwipeSkipMonitor {
    private var monitor: Any?
    private var accX: CGFloat = 0
    private var accY: CGFloat = 0
    private var fired = false
    private let vm: IslandViewModel
    private let nowPlaying: NowPlayingService
    private let settings: AppSettings

    init(vm: IslandViewModel, nowPlaying: NowPlayingService, settings: AppSettings) {
        self.vm = vm
        self.nowPlaying = nowPlaying
        self.settings = settings
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.consume(event) ?? false }
            return consumed ? nil : event
        }
    }

    /// Returns true when the event was used for the swipe gesture.
    private func consume(_ event: NSEvent) -> Bool {
        guard event.window is IslandPanel, settings.swipeToSkip, settings.showMusic, nowPlaying.track != nil,
              event.hasPreciseScrollingDeltas, !(vm.state == .expanded && vm.tab != .home) else { return false }

        if event.phase == .began { accX = 0; accY = 0; fired = false }
        if event.momentumPhase != [] { return fired }

        accX += event.scrollingDeltaX
        accY += event.scrollingDeltaY
        let finger = event.isDirectionInvertedFromDevice ? accX : -accX
        let isEnd = event.phase == .ended || event.phase == .cancelled
        guard abs(accX) > abs(accY) else {
            if isEnd, !fired { settle() }
            return false
        }

        if !fired {
            vm.swipeOffset = max(-44, min(44, finger * 0.45))
            if abs(finger) > 80 {
                fired = true
                skip(next: finger < 0)
            } else if isEnd {
                settle()
            }
        }
        return true
    }

    private func settle() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { vm.swipeOffset = 0 }
    }

    /// Card-swap: fling the artwork out, bring it back from the other side.
    private func skip(next: Bool) {
        if settings.hapticsEnabled { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
        next ? nowPlaying.next() : nowPlaying.previous()
        let out: CGFloat = next ? -90 : 90
        withAnimation(.easeIn(duration: 0.14)) { vm.swipeOffset = out }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { self.vm.swipeOffset = -out }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { self.vm.swipeOffset = 0 }
        }
    }
}
