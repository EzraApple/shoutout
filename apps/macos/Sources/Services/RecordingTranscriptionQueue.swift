import Foundation

@MainActor
final class RecordingTranscription {
    let id = UUID()
    let engine: StreamingTranscriptionEngine?
    fileprivate var pendingSamples: [Float] = []
    fileprivate var cancelled = false
    fileprivate var failed = false
    fileprivate(set) var finalization: Task<EngineTranscriptionResult, Error>?

    init(engine: StreamingTranscriptionEngine?) {
        self.engine = engine
    }
}

/// Orders live feeds and finalization before the next recording's begin command.
/// Capture keeps collecting audio while the worker finishes the preceding clip.
@MainActor
final class RecordingTranscriptionQueue {
    private var pending: Task<Void, Never>?
    private let packetSamples = 2560

    func begin(engine: StreamingTranscriptionEngine?) -> RecordingTranscription {
        let recording = RecordingTranscription(engine: engine)
        if let engine {
            enqueue(recording) { try await engine.startStreaming(id: recording.id) }
        }
        return recording
    }

    func append(_ samples: [Float], to recording: RecordingTranscription) {
        guard let engine = recording.engine, !recording.cancelled,
            recording.finalization == nil else { return }
        recording.pendingSamples.append(contentsOf: samples)
        while recording.pendingSamples.count >= packetSamples {
            let packet = Array(recording.pendingSamples.prefix(packetSamples))
            recording.pendingSamples.removeFirst(packetSamples)
            enqueue(recording) { try await engine.feedStreaming(id: recording.id, samples: packet) }
        }
    }

    func finish(_ recording: RecordingTranscription, audioSamples: [Float]) {
        guard let engine = recording.engine, recording.finalization == nil else { return }
        if !recording.pendingSamples.isEmpty {
            let packet = recording.pendingSamples
            recording.pendingSamples.removeAll()
            enqueue(recording) { try await engine.feedStreaming(id: recording.id, samples: packet) }
        }
        let preceding = pending
        let finalization = Task { @MainActor in
            await preceding?.value
            try Task.checkCancellation()
            guard !recording.cancelled else { throw CancellationError() }
            if recording.failed {
                await engine.cancelStreaming(id: recording.id)
                var result = try await engine.transcribe(audioSamples: audioSamples)
                result.fallbackCount = (result.fallbackCount ?? 0) + 1
                return result
            }
            return try await engine.finishStreaming(id: recording.id, audioSamples: audioSamples)
        }
        recording.finalization = finalization
        pending = Task { _ = try? await finalization.value }
    }

    func cancel(_ recording: RecordingTranscription) {
        recording.cancelled = true
        recording.pendingSamples.removeAll()
        let preceding = pending
        pending = Task { @MainActor in
            await preceding?.value
            await recording.engine?.cancelStreaming(id: recording.id)
        }
    }

    private func enqueue(
        _ recording: RecordingTranscription,
        operation: @escaping @MainActor () async throws -> Void
    ) {
        let preceding = pending
        pending = Task { @MainActor in
            await preceding?.value
            guard !recording.cancelled, !recording.failed else { return }
            do {
                try await operation()
            } catch {
                recording.failed = true
                RuntimeLog.write("stream failed id=\(recording.id) error=\(error)")
            }
        }
    }
}
