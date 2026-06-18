import AppKit
import SwiftUI

enum IndicatorState: Equatable, Sendable {
    case idle
    case armed
    case recording(level: Float, mode: IndicatorRecordingMode)
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
        if case .recording(let level, _) = self {
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

enum IndicatorRecordingMode: Equatable, Sendable {
    case hold
    case handsFree
}

enum CrabOverlayLayout {
    static let width: CGFloat = 72
}

private enum CrabAnimationTiming {
    static let idleFrameDelay: UInt64 = 180_000_000
    static let idlePauseRange: ClosedRange<UInt64> = 750_000_000...1_300_000_000
    static let processingPulseDelay: UInt64 = 540_000_000
    static let processingSpinDuration = 0.54
}

enum ClassicOverlayLayout {
    static let size = CGSize(width: 42, height: 146)
    static let screenEdgeInset: CGFloat = 2
}

enum OverlayStyle: String, Sendable {
    case crab
    case capsule
    case off
}

enum CrabColorVariant: String, CaseIterable, Identifiable, Sendable {
    case ocean
    case deepSea
    case cobalt
    case sky
    case aqua
    case teal
    case mint
    case emerald
    case lime
    case gold
    case amber
    case violet
    case lavender
    case grape
    case coral
    case rose
    case bubblegum
    case ember
    case black
    case graphite
    case pearl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ocean:
            return "Ocean Blue"
        case .deepSea:
            return "Deep Sea"
        case .cobalt:
            return "Cobalt"
        case .sky:
            return "Sky"
        case .aqua:
            return "Aqua"
        case .teal:
            return "Teal"
        case .mint:
            return "Mint"
        case .emerald:
            return "Emerald"
        case .lime:
            return "Lime"
        case .gold:
            return "Gold"
        case .amber:
            return "Amber"
        case .violet:
            return "Violet"
        case .lavender:
            return "Lavender"
        case .grape:
            return "Grape"
        case .coral:
            return "Coral"
        case .rose:
            return "Rose"
        case .bubblegum:
            return "Bubblegum"
        case .ember:
            return "Ember"
        case .black:
            return "Original Black"
        case .graphite:
            return "Graphite"
        case .pearl:
            return "Pearl"
        }
    }

    var hueRotation: Angle {
        switch self {
        case .ocean:
            return .degrees(0)
        case .deepSea:
            return .degrees(0)
        case .cobalt:
            return .degrees(10)
        case .sky:
            return .degrees(-14)
        case .aqua:
            return .degrees(-24)
        case .teal:
            return .degrees(-34)
        case .mint:
            return .degrees(-54)
        case .emerald:
            return .degrees(-74)
        case .lime:
            return .degrees(-96)
        case .gold:
            return .degrees(-128)
        case .amber:
            return .degrees(-150)
        case .violet:
            return .degrees(46)
        case .lavender:
            return .degrees(54)
        case .grape:
            return .degrees(68)
        case .coral:
            return .degrees(150)
        case .rose:
            return .degrees(118)
        case .bubblegum:
            return .degrees(96)
        case .ember:
            return .degrees(170)
        case .black, .graphite, .pearl:
            return .degrees(0)
        }
    }

    var saturation: Double {
        switch self {
        case .ocean, .cobalt, .aqua, .teal, .emerald, .lime, .gold, .amber, .violet,
            .grape, .coral, .rose, .bubblegum, .ember:
            return 1
        case .deepSea:
            return 1.08
        case .sky, .mint, .lavender:
            return 0.82
        case .black:
            return 0.20
        case .graphite:
            return 0.18
        case .pearl:
            return 0.12
        }
    }

    var brightness: Double {
        switch self {
        case .ocean, .cobalt, .aqua, .teal, .emerald, .lime, .gold, .amber, .violet,
            .grape, .rose, .bubblegum:
            return 0
        case .deepSea:
            return -0.14
        case .sky, .mint, .lavender, .pearl:
            return 0.08
        case .coral:
            return 0.02
        case .ember:
            return -0.06
        case .black:
            return -0.42
        case .graphite:
            return -0.04
        }
    }

