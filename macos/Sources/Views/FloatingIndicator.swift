import SwiftUI

enum IndicatorState: Equatable, Sendable {
    case idle
    case recording(level: Float)
    case processing
    case done(text: String)

    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }
}

enum OverlayStyle: String, Sendable {
    case crab
    case capsule
    case off
}

struct AppOverlayView: View {
    let style: OverlayStyle
    let state: IndicatorState
    let crabHeight: CGFloat

    var body: some View {
        switch style {
        case .crab:
            CrabOverlayView(state: state)
                .frame(width: 112, height: crabHeight)
        case .capsule:
            if state == .idle {
                EmptyView()
                    .frame(width: 1, height: 1)
            } else {
                FloatingIndicatorView(state: state)
            }
        case .off:
            EmptyView()
                .frame(width: 1, height: 1)
        }
    }
}

struct FloatingIndicatorView: View {
    let state: IndicatorState
    @State private var animatingDots = false
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            // Left icon
            Group {
                switch state {
                case .idle:
                    EmptyView()
                case .recording:
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                        .scaleEffect(pulse ? 1.3 : 1.0)
                        .opacity(pulse ? 0.7 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                            value: pulse
                        )
                        .onAppear { pulse = true }
                case .processing:
                    ProgressView()
                        .controlSize(.small)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 16))
                }
            }
            .frame(width: 18)

            // Content
            switch state {
            case .idle:
                EmptyView()

            case .recording(let level):
                // Waveform bars
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.primary.opacity(0.9))
                            .frame(width: 4, height: barHeight(for: i, level: level))
                            .animation(.easeOut(duration: 0.08), value: level)
                    }
                }
                .frame(height: 24)

                Text("Listening...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

            case .processing:
                Text("Transcribing")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(.primary.opacity(0.6))
                            .frame(width: 4, height: 4)
                            .offset(y: animatingDots ? -3 : 3)
                            .animation(
                                .easeInOut(duration: 0.4)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.15),
                                value: animatingDots
                            )
                    }
                }
                .onAppear { animatingDots = true }

            case .done(let text):
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 340)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .modifier(GlassCapsuleModifier())
    }

    private func barHeight(for index: Int, level: Float) -> CGFloat {
        let base: CGFloat = 5
        let maxExtra: CGFloat = 19
        // Amplify the level so even quiet speech shows movement
        let amplified = min(pow(level, 0.5) * 1.5, 1.0)
        // Each bar has a different phase for a wave-like look
        let phase = Double(index) * 1.2 + Double(amplified) * 12.0
        let wave = (sin(phase) + 1) / 2  // 0...1
        // Even at zero level, bars should jitter slightly when recording
        let jitter: CGFloat = index % 2 == 0 ? 2 : 0
        return base + jitter + maxExtra * CGFloat(amplified) * wave
    }
}

private struct CrabOverlayView: View {
    let state: IndicatorState

    @State private var walkFrame = false
    @State private var idleOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            PixelCrab(isRecording: state.isRecording, walkFrame: walkFrame)
                .offset(y: state.isRecording ? 0 : idleOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .task(id: state.isRecording) {
                    await animate(in: geometry.size.height)
                }
        }
        .allowsHitTesting(false)
    }

    private func animate(in height: CGFloat) async {
        if state.isRecording {
            withAnimation(.easeOut(duration: 0.2)) {
                idleOffset = 0
                walkFrame = false
            }
            return
        }

        let maxOffset = max((height - 92) / 2, 18)
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: Double.random(in: 2.8...5.2))) {
                idleOffset = CGFloat.random(in: -maxOffset...maxOffset)
            }
            withAnimation(.linear(duration: 0.18)) {
                walkFrame.toggle()
            }
            try? await Task.sleep(nanoseconds: UInt64.random(in: 900_000_000...1_600_000_000))
        }
    }
}

private struct PixelCrab: View {
    let isRecording: Bool
    let walkFrame: Bool

    private let unit: CGFloat = 4

