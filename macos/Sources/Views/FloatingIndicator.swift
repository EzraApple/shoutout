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

    var isProcessing: Bool {
        if case .processing = self {
            return true
        }
        return false
    }
}

enum CrabOverlayLayout {
    static let width: CGFloat = 72
}

enum ClassicOverlayLayout {
    static let size = CGSize(width: 48, height: 48)
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
                ClassicIndicatorView(state: state)
                    .frame(width: ClassicOverlayLayout.size.width, height: ClassicOverlayLayout.size.height)
            }
        case .off:
            EmptyView()
                .frame(width: 1, height: 1)
        }
    }
}

struct ClassicIndicatorView: View {
    let state: IndicatorState
    @State private var pulse = false

    var body: some View {
        ZStack {
            classicGlass
            statusContent
        }
        .frame(width: ClassicOverlayLayout.size.width, height: ClassicOverlayLayout.size.height)
        .help(accessibilityLabel)
        .onAppear { pulse = true }
    }

    private var classicGlass: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.42))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state {
        case .idle:
            EmptyView()
        case .armed:
            Image(systemName: "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
        case .recording(let level):
            recordingBars(level: level)
        case .processing:
            ProgressView()
                .controlSize(.small)
                .tint(.white.opacity(0.95))
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.green.opacity(0.95))
        case .attention:
            Image(systemName: "exclamationmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.orange.opacity(0.95))
        }
    }

    private func recordingBars(level: Float) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 3, height: recordingBarHeight(for: index, level: level))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .frame(width: 24, height: 22)
    }

    private func recordingBarHeight(for index: Int, level: Float) -> CGFloat {
        let amplifiedLevel = min(max(CGFloat(level), 0.12) * 1.8, 1)
        let phase = CGFloat(index) * 0.7
        return 7 + (12 * amplifiedLevel * ((sin(phase + amplifiedLevel * 3) + 1) / 2))
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle:
            return "Shout Out"
        case .armed:
            return "Ready to record"
        case .recording:
            return "Recording"
        case .processing:
            return "Transcribing"
        case .done:
            return "Inserted"
        case .attention(let message):
            return message
        }
    }
}

private struct CrabOverlayView: View {
    let state: IndicatorState
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spriteFrameIndex = 0
    @State private var idleOffset: CGFloat = 0
    @State private var processingPulse = false

    var body: some View {
        ZStack(alignment: .trailing) {
            SpriteWallCrab(
                showsBoomMic: state.showsBoomMic,
                frameIndex: spriteFrameIndex,
                showsProcessing: state.isProcessing,
                processingPulse: processingPulse,
                attentionMessage: attentionMessage
            )
            .offset(y: idleOffset)
        }
        .frame(width: CrabOverlayLayout.width, height: height, alignment: .trailing)
        .task(id: "\(state.showsBoomMic)-\(reduceMotion)") {
            await animateIdleCrawl()
        }
        .task(id: state.isProcessing) {
            await animateProcessingBadge()
        }
        .allowsHitTesting(false)
    }

    private var attentionMessage: String? {
        if case .attention(let message) = state {
            return message
        }
        return nil
    }

    private func animateIdleCrawl() async {
        if reduceMotion {
            idleOffset = 0
            spriteFrameIndex = 0
            return
        }

        if state.showsBoomMic {
            spriteFrameIndex = 0
            return
        }

        let maxOffset = max((height - 76) / 2, 18)
        var crawlDirection: CGFloat = Bool.random() ? -1 : 1

        while !Task.isCancelled {
            let stepCount = Int.random(in: 4...8)

            for _ in 0..<stepCount {
                if Task.isCancelled { return }

                let nextOffset = idleOffset + crawlDirection * CGFloat.random(in: 3...6)
                idleOffset = min(max(nextOffset, -maxOffset), maxOffset)
                spriteFrameIndex += 1

                if abs(idleOffset) >= maxOffset - 2 {
                    crawlDirection *= -1
                }

                try? await Task.sleep(nanoseconds: 150_000_000)
            }

            if Bool.random() {
                crawlDirection *= -1
            }
            try? await Task.sleep(nanoseconds: UInt64.random(in: 650_000_000...1_100_000_000))
        }
    }

    private func animateProcessingBadge() async {
        processingPulse = false
        guard state.isProcessing, !reduceMotion else {
            return
        }

        while !Task.isCancelled {
            processingPulse.toggle()
            try? await Task.sleep(nanoseconds: 450_000_000)
        }
    }
}

private struct SpriteWallCrab: View {
    let showsBoomMic: Bool
    let frameIndex: Int
    let showsProcessing: Bool
    let processingPulse: Bool
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
                    .scaleEffect(boomScale, anchor: .trailing)
            }

            if let attentionMessage {
                attentionBadge
                    .help(attentionMessage)
            } else if showsProcessing {
                processingBadge
                    .help("Transcribing")
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

    private var processingBadge: some View {
        Circle()
            .trim(from: 0.16, to: 0.86)
            .stroke(
                Color.white.opacity(0.92),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
            )
            .frame(width: 13, height: 13)
            .rotationEffect(.degrees(processingPulse ? 360 : 0))
            .background(
                Circle()
                    .fill(Color.black.opacity(0.68))
                    .frame(width: 17, height: 17)
            )
            .animation(.linear(duration: 0.45), value: processingPulse)
            .offset(x: -8, y: 8)
    }

    private var currentImage: NSImage? {
        let frames = showsBoomMic ? imageStore.boomMicFrames : imageStore.idleFrames
        guard !frames.isEmpty else { return nil }
        if showsBoomMic {
            return frames[0]
        }
        return frames[abs(frameIndex) % frames.count]
    }

    private var boomScale: CGFloat {
        showsBoomMic ? 1.15 : 1
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