    var swatchColor: Color {
        switch self {
        case .ocean:
            return Color(red: 0.13, green: 0.29, blue: 0.51)
        case .deepSea:
            return Color(red: 0.08, green: 0.21, blue: 0.39)
        case .cobalt:
            return Color(red: 0.13, green: 0.22, blue: 0.51)
        case .sky:
            return Color(red: 0.24, green: 0.45, blue: 0.58)
        case .aqua:
            return Color(red: 0.13, green: 0.42, blue: 0.49)
        case .teal:
            return Color(red: 0.13, green: 0.47, blue: 0.48)
        case .mint:
            return Color(red: 0.24, green: 0.58, blue: 0.48)
        case .emerald:
            return Color(red: 0.14, green: 0.51, blue: 0.27)
        case .lime:
            return Color(red: 0.16, green: 0.51, blue: 0.16)
        case .gold:
            return Color(red: 0.33, green: 0.50, blue: 0.13)
        case .amber:
            return Color(red: 0.45, green: 0.48, blue: 0.13)
        case .violet:
            return Color(red: 0.27, green: 0.14, blue: 0.51)
        case .lavender:
            return Color(red: 0.41, green: 0.24, blue: 0.58)
        case .grape:
            return Color(red: 0.40, green: 0.13, blue: 0.50)
        case .coral:
            return Color(red: 0.52, green: 0.20, blue: 0.16)
        case .rose:
            return Color(red: 0.51, green: 0.13, blue: 0.30)
        case .bubblegum:
            return Color(red: 0.49, green: 0.13, blue: 0.42)
        case .ember:
            return Color(red: 0.45, green: 0.26, blue: 0.12)
        case .black:
            return Color(red: 0.16, green: 0.16, blue: 0.17)
        case .graphite:
            return Color(red: 0.41, green: 0.43, blue: 0.47)
        case .pearl:
            return Color(red: 0.54, green: 0.56, blue: 0.58)
        }
    }
}

struct AppOverlayView: View {
    let style: OverlayStyle
    let state: IndicatorState
    let crabHeight: CGFloat
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?

    var body: some View {
        switch style {
        case .crab:
            CrabOverlayView(state: state, height: crabHeight)
                .frame(width: CrabOverlayLayout.width, height: crabHeight)
        case .capsule:
            ClassicIndicatorView(state: state, onCancel: onCancel, onCommit: onCommit)
                .frame(width: ClassicOverlayLayout.size.width, height: ClassicOverlayLayout.size.height)
        case .off:
            EmptyView()
                .frame(width: 1, height: 1)
        }
    }
}

@MainActor
final class IndicatorOverlayModel: ObservableObject {
    @Published var style: OverlayStyle
    @Published var state: IndicatorState
    @Published var crabHeight: CGFloat
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?

    init(
        style: OverlayStyle,
        state: IndicatorState,
        crabHeight: CGFloat,
        onCancel: (() -> Void)? = nil,
        onCommit: (() -> Void)? = nil
    ) {
        self.style = style
        self.state = state
        self.crabHeight = crabHeight
        self.onCancel = onCancel
        self.onCommit = onCommit
    }

    func update(
        style: OverlayStyle,
        state: IndicatorState,
        crabHeight: CGFloat,
        onCancel: (() -> Void)?,
        onCommit: (() -> Void)?
    ) {
        self.style = style
        self.state = state
        self.crabHeight = crabHeight
        self.onCancel = onCancel
        self.onCommit = onCommit
    }
}

struct IndicatorOverlayHostView: View {
    @ObservedObject var model: IndicatorOverlayModel

    var body: some View {
        AppOverlayView(
            style: model.style,
            state: model.state,
            crabHeight: model.crabHeight,
            onCancel: model.onCancel,
            onCommit: model.onCommit
        )
    }
}

struct ClassicIndicatorView: View {
    let state: IndicatorState
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedSpeechLevel: CGFloat = 0
    @State private var processingRotation = 0.0

