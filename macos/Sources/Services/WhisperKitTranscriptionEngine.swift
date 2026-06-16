@preconcurrency import WhisperKit
import Foundation

@MainActor
final class WhisperKitTranscriptionEngine: TranscriptionEngine {
    let backend: TranscriptionBackend = .whisperKit
    let modelIdentifier: String

    private var whisperKit: WhisperKit?
    private let modelsDirectory: URL

    init(modelIdentifier: String, modelsDirectory: URL) {
        self.modelIdentifier = modelIdentifier
        self.modelsDirectory = modelsDirectory
    }

    func load(updateState: @escaping @MainActor (ModelState) -> Void) async throws {
        RuntimeLog.write("model load start backend=\(backend.rawValue) selected=\(modelIdentifier)")
        updateState(.downloading(progress: 0))
        whisperKit = nil

        try? FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
        Self.cleanupInterruptedDownloads(in: modelsDirectory)

        let progressCallback: @Sendable (Progress) -> Void = { progress in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                updateState(.downloading(progress: fraction))
            }
        }

        let modelFolder: URL
        do {
            modelFolder = try await WhisperKit.download(
                variant: modelIdentifier,
                downloadBase: modelsDirectory,
                progressCallback: progressCallback
            )
            RuntimeLog.write(
                "model downloaded backend=\(backend.rawValue) selected=\(modelIdentifier) path=\(modelFolder.path)"
            )
        } catch {
            Self.cleanupInterruptedDownloads(in: modelsDirectory)
            throw error
        }

        updateState(.loading)
        let kit = try await WhisperKit(
            modelFolder: modelFolder.path,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )
        whisperKit = kit
        updateState(.ready)
        RuntimeLog.write("model ready backend=\(backend.rawValue) selected=\(modelIdentifier)")
    }

    func transcribe(audioSamples: [Float]) async throws -> EngineTranscriptionResult {
        guard let kit = whisperKit else {
            throw TranscriptionError.modelNotReady
        }

        let decodingOptions = DecodingOptions(
            task: .transcribe,
            temperature: 0.0,
            usePrefillPrompt: true,
            usePrefillCache: true,
            wordTimestamps: false,
            suppressBlank: true
        )

        let results = try await kit.transcribe(
            audioArray: audioSamples,
            decodeOptions: decodingOptions
        )
        let rawText = results.map { $0.text }.joined(separator: " ")
        let whisperTiming = results.first?.timings

        return EngineTranscriptionResult(
            rawText: rawText,
            firstTokenMs: Self.firstTokenMilliseconds(from: whisperTiming),
            pipelineMs: Self.pipelineMilliseconds(from: whisperTiming),
            realTimeFactor: whisperTiming?.realTimeFactor,
            speedFactor: whisperTiming?.speedFactor,
            tokensPerSecond: whisperTiming?.tokensPerSecond,
            fallbackCount: whisperTiming.map { Int($0.totalDecodingFallbacks) }
        )
    }

    func unload() {
        whisperKit = nil
    }

    private static func firstTokenMilliseconds(from timing: TranscriptionTimings?) -> Int? {
        guard let timing,
            timing.firstTokenTime.isFinite,
            timing.pipelineStart.isFinite,
            timing.firstTokenTime >= timing.pipelineStart
        else { return nil }

        return Int((timing.firstTokenTime - timing.pipelineStart) * 1000)
    }

    private static func pipelineMilliseconds(from timing: TranscriptionTimings?) -> Int? {
        guard let timing, timing.fullPipeline.isFinite else { return nil }
        return Int(timing.fullPipeline * 1000)
    }

    private static func cleanupInterruptedDownloads(in directory: URL) {
        guard FileManager.default.fileExists(atPath: directory.path),
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }

        let interruptedURLs = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            let name = url.lastPathComponent
            guard transientDownloadSuffixes.contains(where: { name.hasSuffix($0) }) else {
                return nil
            }
            return url
        }
        .sorted { $0.path.count > $1.path.count }

        for url in interruptedURLs {
            do {
                try FileManager.default.removeItem(at: url)
                RuntimeLog.write("model cleanup interrupted path=\(url.path)")
            } catch {
                RuntimeLog.write("model cleanup failed path=\(url.path) error=\(error)")
            }
        }
    }

    private static let transientDownloadSuffixes = [
        ".partial",
        ".tmp",
        ".download",
        ".incomplete",
        ".extracting",
    ]
}
