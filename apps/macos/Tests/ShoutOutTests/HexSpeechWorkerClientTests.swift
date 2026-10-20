import Foundation
import XCTest
@testable import ShoutOut

final class HexSpeechWorkerClientTests: XCTestCase {
    func testWorkerEOFRejectsPendingCommand() async throws {
        let fixture = try makeWorker("exit 0")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let client = makeClient(fixture.worker)
        do {
            try await client.begin(id: UUID())
            XCTFail("The command must fail when the worker closes stdout.")
        } catch {}
        await client.stop()
    }

    func testWorkerErrorResponseIsReturnedToCaller() async throws {
        let fixture = try makeWorker("printf '{\"event\":\"error\",\"id\":\"%s\",\"message\":\"bad audio\"}\\n' \"$id\"")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let client = makeClient(fixture.worker)
        do {
            try await client.begin(id: UUID())
            XCTFail("The worker error must reach the caller.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("bad audio"))
        }
        await client.stop()
    }

    func testMismatchedIDRejectsCommand() async throws {
        let fixture = try makeWorker("printf '%s\\n' '{\"event\":\"begun\",\"id\":\"wrong-id\"}'")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let client = makeClient(fixture.worker)
        do {
            try await client.begin(id: UUID())
            XCTFail("A result for a different recording must be rejected.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("mismatched recording ID"))
        }
        await client.stop()
    }

    func testFinishTimeoutRestartsBeforeOfflineTranscription() async throws {
        let fixture = try makeWorker("""
            case "$op" in
              begin) printf '{"event":"begun","id":"%s"}\\n' "$id" ;;
              finish) read -r ignored ;;
              transcribe) printf '{"event":"result","id":"%s","text":"recovered","source":"offline"}\\n' "$id" ;;
            esac
            """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let client = makeClient(fixture.worker, finishTimeout: .milliseconds(75))
        let recordingID = UUID()
        try await client.begin(id: recordingID)
        do {
            _ = try await client.finish(id: recordingID)
            XCTFail("Finish must time out.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("timed out"))
        }
        let result = try await client.transcribe(id: UUID(), samples: [0.1, -0.1])
        XCTAssertEqual(result, "recovered")
        await client.stop()
    }

    func testConcurrentCallsKeepTheirRecordingIDs() async throws {
        let fixture = try makeWorker("printf '{\"event\":\"result\",\"id\":\"%s\",\"text\":\"%s\",\"source\":\"offline\"}\\n' \"$id\" \"$id\"")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let client = makeClient(fixture.worker)
        let firstID = UUID()
        let secondID = UUID()
        async let first = client.transcribe(id: firstID, samples: [0.1])
        async let second = client.transcribe(id: secondID, samples: [0.2])
        let firstText = try await first
        let secondText = try await second
        XCTAssertEqual(firstText, firstID.uuidString)
        XCTAssertEqual(secondText, secondID.uuidString)
        await client.stop()
    }

    private func makeClient(
        _ executableURL: URL, finishTimeout: Duration = .milliseconds(1_500)
    ) -> HexSpeechWorkerClient {
        HexSpeechWorkerClient(
            executableURL: executableURL,
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            expectedSHA256: "test-sha",
            finishTimeout: finishTimeout
        )
    }

    private func makeWorker(_ response: String) throws -> (directory: URL, worker: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let worker = directory.appendingPathComponent("fake-worker")
        let script = """
            #!/bin/sh
            printf '%s\\n' '{"event":"ready","modelSha256":"test-sha","streamAvailable":true}'
            while IFS= read -r line; do
              id=$(printf '%s' "$line" | sed -n 's/.*"id":"\\([^"]*\\)".*/\\1/p')
              op=$(printf '%s' "$line" | sed -n 's/.*"op":"\\([^"]*\\)".*/\\1/p')
              \(response)
            done
            """
        try script.write(to: worker, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: worker.path)
        return (directory, worker)
    }
}
