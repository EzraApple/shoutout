#if DEBUG
import AppKit
import SwiftUI

/// An isolated presentation check. It never starts capture, models, hotkeys, or the updater.
@MainActor
final class ClassicOverlayPreview: ObservableObject {
    @Published var style = OverlayStyle.glass
    @Published var phase = "Idle"
    @Published var reduceMotion = false
    @Published var level: Float = 0
    @Published var playsSpeech = false
    @Published var anchor = IndicatorAnchor.right
    @Published var showsPlacementGuides = false
    var onPlacementPreview: ((IndicatorAnchor, Bool) -> Void)?
    @Published private(set) var indicatorState = IndicatorState.idle
    @Published private(set) var caption = "Ready"
    private var window: NSWindow?
    private var speechTask: Task<Void, Never>?
    private var comparisonTask: Task<Void, Never>?
    private let updateOverlay: (IndicatorState, Bool) -> Void

    init(updateOverlay: @escaping (IndicatorState, Bool) -> Void) {
        self.updateOverlay = updateOverlay
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 590),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Classic overlay preview"
        window.contentView = NSHostingView(rootView: ClassicPreviewControls(model: self))
        window.isReleasedWhenClosed = false
        window.center()
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
        refresh()
    }

    func refresh() {
        let state: IndicatorState
        switch phase {
        case "Armed": state = .armed
        case "Hold": state = .recording(level: level, mode: .hold)
        case "Hands-free": state = .recording(level: level, mode: .handsFree)
        case "Processing": state = .processing
        case "Done": state = .done(text: "Done")
        case "Attention": state = .attention(message: "Mic off")
        default: state = .idle
        }
        indicatorState = state
        updateOverlay(state, reduceMotion)
        if !IndicatorAnchor.allowed(for: style).contains(anchor) { anchor = .right }
        onPlacementPreview?(anchor, showsPlacementGuides)
    }

    func setSpeechPlaying(_ plays: Bool) {
        playsSpeech = plays
        speechTask?.cancel()
        guard plays else {
            level = 0
            refresh()
            return
        }
        speechTask = Task { [weak self] in
            let levels: [Float] = [0, 0, 0.04, 0.12, 0.25, 0.18, 0.08, 0.02, 0.15, 0.28,
                0.11, 0.04, 0, 0, 0, 0, 0, 0, 0.03, 0.18, 0.09, 0.22, 0.12, 0.05, 0, 0]
            var index = 0
            while !Task.isCancelled {
                self?.level = levels[index % levels.count]
                self?.refresh()
                index += 1
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func cancel() {
        comparisonTask?.cancel()
        phase = "Idle"
        setSpeechPlaying(false)
    }

    func finish() {
        comparisonTask?.cancel()
        phase = "Processing"
        setSpeechPlaying(false)
    }

    func playFullFlow() {
        comparisonTask?.cancel()
        let steps: [(phase: String, caption: String, duration: Double, speech: Bool)] = [
            ("Idle", "Hold-to-talk · ready", 1.5, false),
            ("Armed", "Hold-to-talk · listening", 0.25, false),
            ("Hold", "Hold-to-talk · recording", 2.4, true),
            ("Hold", "Hold-to-talk · quiet pause", 0.4, false),
            ("Processing", "Hold-to-talk · transcribing", 2.4, false),
            ("Done", "Text inserted", 1.2, false),
            ("Idle", "Double-tap · hands-free", 0.6, false),
            ("Hands-free", "Hands-free · recording", 2.4, true),
            ("Hands-free", "Hands-free · quiet pause", 0.4, false),
            ("Processing", "Hands-free · transcribing", 2.4, false),
            ("Done", "Text inserted", 1.2, false),
            ("Idle", "Ready", 1.0, false),
        ]
        comparisonTask = Task { [weak self] in
            do {
                for step in steps {
                    try Task.checkCancellation()
                    self?.phase = step.phase
                    self?.caption = step.caption
                    self?.setSpeechPlaying(step.speech)
                    self?.refresh()
                    try await Task.sleep(for: .seconds(step.duration))
                }
            } catch {}
        }
    }
}

private struct ClassicPreviewControls: View {
    @ObservedObject var model: ClassicOverlayPreview
    @AppStorage(Defaults.crabColorVariant) private var theme = CrabColorVariant.ocean.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Classic · full flow").font(.title2.weight(.semibold))
                Spacer()
                Text("Native preview · 2× size").font(.callout).foregroundStyle(.secondary)
            }
            Text(model.caption)
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            HStack(spacing: 16) {
                ForEach([OverlayStyle.glass, .capsule], id: \.rawValue) { style in
                    VStack(spacing: 12) {
                        Text(style == .glass ? "Glass" : "Classic").font(.headline)
                        Text(style == .glass ? "Glass circle · fading edge" : "Dark pill · spinner").font(.caption).foregroundStyle(.secondary)
                        AppOverlayView(style: style, state: model.indicatorState, crabHeight: 240, anchor: model.anchor)
                            .scaleEffect(2)
                            .frame(width: 240, height: PillOverlayLayout.size.height * 2)
                            .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background {
                        RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06))
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: [.clear, .white.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: 150)
                    }
                }
            }
            HStack {
                Picker("State", selection: $model.phase) {
                    ForEach(["Idle", "Armed", "Hold", "Hands-free", "Processing", "Done", "Attention"], id: \.self) {
                        Text($0)
                    }
                }
                Picker("App theme", selection: $theme) {
                    ForEach(CrabColorVariant.allCases) { variant in
                        Text(variant.displayName).tag(variant.rawValue)
                    }
                }
                Button("Play full flow") { model.playFullFlow() }
            }
            Slider(value: $model.level, in: 0...0.30) { Text("Audio level") }
            HStack {
                Picker("Floating preview", selection: $model.style) {
                    Text("Glass").tag(OverlayStyle.glass)
                    Text("Classic").tag(OverlayStyle.capsule)
                    Text("Crab").tag(OverlayStyle.crab)
                }
                Toggle("Play speech trace", isOn: Binding(get: { model.playsSpeech }, set: { model.setSpeechPlaying($0) }))
                Toggle("Reduce Motion", isOn: $model.reduceMotion)
            }
            HStack {
                Picker("Preview anchor", selection: $model.anchor) {
                    ForEach(IndicatorAnchor.allowed(for: model.style), id: \.rawValue) { anchor in
                        Text(anchor.rawValue.capitalized).tag(anchor)
                    }
                }
                Toggle("Show drop targets", isOn: $model.showsPlacementGuides)
            }
        }
        .padding(24)
        .environment(\.classicPreviewReduceMotion, model.reduceMotion)
        .onChange(of: model.style) { model.refresh() }
        .onChange(of: model.phase) { model.refresh() }
        .onChange(of: model.level) { model.refresh() }
        .onChange(of: model.reduceMotion) { model.refresh() }
        .onChange(of: model.anchor) { model.refresh() }
        .onChange(of: model.showsPlacementGuides) { model.refresh() }
    }
}
#endif
