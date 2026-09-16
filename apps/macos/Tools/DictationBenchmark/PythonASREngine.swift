import Foundation
import ShoutOutCore

// Benchmark-only persistent worker. Audio gates and postprocessing remain native.
@MainActor
final class BenchmarkPythonASREngine: TranscriptionEngine {
    let backend: TranscriptionBackend = .whisperKit
    var modelIdentifier: String { ProcessInfo.processInfo.environment["BENCH_PYTHON_MODEL"]! }
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var pending = Data()

    private struct Response: Decodable {
        var ready: Bool?
        var text: String?
        var error: String?
        var inferenceMs: Double?
        var words: [Word]?
    }
    private struct Word: Decodable {
        var text: String
        var start: Double
        var end: Double
        var probability: Float
    }

    func load(updateState: @escaping @MainActor (ModelState) -> Void) async throws {
        updateState(.loading)
        let environment = ProcessInfo.processInfo.environment
        let worker = Process()
        worker.executableURL = URL(fileURLWithPath: environment["BENCH_PYTHON"]!)
        worker.arguments = [environment["BENCH_PYTHON_WORKER"]!, modelIdentifier]
        let requestPipe = Pipe()
        let responsePipe = Pipe()
        worker.standardInput = requestPipe
        worker.standardOutput = responsePipe
        worker.standardError = FileHandle.standardError
        try worker.run()
        process = worker
        input = requestPipe.fileHandleForWriting
        output = responsePipe.fileHandleForReading
        guard try readResponse().ready == true else {
            throw NSError(domain: "BenchmarkPythonASR", code: 1)
        }
        updateState(.ready)
    }

    func transcribe(audioSamples: [Float]) async throws -> EngineTranscriptionResult {
        let encoded = audioSamples.withUnsafeBytes { Data($0).base64EncodedString() }
        var request = try JSONSerialization.data(withJSONObject: ["samples": encoded])
        request.append(10)
        try input!.write(contentsOf: request)
        let response = try readResponse()
        return EngineTranscriptionResult(rawText: response.text!, wordTimings: (response.words ?? []).map {
            TranscriptWordTiming(text: $0.text, start: $0.start, end: $0.end, probability: $0.probability)
        }, pipelineMs: response.inferenceMs.map { Int($0.rounded()) })
    }

    private func readResponse() throws -> Response {
        while !pending.contains(10) {
            let chunk = output!.availableData
            guard !chunk.isEmpty else {
                throw NSError(domain: "BenchmarkPythonASR", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Python worker exited without a response"])
            }
            pending.append(chunk)
        }
        let end = pending.firstIndex(of: 10)!
        let response = try JSONDecoder().decode(Response.self, from: pending[..<end])
        pending.removeSubrange(...end)
        if let error = response.error {
            throw NSError(domain: "BenchmarkPythonASR", code: 3,
                userInfo: [NSLocalizedDescriptionKey: error])
        }
        return response
    }

    func unload() {
        try? input?.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil
    }
}
