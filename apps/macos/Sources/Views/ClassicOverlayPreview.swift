#if DEBUG
import AppKit
import SwiftUI

/// An isolated presentation check. It never starts capture, models, hotkeys, or the updater.
@MainActor
final class ClassicOverlayPreview: ObservableObject {
    @Published var phase = "Idle"
    @Published var reduceMotion = false
    @Published var level: Float = 0
    @Published var playsSpeech = false
    private var window: NSWindow?
    private var speechTask: Task<Void, Never>?
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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Classic overlay preview"
        window.contentView = NSHostingView(rootView: ClassicPreviewControls(model: self))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
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
        updateOverlay(state, reduceMotion)
    }

    func playSpeech() {
        speechTask?.cancel()
        guard playsSpeech else { return }
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
        phase = "Idle"
        refresh()
    }

    func finish() {
        phase = "Processing"
        refresh()
    }
}

private struct ClassicPreviewControls: View {
    @ObservedObject var model: ClassicOverlayPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Classic overlay").font(.title2.weight(.semibold))
            Text("The actual panel sits at the right edge. No microphone or models are running.")
                .foregroundStyle(.secondary)
            Picker("State", selection: $model.phase) {
                ForEach(["Idle", "Armed", "Hold", "Hands-free", "Processing", "Done", "Attention"], id: \.self) {
                    Text($0)
                }
            }
            Slider(value: $model.level, in: 0...0.30) { Text("Audio level") }
            HStack {
                Toggle("Play speech trace", isOn: $model.playsSpeech)
                Toggle("Reduce Motion", isOn: $model.reduceMotion)
            }
        }
        .padding(24)
        .onChange(of: model.phase) { model.refresh() }
        .onChange(of: model.level) { model.refresh() }
        .onChange(of: model.reduceMotion) { model.refresh() }
        .onChange(of: model.playsSpeech) { model.playSpeech() }
    }
}
#endif
