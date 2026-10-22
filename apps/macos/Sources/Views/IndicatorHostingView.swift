import AppKit
import SwiftUI

final class IndicatorHostingView: NSHostingView<IndicatorOverlayHostView> {
    var dragRect = CGRect.zero {
        didSet {
            if oldValue != dragRect { window?.invalidateCursorRects(for: self) }
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
