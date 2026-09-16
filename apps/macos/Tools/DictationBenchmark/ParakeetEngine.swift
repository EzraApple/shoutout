import Foundation
import FluidAudio
import ShoutOutCore

// Benchmark-only adapter: production postprocessing and signal gates still run.
@MainActor
final class BenchmarkParakeetEngine: TranscriptionEngine {
    let backend: TranscriptionBackend = .whisperKit
    private var version: AsrModelVersion {
        ProcessInfo.processInfo.environment["BENCH_PARAKEET_VERSION"] == "v2" ? .v2 : .v3
    }
    var modelIdentifier: String {
        "parakeet-tdt-0.6b-" + (ProcessInfo.processInfo.environment["BENCH_PARAKEET_VERSION"] ?? "v3")
    }
    private var manager: AsrManager?

    func load(updateState: @escaping @MainActor (ModelState) -> Void) async throws {
        updateState(.loading)
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BENCH_PARAKEET_CACHE"]!)
        let precision = ParakeetEncoderPrecision(
            rawValue: ProcessInfo.processInfo.environment["BENCH_PARAKEET_ENCODER"] ?? "int8")!
        let models = try await AsrModels.downloadAndLoad(to: directory, version: version,
            encoderPrecision: precision)
        let noMelContext = ProcessInfo.processInfo.environment["BENCH_PARAKEET_NO_MEL_CONTEXT"] == "1"
        let manager = AsrManager(config: ASRConfig(melChunkContext: noMelContext ? false : nil))
        try await manager.loadModels(models)
        self.manager = manager
        updateState(.ready)
    }

    func transcribe(audioSamples: [Float]) async throws -> EngineTranscriptionResult {
        guard let manager else { throw TranscriptionError.modelNotReady }
        var state = try TdtDecoderState()
        let padding = Int(ProcessInfo.processInfo.environment["BENCH_PARAKEET_PADDING_SAMPLES"] ?? "0") ?? 0
        let inferenceSamples = padding > 0 ? audioSamples + Array(repeating: Float(0), count: padding) : audioSamples
        let result = try await manager.transcribe(inferenceSamples, decoderState: &state)
        let tokens = result.tokenTimings ?? []
        let words = buildWordTimings(from: tokens).map { word in
            let probabilities = tokens.filter {
                $0.startTime >= word.startTime && $0.endTime <= word.endTime
            }.map(\.confidence)
            return TranscriptWordTiming(text: word.word, start: word.startTime, end: word.endTime,
                probability: probabilities.isEmpty ? result.confidence
                    : probabilities.reduce(0, +) / Float(probabilities.count))
        }
        if let path = ProcessInfo.processInfo.environment["BENCH_PARAKEET_METRICS"] {
            let record: [String: Any] = [
                "samples": audioSamples.count, "text": result.text,
                "confidence": result.confidence,
                "words": words.map { ["text": $0.text, "probability": $0.probability,
                    "start": $0.start, "end": $0.end] as [String: Any] },
            ]
            var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            data.append(10)
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        }
        return EngineTranscriptionResult(rawText: result.text, wordTimings: words)
    }

    func unload() { manager = nil }
}
