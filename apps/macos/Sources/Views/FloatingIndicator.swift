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
    static let screenBleed: CGFloat = 4
    static let verticalOffset: CGFloat = 18
}

private enum CrabAnimationTiming {
    static let idleFrameDelay: UInt64 = 130_000_000
    static let idleStepDuration = 0.13
    static let idlePauseRange: ClosedRange<UInt64> = 520_000_000...880_000_000
    static let boomIntroFrameDelay: UInt64 = 68_000_000
    static let boomOutroFrameDelay: UInt64 = 46_000_000
    static let processingPulseDelay: UInt64 = 540_000_000
    static let processingSpinDuration = 0.54
}

enum PillOverlayLayout {
    static let size = CGSize(width: 34, height: 116)
    static let screenEdgeInset: CGFloat = 4
}

enum OverlayStyle: String, Sendable {
    case crab
    case capsule
    case glass
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
        case .capsule, .glass:
            PillIndicatorView(style: style, state: state, onCancel: onCancel, onCommit: onCommit)
                .frame(width: PillOverlayLayout.size.width, height: PillOverlayLayout.size.height)
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
#if DEBUG
    @Published var previewReduceMotion: Bool?
#endif
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
#if DEBUG
        .environment(\.classicPreviewReduceMotion, model.previewReduceMotion)
#endif
    }
}

#if DEBUG
private struct ClassicPreviewReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var classicPreviewReduceMotion: Bool? {
        get { self[ClassicPreviewReduceMotionKey.self] }
        set { self[ClassicPreviewReduceMotionKey.self] = newValue }
    }
}
#endif

struct PillIndicatorView: View {
    let style: OverlayStyle
    let state: IndicatorState
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?
    @AppStorage(Defaults.crabColorVariant) private var crabColorVariant = CrabColorVariant.ocean.rawValue
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
#if DEBUG
    @Environment(\.classicPreviewReduceMotion) private var previewReduceMotion
#endif
    @State private var recordingWaveform = ClassicWaveform()

