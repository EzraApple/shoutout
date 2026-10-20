import CryptoKit
import Foundation
import ShoutOutCore

@MainActor
final class HexStreamingTranscriptionEngine: StreamingTranscriptionEngine {
    static let identifier = "parakeet-unified-en-0.6b-Q8_0"
    static let repository = "handy-computer/parakeet-unified-en-0.6b-gguf"
    static let revision = "7e948f21b7bdbac698d3318db9d350f1096f3b6c"
    static let filename = "parakeet-unified-en-0.6b-Q8_0.gguf"
    static let sha256 = "4b50b6dd862bf6e346929aaf4f5eaacec003bfa3f56462d6c874b41ef2f38795"
    static let fileSize: Int64 = 731_357_568
    static let maximumSamples = 10 * 60 * 16_000

    let backend: TranscriptionBackend = .hexStreaming
    let modelIdentifier = HexStreamingTranscriptionEngine.identifier

    private let modelsDirectory: URL
    private let workerURL: URL
    private let verificationEngine: WhisperKitTranscriptionEngine
    private var worker: HexSpeechWorkerClient?
    private var activeStreams: Set<UUID> = []
    private var generation = 0

    init(modelsDirectory: URL, workerURL: URL? = nil) {
        self.modelsDirectory = modelsDirectory
        self.workerURL = workerURL ?? Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/HexSpeechWorker")
        verificationEngine = WhisperKitTranscriptionEngine(
            modelIdentifier: TranscriptionModelOption.benchmarkTurboID,
            modelsDirectory: modelsDirectory
        )
    }

    func load(updateState: @escaping @MainActor (ModelState) -> Void) async throws {
        unload()
        let loadGeneration = generation
        RuntimeLog.write("model load start backend=hexStreaming selected=\(modelIdentifier)")
        updateState(.downloading(progress: 0))
        let progress = HexModelProgressRelay(updateState: updateState)
        var startingWorker: HexSpeechWorkerClient?
        do {
            async let verificationReady: Void = verificationEngine.load(updateState: { _ in })
            let modelURL = try await HexModelDownloader.prepare(
                in: modelsDirectory,
                repository: Self.repository,
                revision: Self.revision,
                filename: Self.filename,
                expectedSHA256: Self.sha256,
                expectedSize: Self.fileSize,
                progress: progress
            )
            progress.finish()
            try Task.checkCancellation()
            guard generation == loadGeneration else { throw CancellationError() }
            updateState(.loading)
            let worker = HexSpeechWorkerClient(
                executableURL: workerURL, modelURL: modelURL, expectedSHA256: Self.sha256
            )
            startingWorker = worker
            try await worker.start()
            try await verificationReady
            try Task.checkCancellation()
            guard generation == loadGeneration else { throw CancellationError() }
            self.worker = worker
            updateState(.ready)
            RuntimeLog.write("model ready backend=hexStreaming selected=\(modelIdentifier)")
        } catch {
            progress.finish()
            if let startingWorker { await startingWorker.stop() }
            verificationEngine.unload()
            throw error
        }
    }

    func startStreaming(id: UUID) async throws {
        guard let worker else { throw TranscriptionError.modelNotReady }
        guard !activeStreams.contains(id) else { return }
        do {
            try await worker.begin(id: id)
            activeStreams.insert(id)
        } catch {
            RuntimeLog.write("hex stream begin failed id=\(id) error=\(error)")
            throw error
        }
    }

    func feedStreaming(id: UUID, samples: [Float]) async throws {
        guard activeStreams.contains(id), let worker else { return }
        do {
            try await worker.feed(id: id, samples: samples)
        } catch {
            activeStreams.remove(id)
            RuntimeLog.write("hex stream feed failed id=\(id) error=\(error)")
            throw error
        }
    }

