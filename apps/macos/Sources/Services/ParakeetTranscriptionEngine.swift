import Foundation
import Hub
import MLX
import MLXAudioSTT
import ShoutOutCore

private actor ParakeetRuntime {
    private var model: ParakeetModel?

    func load(directory: URL) throws {
        model = try ParakeetModel.fromDirectory(directory, computeDType: .bfloat16)
    }

    func transcribe(samples: [Float]) throws -> String {
        guard let model else { throw TranscriptionError.modelNotReady }
        try Task.checkCancellation()
        let text = model.generate(audio: MLXArray(samples),
            generationParameters: model.defaultGenerationParameters).text
        try Task.checkCancellation()
        return text
    }
}

@MainActor
final class ParakeetTranscriptionEngine: TranscriptionEngine {
    static let identifier = "parakeet-tdt-1.1b"
    static let repository = "mlx-community/parakeet-tdt-1.1b"
    static let revision = "a48da3b2e1aa436c4077acb978bb3a2b65fd1b45"

    let backend: TranscriptionBackend = .parakeet
    let modelIdentifier = ParakeetTranscriptionEngine.identifier

    private let modelsDirectory: URL
    private let verificationEngine: WhisperKitTranscriptionEngine
    private var runtime: ParakeetRuntime?

    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
        verificationEngine = WhisperKitTranscriptionEngine(
            modelIdentifier: TranscriptionModelOption.benchmarkTurboID, modelsDirectory: modelsDirectory)
    }

    func load(updateState: @escaping @MainActor (ModelState) -> Void) async throws {
        runtime = nil
        RuntimeLog.write("model load start backend=parakeet selected=\(modelIdentifier)")
        updateState(.downloading(progress: 0))
        let directory = try await prepareModelDirectory(updateState: updateState)
        updateState(.loading)
        let runtime = ParakeetRuntime()
        async let verificationReady: Void = verificationEngine.load(updateState: { _ in })
        try await runtime.load(directory: directory)
        try await verificationReady
        try Task.checkCancellation()
        self.runtime = runtime
        updateState(.ready)
        RuntimeLog.write("model ready backend=parakeet selected=\(modelIdentifier)")
    }

    func transcribe(audioSamples: [Float]) async throws -> EngineTranscriptionResult {
        guard let runtime else { throw TranscriptionError.modelNotReady }
        let text = try await runtime.transcribe(samples: audioSamples)
        guard TranscriptHallucinationFilter.requiresWordTimingVerification(for: text) else {
            return EngineTranscriptionResult(rawText: text)
        }

        // The native Parakeet API has no word confidence. For endings that need
        // that evidence, retain the existing Whisper timing and silence checks.
        RuntimeLog.write("transcription verification backend=parakeet verifier=whisperkit")
        var verified = try await verificationEngine.transcribe(audioSamples: audioSamples)
        verified.fallbackCount = (verified.fallbackCount ?? 0) + 1
        return verified
    }

    func unload() {
        runtime = nil
        verificationEngine.unload()
    }

    private func prepareModelDirectory(
        updateState: @escaping @MainActor (ModelState) -> Void
    ) async throws -> URL {
        let downloadBase = modelsDirectory.appendingPathComponent("parakeet-\(Self.revision)")
        let directory = downloadBase.appendingPathComponent("models/\(Self.repository)")
        let files = ["config.json", "model.safetensors"]
        if files.allSatisfy({ FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }) {
            return directory
        }
        return try await HubApi(downloadBase: downloadBase).snapshot(
            from: Self.repository, revision: Self.revision, matching: files
        ) { @Sendable progress in
            let fraction = progress.fractionCompleted
            Task { @MainActor in updateState(.downloading(progress: fraction)) }
        }
    }
}