    var body: some View {
        ZStack(alignment: .topLeading) {
            bodyPixels
            legs
            claws
            headphones
            if isRecording {
                boomMic
            }
            eyes
        }
        .frame(width: 84, height: 72)
        .shadow(color: .white.opacity(0.65), radius: 0, x: 1, y: 0)
        .shadow(color: .white.opacity(0.65), radius: 0, x: -1, y: 0)
        .shadow(color: .white.opacity(0.65), radius: 0, x: 0, y: 1)
        .shadow(color: .white.opacity(0.65), radius: 0, x: 0, y: -1)
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }

    private var bodyPixels: some View {
        Group {
            pixel(x: 5, y: 5, w: 9, h: 1, color: .black)
            pixel(x: 4, y: 6, w: 11, h: 5, color: Color(white: 0.05))
            pixel(x: 5, y: 11, w: 9, h: 1, color: Color(white: 0.02))
            pixel(x: 6, y: 7, w: 7, h: 3, color: Color(white: 0.12))
        }
    }

    private var eyes: some View {
        Group {
            pixel(x: 7, y: 4, w: 1, h: 2, color: .white)
            pixel(x: 11, y: 4, w: 1, h: 2, color: .white)
            pixel(x: 7, y: 4, w: 1, h: 1, color: .black)
            pixel(x: 11, y: 4, w: 1, h: 1, color: .black)
        }
    }

    private var headphones: some View {
        Group {
            pixel(x: 5, y: 3, w: 9, h: 1, color: Color(white: 0.45))
            pixel(x: 4, y: 4, w: 2, h: 3, color: Color(white: 0.22))
            pixel(x: 13, y: 4, w: 2, h: 3, color: Color(white: 0.22))
            pixel(x: 5, y: 5, w: 1, h: 2, color: Color(red: 0.18, green: 0.30, blue: 0.36))
            pixel(x: 13, y: 5, w: 1, h: 2, color: Color(red: 0.18, green: 0.30, blue: 0.36))
        }
    }

    private var claws: some View {
        Group {
            pixel(x: 1, y: 6, w: 3, h: 1, color: .black)
            pixel(x: 0, y: 5, w: 2, h: 1, color: .black)
            pixel(x: 0, y: 7, w: 2, h: 1, color: .black)
            pixel(x: 15, y: 6, w: 3, h: 1, color: .black)
            pixel(x: 17, y: 5, w: 2, h: 1, color: .black)
            pixel(x: 17, y: 7, w: 2, h: 1, color: .black)
        }
    }

    private var legs: some View {
        let firstLegShift = walkFrame ? 1 : 0
        let secondLegShift = walkFrame ? 0 : 1

        return Group {
            pixel(x: 4, y: 12 + firstLegShift, w: 2, h: 1, color: .black)
            pixel(x: 7, y: 12 + secondLegShift, w: 2, h: 1, color: .black)
            pixel(x: 10, y: 12 + firstLegShift, w: 2, h: 1, color: .black)
            pixel(x: 13, y: 12 + secondLegShift, w: 2, h: 1, color: .black)
            pixel(x: 3, y: 13 + firstLegShift, w: 1, h: 1, color: .black)
            pixel(x: 15, y: 13 + secondLegShift, w: 1, h: 1, color: .black)
        }
    }

    private var boomMic: some View {
        Group {
            pixel(x: 14, y: 6, w: 4, h: 1, color: Color(white: 0.55))
            pixel(x: 18, y: 7, w: 1, h: 2, color: Color(white: 0.55))
            pixel(x: 18, y: 9, w: 3, h: 1, color: .black)
            pixel(x: 20, y: 8, w: 1, h: 3, color: .black)
        }
    }

    private func pixel(x: Int, y: Int, w: Int, h: Int, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: CGFloat(w) * unit, height: CGFloat(h) * unit)
            .offset(x: CGFloat(x) * unit, y: CGFloat(y) * unit)
    }
}

// MARK: - Liquid Glass with fallback

private struct GlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            }
    }
}
