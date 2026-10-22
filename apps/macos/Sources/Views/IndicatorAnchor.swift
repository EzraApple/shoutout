import AppKit

enum IndicatorAnchor: String, CaseIterable, Sendable {
    case left, right, top, bottom

    var isHorizontal: Bool { self == .top || self == .bottom }

    static func allowed(for style: OverlayStyle) -> [Self] {
        switch style {
        case .crab: [.left, .right]
        case .capsule, .glass: allCases
        case .off: []
        }
    }

    func frame(in visibleFrame: CGRect, style: OverlayStyle, crabHeight: CGFloat) -> CGRect {
        if style == .crab {
            return CGRect(
                x: self == .left ? visibleFrame.minX - CrabOverlayLayout.screenBleed
                    : visibleFrame.maxX - CrabOverlayLayout.width + CrabOverlayLayout.screenBleed,
                y: visibleFrame.midY - crabHeight / 2 + CrabOverlayLayout.verticalOffset,
                width: CrabOverlayLayout.width, height: crabHeight
            )
        }
        let size = isHorizontal
            ? CGSize(width: PillOverlayLayout.size.height, height: PillOverlayLayout.size.width)
            : PillOverlayLayout.size
        let inset = PillOverlayLayout.panelScreenInset
        var frame = CGRect(x: visibleFrame.midX - size.width / 2,
                           y: visibleFrame.midY - size.height / 2,
                           width: size.width, height: size.height)
        switch self {
        case .left: frame.origin.x = visibleFrame.minX + inset
        case .right: frame.origin.x = visibleFrame.maxX - size.width - inset
        case .top: frame.origin.y = visibleFrame.maxY - size.height - inset
        case .bottom: frame.origin.y = visibleFrame.minY + inset
        }
        return frame
    }

    func targetFrame(in visibleFrame: CGRect) -> CGRect {
        let size = isHorizontal ? CGSize(width: 144, height: 88) : CGSize(width: 88, height: 144)
        var frame = CGRect(x: visibleFrame.midX - size.width / 2,
                           y: visibleFrame.midY - size.height / 2,
                           width: size.width, height: size.height)
        switch self {
        case .left: frame.origin.x = visibleFrame.minX + 12
        case .right: frame.origin.x = visibleFrame.maxX - size.width - 12
        case .top: frame.origin.y = visibleFrame.maxY - size.height - 12
        case .bottom: frame.origin.y = visibleFrame.minY + 12
        }
        return frame
    }

    static func dropTarget(at point: CGPoint, in visibleFrame: CGRect, style: OverlayStyle) -> Self? {
        // A sideways drag should still land when the Crab has crawled above or below the target.
        let verticalAllowance: CGFloat = style == .crab ? 72 : 24
        return allowed(for: style).first {
            $0.targetFrame(in: visibleFrame).insetBy(dx: -24, dy: -verticalAllowance).contains(point)
        }
    }
}
