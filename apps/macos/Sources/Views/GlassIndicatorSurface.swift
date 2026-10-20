import SwiftUI

struct GlassIndicatorSurface: View {
    let size: CGSize
    let accent: Color
    let isProcessing: Bool
    let reduceMotion: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        glassSurface
            .overlay {
                Capsule(style: .circular).stroke(.white.opacity(0.16), lineWidth: 0.6)
            }
            .overlay {
                if isProcessing {
                    GlassLoadingBorder(accent: accent, reduceMotion: reduceMotion)
                }
            }
    }

    @ViewBuilder
    private var glassSurface: some View {
        if reduceTransparency {
            Capsule(style: .circular)
                .fill(Color(white: 0.075))
                .frame(width: size.width, height: size.height)
        } else if #available(macOS 26.0, *) {
            Color.clear
                .frame(width: size.width, height: size.height)
                .glassEffect(.regular, in: Capsule(style: .circular))
                .environment(\.colorScheme, .dark)
        } else {
            Capsule(style: .circular)
                .fill(.ultraThinMaterial)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
        }
    }
}

private struct GlassLoadingBorder: View {
    let accent: Color
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let time = ProcessInfo.processInfo.systemUptime + timeline.date.timeIntervalSinceNow
            let phase = reduceMotion ? 0.18 : time.truncatingRemainder(dividingBy: 1.15) / 1.15
            let angle = phase * 2 * Double.pi - Double.pi / 2
            Canvas { context, size in
                let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
                let path = Capsule(style: .circular).path(in: bounds)
                let gradient = Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.68),
                    .init(color: accent.opacity(0.06), location: 0.728),
                    .init(color: accent.opacity(0.32), location: 0.84),
                    .init(color: accent.opacity(0.78), location: 0.952),
                    .init(color: .white.opacity(0.98), location: 1),
                ])
                let center = CGPoint(x: bounds.midX, y: bounds.midY)
                let shading = GraphicsContext.Shading.conicGradient(gradient, center: center, angle: .radians(angle))
                var glow = context
                glow.opacity = 0.18
                glow.addFilter(.blur(radius: 0.65))
                glow.stroke(path, with: shading, lineWidth: 2.4)
                context.stroke(path, with: shading, lineWidth: 1.25)
                let tip = capsuleEdgePoint(at: angle, in: bounds)
                context.fill(
                    Path(ellipseIn: CGRect(x: tip.x - 0.85, y: tip.y - 0.85, width: 1.7, height: 1.7)),
                    with: .color(.white.opacity(0.98))
                )
            }
            .padding(-3)
        }
        .allowsHitTesting(false)
    }
}

private func capsuleEdgePoint(at angle: Double, in bounds: CGRect) -> CGPoint {
    let radius = bounds.width / 2
    let straightHalf = max(0, (bounds.height - bounds.width) / 2)
    let x = CGFloat(cos(angle))
    let y = CGFloat(sin(angle))
    let sideDistance = radius / max(abs(x), 0.0001)
    let distance: CGFloat
    if abs(sideDistance * y) <= straightHalf {
        distance = sideDistance
    } else {
        distance = abs(y) * straightHalf + sqrt(max(0, radius * radius - straightHalf * straightHalf * x * x))
    }
    return CGPoint(x: bounds.midX + distance * x, y: bounds.midY + distance * y)
}

