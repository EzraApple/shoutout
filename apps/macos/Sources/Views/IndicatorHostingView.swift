import AppKit
import SwiftUI

final class IndicatorHostingView: NSHostingView<IndicatorOverlayHostView> {
    private var mouseDownPoint: CGPoint?
    private var startedDrag = false
    var dragRect = CGRect.zero {
        didSet {
            if oldValue != dragRect { window?.invalidateCursorRects(for: self) }
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if rootView.model.style == .crab, dragRect.contains(convert(point, from: superview)) {
            return self
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard rootView.model.style == .crab, let window else {
            super.mouseDown(with: event)
            return
        }
        mouseDownPoint = window.convertPoint(toScreen: event.locationInWindow)
        startedDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownPoint, let window else {
            super.mouseDragged(with: event)
            return
        }
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        let translation = CGSize(width: pointer.x - mouseDownPoint.x, height: mouseDownPoint.y - pointer.y)
        guard startedDrag || hypot(translation.width, translation.height) >= 3 else { return }
        startedDrag = true
        rootView.model.onDragChanged?(convert(event.locationInWindow, from: nil), translation)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownPoint != nil else {
            super.mouseUp(with: event)
            return
        }
        if startedDrag {
            mouseDragged(with: event)
            rootView.model.onDragEnded?()
        }
        mouseDownPoint = nil
        startedDrag = false
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(dragRect, cursor: .openHand)
    }
}

func getIndicatorHitFrame(for surface: CGRect, style: OverlayStyle, anchor: IndicatorAnchor, in bounds: CGRect) -> CGRect {
    guard style != .off, !surface.isEmpty, surface.intersects(bounds) else { return .zero }
    let padding: CGSize
    if style == .crab {
        padding = CGSize(width: 8, height: 8)
    } else {
        let minimum = anchor.isHorizontal ? CGSize(width: 48, height: 32) : CGSize(width: 32, height: 48)
        padding = CGSize(width: max(6, (minimum.width - surface.width) / 2),
                         height: max(6, (minimum.height - surface.height) / 2))
    }
    let expanded = surface.insetBy(dx: -padding.width, dy: -padding.height)
    let size = CGSize(width: min(expanded.width, bounds.width), height: min(expanded.height, bounds.height))
    return CGRect(x: min(max(expanded.minX, bounds.minX), bounds.maxX - size.width),
                  y: min(max(expanded.minY, bounds.minY), bounds.maxY - size.height),
                  width: size.width, height: size.height)
}
