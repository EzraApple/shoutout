import XCTest
@testable import ShoutOut

final class ClassicWaveformTests: XCTestCase {
    func testSpeechAttackIsQuickAndReleaseSettlesDuringAPause() {
        var waveform = ClassicWaveform()
        waveform.recordLevel(0.30, at: 0)
        XCTAssertGreaterThan(waveform.sampleLevel(at: 0.06), 0.90)
        let beforeRelease = waveform.sampleLevel(at: 0.1)
        waveform.recordLevel(0, at: 0.1)
        XCTAssertEqual(waveform.sampleLevel(at: 0.1), beforeRelease, accuracy: 0.00001)
        XCTAssertLessThan(waveform.sampleLevel(at: 0.4), 0.05)
        XCTAssertTrue(waveform.sampleBarWidths(at: 1).allSatisfy { $0 < 4.41 })
    }

    func testEnvelopeDoesNotDependOnPublicationFrequency() {
        var sparse = ClassicWaveform()
        sparse.recordLevel(0.2, at: 0)
        var frequent = sparse
        for index in 1...10 {
            frequent.recordLevel(0.2, at: Double(index) * 0.01)
        }
        XCTAssertEqual(sparse.sampleLevel(at: 0.12), frequent.sampleLevel(at: 0.12), accuracy: 0.00001)
    }

    func testNewSamplesNeverJumpAndOlderInputIsIgnored() {
        var waveform = ClassicWaveform()
        waveform.recordLevel(0.30, at: 0)
        let before = waveform.sampleLevel(at: 0.05)
        waveform.recordLevel(0.02, at: 0.05)
        XCTAssertEqual(waveform.sampleLevel(at: 0.05), before, accuracy: 0.00001)
        let later = waveform.sampleLevel(at: 0.08)
        waveform.recordLevel(1, at: 0.01)
        waveform.recordLevel(1, at: .infinity)
        XCTAssertEqual(waveform.sampleLevel(at: 0.08), later)
    }

    func testWaveSpreadsFromCenterWithinCompactBounds() {
        var waveform = ClassicWaveform()
        waveform.recordLevel(1, at: 0)
        let onset = waveform.sampleBarWidths(at: 0.02)
        let resting = ClassicWaveform().sampleBarWidths(at: 0.02)
        XCTAssertGreaterThan(onset[3], resting[3])
        XCTAssertEqual(onset[2], resting[2])
        let full = waveform.sampleBarWidths(at: 1)
        XCTAssertEqual(full.count, 7)
        XCTAssertTrue(full.allSatisfy { (2.5...18).contains($0) })
        XCTAssertEqual(full[3], 18, accuracy: 0.00001)
    }

    func testSilenceAndInvalidLevelsOnlyShowSubtleRestingMotion() {
        var waveform = ClassicWaveform()
        let levels: [Float] = [0, 0.005, -.infinity, .nan]
        for (index, level) in levels.enumerated() {
            waveform.recordLevel(level, at: Double(index))
        }
        XCTAssertEqual(waveform.sampleLevel(at: 10), 0)
        let first = waveform.sampleBarWidths(at: 10)
        let second = waveform.sampleBarWidths(at: 10.5)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue((first + second).allSatisfy { (3...4.4).contains($0) })
        XCTAssertEqual(waveform.sampleLevel(at: .nan), 0)
        XCTAssertEqual(waveform.sampleBarWidths(at: .nan), Array(repeating: 2.5, count: 7))
    }
}
