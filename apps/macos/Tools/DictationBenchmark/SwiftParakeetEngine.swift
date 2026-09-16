import Foundation
import MLX
import MLXAudioSTT
import ShoutOutCore

// Native-runtime experiment. This API exposes sentence segments, but no word
// confidence; production adoption needs a verified terminal-filter path.
private actor SwiftParakeetRuntime {
    private var model: ParakeetModel?

    func load(directory: URL) throws {
        model = try ParakeetModel.fromDirectory(directory, computeDType: .bfloat16)
    }

    func transcribe(samples: [Float]) throws -> String {
        guard let model else { throw TranscriptionError.modelNotReady }
        return model.generate(audio: MLXArray(samples),
            generationParameters: model.defaultGenerationParameters).text
    }
}

@MainActor
final class BenchmarkSwiftParakeetEngine: TranscriptionEngine {
    let backend: TranscriptionBackend = .whisperKit
    let modelIdentifier = "parakeet-1.1b-swift"
    private var runtime: SwiftParakeetRuntime?

    func load(updateState: @escaping @MainActor (ModelState) -> Void) async throws {
        updateState(.loading)
        let runtime = SwiftParakeetRuntime()
        try await runtime.load(directory: URL(fileURLWithPath:
            ProcessInfo.processInfo.environment["BENCH_SWIFT_PARAKEET_DIRECTORY"]!))
        self.runtime = runtime
        updateState(.ready)
    }

    func transcribe(audioSamples: [Float]) async throws -> EngineTranscriptionResult {
        guard let runtime else { throw TranscriptionError.modelNotReady }
        return EngineTranscriptionResult(rawText: try await runtime.transcribe(samples: audioSamples))
    }

    func unload() { runtime = nil }
}
