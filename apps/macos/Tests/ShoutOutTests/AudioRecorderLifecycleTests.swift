import XCTest
@testable import ShoutOut

@MainActor
final class AudioRecorderLifecycleTests: XCTestCase {
    func testReplayTakesKeepSamplesAndStreamingSeparate() {
        let recorder = AudioRecorder()
        var streamed: [[Float]] = []
        recorder.onSamples = { streamed.append($0) }

        recorder.startReplay()
        recorder.appendReplaySamples([1, 2])
        recorder.markReleaseForTailDiagnostics()
        recorder.appendReplaySamples([3])
        XCTAssertEqual(recorder.stopRecording(tailDiagnosticsID: "replay-test"), [1, 2, 3])
        RuntimeLog.flush()

        recorder.startReplay()
        recorder.appendReplaySamples([4])
        XCTAssertEqual(recorder.stopRecording(), [4])
        XCTAssertEqual(streamed, [[1, 2], [3], [4]])
        recorder.tearDown()
    }
}

final class CaptureTailMeasurementTests: XCTestCase {
    func testZeroCutoffCountsOnlySamplesDeliveredAfterRelease() {
        let measurement = CaptureTailMeasurement(sampleCountAtRelease: 400)
        let initial = [Float](repeating: 0.1, count: 400)

        XCTAssertEqual(measurement.logFields(for: initial),
                       "omittedSamplesAt0Ms=0 omittedRmsAt0Ms=0.000000 speechLikeAt0Ms=false")
        XCTAssertEqual(measurement.logFields(for: initial + [Float](repeating: 0.02, count: 1_600)),
                       "omittedSamplesAt0Ms=1600 omittedRmsAt0Ms=0.020000 speechLikeAt0Ms=true")
    }
}

final class AudioCaptureGateTests: XCTestCase {
    func testCaptureGateRejectsLateCallbacksAndResetsEachTake() {
        var resets = 0
        var delivered: [Int] = []
        let gate = AudioCaptureGate(resetTake: { resets += 1 })

        gate.process(hostTime: 99) { delivered.append(-1) }
        gate.beginTake(after: 100)
        gate.process(hostTime: 100) { delivered.append(1) }
        gate.endTake()
        gate.process(hostTime: 101) { delivered.append(-2) }
        gate.beginTake(after: 200)
        gate.process(hostTime: 150) { delivered.append(-3) }
        gate.process(hostTime: 200) { delivered.append(2) }
        gate.endTake()
        gate.process(hostTime: 201) { delivered.append(-4) }

        XCTAssertEqual(resets, 2)
        XCTAssertEqual(delivered, [1, 2])
    }
}
