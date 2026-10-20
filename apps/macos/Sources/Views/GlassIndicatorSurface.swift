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
                    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
                        let time = ProcessInfo.processInfo.systemUptime + timeline.date.timeIntervalSinceNow
                        let phase = reduceMotion ? 0 : time.truncatingRemainder(dividingBy: 1.15) / 1.15
                        Canvas { context, size in
                            let path = Capsule(style: .circular).path(in: CGRect(origin: .zero, size: size).insetBy(dx: 0.8, dy: 0.8))
                            let style = StrokeStyle(lineWidth: 1.4, lineCap: .round)
                            context.stroke(path.trimmedPath(from: phase, to: min(phase + 0.24, 1)), with: .color(accent), style: style)
                            if phase + 0.24 > 1 {
                                context.stroke(path.trimmedPath(from: 0, to: phase + 0.24 - 1), with: .color(accent), style: style)
                            }
                        }
                    }
                    .allowsHitTesting(false)
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