    func finishStreaming(id: UUID, audioSamples: [Float]) async throws -> EngineTranscriptionResult {
        guard audioSamples.count <= Self.maximumSamples else {
            await cancelStreaming(id: id)
            throw TranscriptionError.recordingTooLong
        }
        guard let worker else { throw TranscriptionError.modelNotReady }
        if activeStreams.remove(id) != nil {
            do {
                let result = try await worker.finish(id: id)
                try Task.checkCancellation()
                return try await verifyIfNeeded(EngineTranscriptionResult(
                    rawText: result.text, fallbackCount: result.usedFallback ? 1 : 0
                ), audioSamples: audioSamples)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                RuntimeLog.write("hex stream finish fallback id=\(id) error=\(error)")
            }
        } else {
            RuntimeLog.write("hex stream unavailable fallback id=\(id)")
        }
        // A fresh command ID avoids reusing a stream ID after a worker restart.
        let text = try await worker.transcribe(id: UUID(), samples: audioSamples)
        return try await verifyIfNeeded(
            EngineTranscriptionResult(rawText: text, fallbackCount: 1),
            audioSamples: audioSamples
        )
    }

    func cancelStreaming(id: UUID) async {
        activeStreams.remove(id)
        guard let worker else { return }
        await worker.cancel(id: id)
    }

    func transcribe(audioSamples: [Float]) async throws -> EngineTranscriptionResult {
        guard audioSamples.count <= Self.maximumSamples else { throw TranscriptionError.recordingTooLong }
        guard let worker else { throw TranscriptionError.modelNotReady }
        let text = try await worker.transcribe(id: UUID(), samples: audioSamples)
        return try await verifyIfNeeded(
            EngineTranscriptionResult(rawText: text, fallbackCount: 0),
            audioSamples: audioSamples
        )
    }

    func unload() {
        generation += 1
        activeStreams.removeAll()
        if let worker { Task { await worker.stop() } }
        worker = nil
        verificationEngine.unload()
    }

    private func verifyIfNeeded(
        _ result: EngineTranscriptionResult, audioSamples: [Float]
    ) async throws -> EngineTranscriptionResult {
        guard TranscriptHallucinationFilter.requiresWordTimingVerification(for: result.rawText) else {
            return result
        }
        RuntimeLog.write("transcription verification backend=hexStreaming verifier=whisperkit")
        do {
            var verified = try await verificationEngine.transcribe(audioSamples: audioSamples)
            verified.fallbackCount = (verified.fallbackCount ?? 0) + (result.fallbackCount ?? 0) + 1
            return verified
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            RuntimeLog.write("hex verification failed; retaining native result error=\(error)")
            return result
        }
    }
}

private final class HexModelProgressRelay: @unchecked Sendable {
    private let updateState: @MainActor (ModelState) -> Void
    @MainActor private var active = true

    init(updateState: @escaping @MainActor (ModelState) -> Void) {
        self.updateState = updateState
    }

    func report(_ fraction: Double) {
        Task { @MainActor in
            guard active else { return }
            updateState(.downloading(progress: min(max(fraction, 0), 1)))
        }
    }

    @MainActor func finish() {
        active = false
    }
}

private final class HexModelDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: HexModelProgressRelay

    init(progress: HexModelProgressRelay) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress.report(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}

private actor HexModelDownloader {
    static func prepare(
        in modelsDirectory: URL,
        repository: String,
        revision: String,
        filename: String,
        expectedSHA256: String,
        expectedSize: Int64,
        progress: HexModelProgressRelay
    ) async throws -> URL {
        let directory = modelsDirectory.appendingPathComponent("hex-\(revision)")
        let destination = directory.appendingPathComponent(filename)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path),
           try verify(destination, sha256: expectedSHA256, size: expectedSize) {
            progress.report(1)
            return destination
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(filename)")!
        let delegate = HexModelDownloadDelegate(progress: progress)
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        let (downloaded, response) = try await URLSession.shared.download(for: request, delegate: delegate)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw HexSpeechWorkerError.unavailable("Hex model download failed.")
        }
        try Task.checkCancellation()
        guard try verify(downloaded, sha256: expectedSHA256, size: expectedSize) else {
            throw HexSpeechWorkerError.unavailable("Hex model checksum or size did not match the pinned release.")
        }

        let staging = directory.appendingPathComponent(".\(filename).\(UUID().uuidString).partial")
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.moveItem(at: downloaded, to: staging)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
        progress.report(1)
        return destination
    }

    private static func verify(_ url: URL, sha256: String, size: Int64) throws -> Bool {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == size else { return false }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            digest.update(data: chunk)
        }
        let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
        return actual == sha256
    }
}
