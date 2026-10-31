import AppKit
import SwiftUI

/// Hover tracking that works even though the app is never active (SwiftUI's onHover is unreliable in that case).
struct HoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void
    let onMake: (TrackingView) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        onMake(view)
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) { view.onChange = onChange }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        var isMouseInside: Bool {
            guard let window else { return false }
            return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
    }
}

/// AppKit drag source so dragging files out of the shelf always *copies* (never moves) and works across screens/apps.
struct FileDragSource: NSViewRepresentable {
    let urls: [URL]
    var onDragging: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.urls = urls
        view.onDragging = onDragging
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var urls: [URL] = []
        var onDragging: ((Bool) -> Void)?
        private var mouseDownEvent: NSEvent?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            if event.clickCount == 2 { urls.forEach { NSWorkspace.shared.open($0) } }
        }

        override func mouseUp(with event: NSEvent) { mouseDownEvent = nil }

        override func mouseDragged(with event: NSEvent) {
            guard let down = mouseDownEvent, !urls.isEmpty else { return }
            let dx = event.locationInWindow.x - down.locationInWindow.x
            let dy = event.locationInWindow.y - down.locationInWindow.y
            guard hypot(dx, dy) > 3 else { return }
            mouseDownEvent = nil

            let origin = convert(down.locationInWindow, from: nil)
            let items = urls.enumerated().map { index, url -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 48, height: 48)
                let offset = CGFloat(min(index, 4)) * 6
                item.setDraggingFrame(NSRect(x: origin.x - 24 + offset, y: origin.y - 24 - offset, width: 48, height: 48),
                                      contents: icon)
                return item
            }
            onDragging?(true)
            let session = beginDraggingSession(with: items, event: down, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? .copy : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            onDragging?(false)
        }
    }
}