    var body: some View {
        ZStack(alignment: .trailing) {
            classicGlass
            statusContent
                .frame(width: surfaceSize.width, height: surfaceSize.height)
                .id(visualKind)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
        .frame(
            width: ClassicOverlayLayout.size.width,
            height: ClassicOverlayLayout.size.height,
            alignment: .trailing
        )
        .help(accessibilityLabel)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: visualKind)
        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: surfaceSize)
        .onAppear {
            syncDisplayedSpeechLevel(animated: false)
        }
        .onChange(of: recordingTargetSpeechLevel) { _, _ in
            syncDisplayedSpeechLevel(animated: true)
        }
        .onChange(of: visualKind) { _, _ in
            syncDisplayedSpeechLevel(animated: true)
        }
        .task(id: state.isProcessing) {
            await animateProcessingRing()
        }
    }

    private var classicGlass: some View {
        RoundedRectangle(cornerRadius: surfaceSize.width / 2, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: surfaceSize.width / 2, style: .continuous)
                    .fill(Color.black.opacity(0.42))
            }
            .overlay {
                RoundedRectangle(cornerRadius: surfaceSize.width / 2, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.24), radius: 14, y: 6)
            .frame(width: surfaceSize.width, height: surfaceSize.height)
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state {
        case .idle:
            EmptyView()
        case .armed:
            recordingContent(mode: .hold)
        case .recording(_, let mode):
            recordingContent(mode: mode)
        case .processing:
            processingRing
        case .done:
            statusIcon(symbol: "checkmark", tint: .green.opacity(0.92))
        case .attention:
            statusIcon(symbol: "exclamationmark", tint: Color(red: 0.92, green: 0.42, blue: 0.08))
        }
    }

    private func recordingContent(mode: IndicatorRecordingMode) -> some View {
        VStack(spacing: mode == .handsFree ? 8 : 0) {
            if mode == .handsFree {
                overlayActionButton(symbol: "xmark", tint: .white.opacity(0.88), action: onCancel)
            }

            recordingBars(speechLevel: displayedSpeechLevel)

            if mode == .handsFree {
                overlayActionButton(symbol: "checkmark", tint: .white.opacity(0.9), action: onCommit)
            }
        }
        .frame(width: surfaceSize.width, height: surfaceSize.height)
    }

    private func recordingBars(speechLevel: CGFloat) -> some View {
        VStack(spacing: 3) {
            ForEach(0..<9, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.84))
                    .frame(width: recordingBarWidth(for: index, speechLevel: speechLevel), height: 3)
                    .animation(.easeOut(duration: 0.12), value: speechLevel)
            }
        }
        .frame(width: 24, height: 58)
    }

    private func recordingBarWidth(for index: Int, speechLevel: CGFloat) -> CGFloat {
        let basePattern: [CGFloat] = [4, 8, 6, 10, 7, 9, 4, 8, 5]
        let responsePattern: [CGFloat] = [0.48, 0.92, 0.62, 1.00, 0.72, 0.86, 0.44, 0.78, 0.58]
        let base = basePattern[index % basePattern.count]
        let gain = min(max(speechLevel, 0), 1)
        let response = responsePattern[index % responsePattern.count]
        let levelTexture = sin(CGFloat(index) * 1.73 + gain * 5.4) * (1.1 + gain * 1.1)
        return min(max(base + gain * (4 + response * 14) + levelTexture, 3), 27)
    }

    private var recordingTargetSpeechLevel: CGFloat {
        if case .recording(let level, _) = state {
            return visualSpeechLevel(from: level)
        }
        return 0
    }

    private func syncDisplayedSpeechLevel(animated: Bool) {
        let target = recordingTargetSpeechLevel
        let duration = target > displayedSpeechLevel ? 0.14 : 0.28
        let update = {
            displayedSpeechLevel = target
        }

        if animated, !reduceMotion {
            withAnimation(.easeOut(duration: duration)) {
                update()
            }
        } else {
            update()
        }
    }

    private func visualSpeechLevel(from level: Float) -> CGFloat {
        let clampedLevel = min(max(CGFloat(level), 0), 1)
        let noiseFloor: CGFloat = 0.006
        let speechCeiling: CGFloat = 0.30

        let normalized = min(max((clampedLevel - noiseFloor) / (speechCeiling - noiseFloor), 0), 1)
        return pow(normalized, 0.88)
    }

    private func statusIcon(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(tint)
    }

    private var processingRing: some View {
        Circle()
            .trim(from: 0.16, to: 0.86)
            .stroke(
                Color.white.opacity(0.88),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
            )
            .frame(width: 17, height: 17)
            .rotationEffect(.degrees(processingRotation))
            .animation(
                .linear(duration: CrabAnimationTiming.processingSpinDuration),
                value: processingRotation
            )
    }

    private func animateProcessingRing() async {
        processingRotation = 0
        guard state.isProcessing, !reduceMotion else {
            return
        }

        while !Task.isCancelled {
            processingRotation += 360
            try? await Task.sleep(nanoseconds: CrabAnimationTiming.processingPulseDelay)
        }
    }

    private func overlayActionButton(
        symbol: String,
        tint: Color,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private var surfaceSize: CGSize {
        switch state {
        case .idle:
            return CGSize(width: 14, height: 44)
        case .armed:
            return CGSize(width: 34, height: 86)
        case .recording(_, .hold):
            return CGSize(width: 34, height: 86)
        case .recording(_, .handsFree):
            return CGSize(width: 34, height: 132)
        case .processing, .done, .attention:
            return CGSize(width: 34, height: 48)
        }
    }

    private var visualKind: String {
        switch state {
        case .idle:
            return "idle"
        case .armed:
            return "recording-hold"
        case .recording(_, let mode):
            return "recording-\(mode)"
        case .processing:
            return "processing"
        case .done:
            return "done"
        case .attention:
            return "attention"
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle:
            return "ShoutOut"
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
    @State private var processingRotation = 0.0

    var body: some View {
        ZStack(alignment: .trailing) {
            SpriteWallCrab(
                showsBoomMic: state.showsBoomMic,
                frameIndex: spriteFrameIndex,
                showsProcessing: state.isProcessing,
                processingRotation: processingRotation,
                attentionMessage: attentionMessage
            )
            .offset(y: idleOffset)
        }
        .frame(width: CrabOverlayLayout.width, height: height, alignment: .trailing)
        .task(id: "\(state.showsBoomMic)-\(reduceMotion)") {
            await animateCrab()
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

    private func animateCrab() async {
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
            let stepCount = Int.random(in: 5...9)

            for _ in 0..<stepCount {
                if Task.isCancelled { return }

                let nextOffset = idleOffset + crawlDirection * CGFloat.random(in: 3...6)
                idleOffset = min(max(nextOffset, -maxOffset), maxOffset)
                spriteFrameIndex += 1

                if abs(idleOffset) >= maxOffset - 2 {
                    crawlDirection *= -1
                }

                try? await Task.sleep(nanoseconds: CrabAnimationTiming.idleFrameDelay)
            }

            if Bool.random() {
                crawlDirection *= -1
            }
            try? await Task.sleep(nanoseconds: UInt64.random(in: CrabAnimationTiming.idlePauseRange))
        }
    }

    private func animateProcessingBadge() async {
        processingRotation = 0
        guard state.isProcessing, !reduceMotion else {
            return
        }

        while !Task.isCancelled {
            processingRotation += 360
            try? await Task.sleep(nanoseconds: CrabAnimationTiming.processingPulseDelay)
        }
    }
}

private struct SpriteWallCrab: View {
    let showsBoomMic: Bool
    let frameIndex: Int
    let showsProcessing: Bool
    let processingRotation: Double
    let attentionMessage: String?

    @Environment(\.displayScale) private var displayScale
    @AppStorage(Defaults.crabColorVariant) private var crabColorVariant = CrabColorVariant.ocean.rawValue

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = currentImage {
                spriteImage(image)
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
        .offset(x: wallContactOffset)
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
            .rotationEffect(.degrees(processingRotation))
            .background(
                Circle()
                    .fill(Color.black.opacity(0.68))
                    .frame(width: 17, height: 17)
            )
            .animation(
                .linear(duration: CrabAnimationTiming.processingSpinDuration),
                value: processingRotation
            )
            .offset(x: -8, y: 8)
    }

    private var currentImage: NSImage? {
        let frames = showsBoomMic ? CrabSpriteAssets.boomMicFrameNames : CrabSpriteAssets.idleFrameNames
        guard !frames.isEmpty else { return nil }
        let frameName = frames[abs(frameIndex) % frames.count]
        return CrabSpriteAssets.image(named: frameName, variant: colorVariant)
    }

    private var boomScale: CGFloat {
        1
    }

    private var wallContactOffset: CGFloat {
        0.5
    }

    private var colorVariant: CrabColorVariant {
        CrabColorVariant(rawValue: crabColorVariant) ?? .ocean
    }

    private func spriteImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.none)
            .antialiased(false)
            .scaleEffect(boomScale, anchor: .trailing)
            .scaledToFit()
            .frame(width: 54, height: 76, alignment: .trailing)
    }
}

private enum CrabSpriteAssets {
    static let idleFrameNames = pingPongFrameNames(prefix: "idle", count: 4)
    static let boomMicFrameNames = ["recording-2"]

    static func image(named name: String, variant: CrabColorVariant) -> NSImage? {
        image(named: name, subdirectory: "CrabSpriteWallVariants/\(variant.rawValue)")
            ?? image(named: name, subdirectory: "CrabSpritesWall")
    }

    private static func image(named name: String, subdirectory: String) -> NSImage? {
        guard
            let url = Bundle.main.url(
                forResource: name,
                withExtension: "png",
                subdirectory: subdirectory
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