    private var reduceMotion: Bool {
#if DEBUG
        if let previewReduceMotion { return previewReduceMotion }
#endif
        return systemReduceMotion
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            classicSurface
            statusContent
                .frame(width: surfaceSize.width, height: surfaceSize.height)
                .id(visualKind)
                .transition(.opacity)
        }
        .frame(
            width: PillOverlayLayout.size.width,
            height: PillOverlayLayout.size.height,
            alignment: .trailing
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: visualKind)
        .animation(
            reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.16),
            value: surfaceSize
        )
        .onAppear {
            recordingWaveform.recordLevel(recordingTargetLevel, at: ProcessInfo.processInfo.systemUptime)
        }
        .onChange(of: recordingTargetLevel) { _, level in
            recordingWaveform.recordLevel(level, at: ProcessInfo.processInfo.systemUptime)
        }
        .onChange(of: state.isRecording) { _, isRecording in
            if !isRecording { recordingWaveform = ClassicWaveform() }
        }
        .transaction { transaction in
            if reduceMotion { transaction.disablesAnimations = true }
        }
    }

    @ViewBuilder
    private var classicSurface: some View {
        if style == .glass {
            GlassIndicatorSurface(
                size: surfaceSize,
                accent: recordingAccent,
                isProcessing: state.isProcessing,
                reduceMotion: reduceMotion
            )
        } else {
            matteSurface
        }
    }

    private var matteSurface: some View {
        Capsule(style: .circular)
            .fill(Color(white: 0.075).opacity(0.96))
            .overlay {
                Capsule(style: .circular)
                    .stroke(Color.white.opacity(0.13), lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
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
            processingContent
        case .done:
            statusIcon(symbol: "checkmark", tint: .green.opacity(0.92))
        case .attention:
            statusIcon(symbol: "exclamationmark", tint: Color(red: 0.92, green: 0.42, blue: 0.08))
        }
    }

    private func recordingContent(mode: IndicatorRecordingMode) -> some View {
        VStack(spacing: mode == .handsFree ? 5 : 0) {
            if mode == .handsFree {
                overlayActionButton(symbol: "checkmark", label: "Finish dictation", action: onCommit)
                    .transition(.opacity)
            }

            recordingBars

            if mode == .handsFree {
                overlayActionButton(symbol: "xmark", label: "Cancel dictation", action: onCancel)
                    .transition(.opacity)
            }
        }
        .frame(width: surfaceSize.width, height: surfaceSize.height)
    }

    private var recordingBars: some View {
        let accent = recordingAccent
        return Group {
            if reduceMotion {
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !state.isRecording)) { timeline in
                    let time = ProcessInfo.processInfo.systemUptime + timeline.date.timeIntervalSinceNow
                    let baseWidths = state.isRecording
                        ? recordingWaveform.sampleBarWidths(at: time)
                        : Array(repeating: CGFloat(2.5), count: 7)
                    let widths = baseWidths
                    Canvas { context, size in
                        let height: CGFloat = 2.5
                        let spacing: CGFloat = 2.5
                        let totalHeight = CGFloat(widths.count) * height + CGFloat(widths.count - 1) * spacing
                        for (index, width) in widths.enumerated() {
                            let rect = CGRect(
                                x: (size.width - width) / 2,
                                y: (size.height - totalHeight) / 2 + CGFloat(index) * (height + spacing),
                                width: width,
                                height: height
                            )
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: height / 2),
                                with: .color(
                                    (abs(index - widths.count / 2) <= 1
                                        ? accent : .white).opacity(0.92)
                                )
                            )
                        }
                    }
                }
            }
        }
        .frame(width: 18, height: 36)
        .accessibilityHidden(true)
    }

    private var recordingAccent: Color {
        let variant = CrabColorVariant(rawValue: crabColorVariant) ?? .ocean
        let color = NSColor(variant.swatchColor).blended(withFraction: 0.72, of: .white) ?? .white
        return Color(nsColor: color)
    }

    private var recordingTargetLevel: Float {
        if case .recording(let level, _) = state {
            return level
        }
        return 0
    }

    private func statusIcon(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private var processingContent: some View {
        if style != .glass { processingRing }
    }

    private var processingRing: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let time = ProcessInfo.processInfo.systemUptime + timeline.date.timeIntervalSinceNow
            let phase = reduceMotion ? 0 : time.truncatingRemainder(dividingBy: 0.9) / 0.9
            Circle()
                .trim(from: 0.16, to: 0.86)
                .stroke(
                    Color.white.opacity(0.9),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(phase * 360))
        }
        .accessibilityHidden(true)
    }

    private func overlayActionButton(
        symbol: String,
        label: String,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private var surfaceSize: CGSize {
        switch state {
        case .idle:
            return CGSize(width: 8, height: 30)
        case .armed:
            return CGSize(width: 26, height: 64)
        case .recording(_, .hold):
            return CGSize(width: 26, height: 64)
        case .recording(_, .handsFree):
            return CGSize(width: 26, height: 96)
        case .processing, .done, .attention:
            return CGSize(width: 26, height: style == .glass ? 26 : 34)
        }
    }

    private var visualKind: String {
        switch state {
        case .idle:
            return "idle"
        case .armed:
            return "recording"
        case .recording:
            return "recording"
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
    @State private var spriteFrameName = CrabSpriteAssets.idleFrameNames[0]
    @State private var idleOffset: CGFloat = 0
    @State private var processingRotation = 0.0

    var body: some View {
        ZStack(alignment: .trailing) {
            SpriteWallCrab(
                frameName: spriteFrameName,
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
            setSpriteFrame(
                state.showsBoomMic
                ? CrabSpriteAssets.boomHoldFrameName
                : CrabSpriteAssets.idleFrameNames[0]
            )
            return
        }

        if state.showsBoomMic {
            await animateBoomIntro()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            return
        }

        if CrabSpriteAssets.isBoomFrame(spriteFrameName) {
            await animateBoomOutro()
        }

        let maxOffset = min(max((height - 76) / 2 - 16, 0), 72)
        var crawlDirection: CGFloat = Bool.random() ? -1 : 1
        var crawlFrameIndex = 0

        while !Task.isCancelled {
            let stepCount = Int.random(in: 8...14)

            for _ in 0..<stepCount {
                if Task.isCancelled { return }

                let nextOffset = idleOffset + crawlDirection * CGFloat.random(in: 3.2...5.4)
                withAnimation(.easeInOut(duration: CrabAnimationTiming.idleStepDuration)) {
                    idleOffset = min(max(nextOffset, -maxOffset), maxOffset)
                }
                setSpriteFrame(CrabSpriteAssets.idleFrameNames[
                    crawlFrameIndex % CrabSpriteAssets.idleFrameNames.count
                ])
                crawlFrameIndex += 1

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

    private func animateBoomIntro() async {
        for frameName in CrabSpriteAssets.boomIntroFrameNames {
            if Task.isCancelled { return }
            setSpriteFrame(frameName)
            try? await Task.sleep(nanoseconds: CrabAnimationTiming.boomIntroFrameDelay)
        }
        setSpriteFrame(CrabSpriteAssets.boomHoldFrameName)
    }

    private func animateBoomOutro() async {
        for frameName in CrabSpriteAssets.boomIntroFrameNames.reversed() {
            if Task.isCancelled { return }
            setSpriteFrame(frameName)
            try? await Task.sleep(nanoseconds: CrabAnimationTiming.boomOutroFrameDelay)
        }
        setSpriteFrame(CrabSpriteAssets.idleFrameNames[0])
    }

    private func setSpriteFrame(_ frameName: String) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            spriteFrameName = frameName
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
    let frameName: String
    let showsProcessing: Bool
    let processingRotation: Double
    let attentionMessage: String?

    @Environment(\.displayScale) private var displayScale
    @AppStorage(Defaults.crabColorVariant) private var crabColorVariant = CrabColorVariant.ocean.rawValue

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = currentImage {
                spriteImage(image)
                    .id(frameName)
                    .transition(.identity)
                    .transaction { transaction in
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
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
    static let idleFrameNames = [
        "idle-1",
        "idle-2",
        "idle-3",
        "idle-4",
        "idle-3",
        "idle-2",
    ]
    static let boomIntroFrameNames = frameNames(prefix: "recording-intro", count: 6)
    static let boomHoldFrameName = "recording-hold"

    @MainActor private static var imageCache: [String: NSImage] = [:]

    static func isBoomFrame(_ frameName: String) -> Bool {
        frameName.hasPrefix("recording-")
    }

    @MainActor
    static func image(named name: String, variant: CrabColorVariant) -> NSImage? {
        image(named: name, subdirectory: "CrabSpriteWallVariants/\(variant.rawValue)")
            ?? image(named: name, subdirectory: "CrabSpritesWall")
    }

    @MainActor
    private static func image(named name: String, subdirectory: String) -> NSImage? {
        let cacheKey = "\(subdirectory)/\(name)"
        if let cachedImage = imageCache[cacheKey] {
            return cachedImage
        }

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
        imageCache[cacheKey] = image
        return image
    }

    private static func frameNames(prefix: String, count: Int) -> [String] {
        (1...count).map { index in "\(prefix)-\(index)" }
    }
}
