import Foundation
import XCTest
@testable import ShoutOut

@MainActor
final class RecordingTranscriptionQueueTests: XCTestCase {
    func testNextRecordingWaitsForFinalizationAndKeepsItsOwnAudio() async throws {
        let engine = ReplayEngine()
        let queue = RecordingTranscriptionQueue()
        let first = queue.begin(engine: engine)
        queue.append([Float](repeating: 1, count: 3000), to: first)
        queue.finish(first, audioSamples: [1])
        let second = queue.begin(engine: engine)
        queue.append([Float](repeating: 2, count: 3000), to: second)
        queue.finish(second, audioSamples: [2])
        let firstResult = try await first.finalization!.value
        let secondResult = try await second.finalization!.value
        XCTAssertEqual(firstResult.rawText, "3000.0")
        XCTAssertEqual(secondResult.rawText, "6000.0")
        XCTAssertEqual(engine.events, ["begin", "feed", "feed", "finish", "begin", "feed", "feed", "finish"])
    }

    func testCancelledPendingRecordingDoesNotFeedOrFinish() async throws {
        let engine = ReplayEngine()
        let queue = RecordingTranscriptionQueue()
        let recording = queue.begin(engine: engine)
        queue.append([Float](repeating: 1, count: 3000), to: recording)
        queue.cancel(recording)
        let next = queue.begin(engine: engine)
        queue.finish(next, audioSamples: [2])
        _ = try await next.finalization!.value
        XCTAssertEqual(engine.events, ["cancel", "begin", "finish"])
    }

    func testFailedFeedUsesCompleteRecordingInsteadOfPartialText() async throws {
        let engine = ReplayEngine()
        engine.failFeeds = true
        let queue = RecordingTranscriptionQueue()
        let recording = queue.begin(engine: engine)
        queue.append([Float](repeating: 1, count: 3000), to: recording)
        queue.finish(recording, audioSamples: [4, 5])
        let result = try await recording.finalization!.value
        XCTAssertEqual(result.rawText, "9.0")
        XCTAssertEqual(result.fallbackCount, 1)
        XCTAssertEqual(engine.events, ["begin", "feed", "cancel", "batch"])
    }
}

@MainActor
private final class ReplayEngine: StreamingTranscriptionEngine {
    let backend: TranscriptionBackend = .hexStreaming
    let modelIdentifier = "test"
    var events: [String] = []
    var failFeeds = false
    private var activeID: UUID?
    private var sum: Float = 0

    func load(updateState: @escaping @MainActor (ModelState) -> Void) async throws {}
    func unload() {}
    func startStreaming(id: UUID) async throws {
        XCTAssertNil(activeID)
        events.append("begin")
        activeID = id
        sum = 0
    }
    func feedStreaming(id: UUID, samples: [Float]) async throws {
        XCTAssertEqual(id, activeID)
        events.append("feed")
        if failFeeds { throw CocoaError(.fileReadUnknown) }
        sum += samples.reduce(0, +)
        try await Task.sleep(for: .milliseconds(5))
    }
    func finishStreaming(id: UUID, audioSamples: [Float]) async throws -> EngineTranscriptionResult {
        XCTAssertEqual(id, activeID)
        events.append("finish")
        try await Task.sleep(for: .milliseconds(10))
        activeID = nil
        return EngineTranscriptionResult(rawText: String(sum))
    }
    func cancelStreaming(id: UUID) async {
        events.append("cancel")
        activeID = nil
    }
    func transcribe(audioSamples: [Float]) async throws -> EngineTranscriptionResult {
        events.append("batch")
        return EngineTranscriptionResult(rawText: String(audioSamples.reduce(0, +)))
    }
}
