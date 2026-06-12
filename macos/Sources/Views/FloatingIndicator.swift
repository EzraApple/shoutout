import AppKit
import SwiftUI

enum IndicatorState: Equatable, Sendable {
    case idle
    case armed
    case recording(level: Float)
    case processing
    case done(text: String)
    case attention(message: String)

    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }

    var showsBoomMic: Bool {
        switch self {
        case .armed, .recording:
            return true
        case .idle, .processing, .done, .attention:
            return false
        }
    }

    var recordingLevel: Float {
        if case .recording(let level) = self {
            return level
        }
        return showsBoomMic ? 0.22 : 0
    }

    var hasAttention: Bool {
        if case .attention = self {
            return true
        }
        return false
    }
}

enum CrabOverlayLayout {
    static let width: CGFloat = 72
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
            CrabOverlayView(state: state, height: crabHeight)
                .frame(width: CrabOverlayLayout.width, height: crabHeight)
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
                case .armed:
                    Circle()
                        .fill(.red.opacity(0.85))
                        .frame(width: 10, height: 10)
                        .scaleEffect(pulse ? 1.18 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                            value: pulse
                        )
                        .onAppear { pulse = true }
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
                case .attention:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .frame(width: 18)

            // Content
            switch state {
            case .idle:
                EmptyView()

            case .armed:
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.red.opacity(0.85))
                            .frame(width: 4, height: barHeight(for: i, level: 0.22))
                    }
                }
                .frame(height: 24)

                Text("Ready")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

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

            case .attention(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 15, weight: .semibold))

                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

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
    let height: CGFloat

    @State private var spriteFrameIndex = 0
    @State private var idleOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            SpriteWallCrab(
                showsBoomMic: state.showsBoomMic,
                frameIndex: spriteFrameIndex,
                attentionMessage: attentionMessage
            )
            .offset(y: idleOffset)
        }
        .frame(width: CrabOverlayLayout.width, height: height, alignment: .trailing)
        .task(id: state.showsBoomMic || state.isRecording) {
            await animate(in: height, active: state.showsBoomMic || state.isRecording)
        }
        .allowsHitTesting(false)
    }

    private var attentionMessage: String? {
        if case .attention(let message) = state {
            return message
        }
        return nil
    }

    private func animate(in height: CGFloat, active: Bool) async {
        if active {
            while !Task.isCancelled {
                spriteFrameIndex += 1
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            return
        }

        let maxOffset = max((height - 76) / 2, 18)
        var crawlDirection: CGFloat = Bool.random() ? -1 : 1
        while !Task.isCancelled {
            let steps = Int.random(in: 6...10)

            for _ in 0..<steps {
                if Task.isCancelled { return }

                let nextOffset = idleOffset + crawlDirection * CGFloat.random(in: 4...7)
                idleOffset = min(max(nextOffset, -maxOffset), maxOffset)
                spriteFrameIndex += 1

                if abs(idleOffset) >= maxOffset - 2 {
                    crawlDirection *= -1
                }

                try? await Task.sleep(nanoseconds: 140_000_000)
            }

            if Bool.random() {
                crawlDirection *= -1
            }
            try? await Task.sleep(nanoseconds: UInt64.random(in: 650_000_000...1_100_000_000))
        }
    }
}

private struct SpriteWallCrab: View {
    let showsBoomMic: Bool
    let frameIndex: Int
    let attentionMessage: String?

    @Environment(\.displayScale) private var displayScale
    @StateObject private var imageStore = CrabSpriteImageStore()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = currentImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .scaledToFit()
                    .frame(width: 54, height: 76, alignment: .trailing)
            }

            if let attentionMessage {
                attentionBadge
                    .help(attentionMessage)
            }
        }
        .frame(width: 54, height: 76, alignment: .trailing)
        .offset(x: showsBoomMic ? 2 : 0)
        .shadow(color: .black.opacity(0.22), radius: 1, x: -1 / max(displayScale, 1), y: 1)
    }

    private var attentionBadge: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 12, weight: .bold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.orange, Color.black.opacity(0.88))
            .background(Circle().fill(.white.opacity(0.86)).frame(width: 9, height: 9))
            .offset(x: -8, y: 8)
    }

    private var currentImage: NSImage? {
        let frames = showsBoomMic ? imageStore.boomMicFrames : imageStore.idleFrames
        guard !frames.isEmpty else { return nil }
        return frames[abs(frameIndex) % frames.count]
    }
}

@MainActor
private final class CrabSpriteImageStore: ObservableObject {
    let idleFrames: [NSImage]
    let boomMicFrames: [NSImage]

    init() {
        idleFrames = CrabSpriteAssets.idleFrameNames.compactMap(CrabSpriteAssets.image)
        boomMicFrames = CrabSpriteAssets.boomMicFrameNames.compactMap(CrabSpriteAssets.image)
    }
}

private enum CrabSpriteAssets {
    static let idleFrameNames = pingPongFrameNames(prefix: "idle", count: 4)
    static let boomMicFrameNames = pingPongFrameNames(prefix: "recording", count: 4)

    static func image(named name: String) -> NSImage? {
        guard
            let url = Bundle.main.url(
                forResource: name,
                withExtension: "png",
                subdirectory: "CrabSpritesWall"
            ),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        image.isTemplate = false
        return image
    }

    private static func frameNames(prefix: String, count: Int) -> [String] {
        (1...count).map { index in "\(prefix)-\(index)" }
    }

    private static func pingPongFrameNames(prefix: String, count: Int) -> [String] {
        let forwardFrames = frameNames(prefix: prefix, count: count)
        let returnFrames = (2..<count).reversed().map { index in "\(prefix)-\(index)" }
        return forwardFrames + returnFrames
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
