import XCTest
@testable import ShoutOutCore

final class TranscriptHallucinationFilterTests: XCTestCase {
    func testDropsPunctuationOnlyTranscript() {
        XCTAssertTrue(
            TranscriptHallucinationFilter.shouldDrop(
                text: "..",
                recordingDuration: 2.8,
                signal: AudioSignalAnalysis(
                    sampleCount: 44_800,
                    rms: 0.014,
                    peak: 0.04,
                    activeRatio: 0.35
                )
            )
        )
    }

    func testDropsLowEnergyLowInformationTranscript() {
        XCTAssertTrue(
            TranscriptHallucinationFilter.shouldDrop(
                text: "Blue table.",
                recordingDuration: 1.4,
                signal: AudioSignalAnalysis(
                    sampleCount: 22_400,
                    rms: 0.0018,
                    peak: 0.006,
                    activeRatio: 0.55
                )
            )
        )
    }

    func testKeepsLowInformationTranscriptWithSpeechPeak() {
        XCTAssertFalse(
            TranscriptHallucinationFilter.shouldDrop(
                text: "Blue table.",
                recordingDuration: 1.4,
                signal: AudioSignalAnalysis(
                    sampleCount: 22_400,
                    rms: 0.002,
                    peak: 0.03,
                    activeRatio: 0.55
                )
            )
        )
    }

    func testKeepsLowEnergyLongerDictation() {
        XCTAssertFalse(
            TranscriptHallucinationFilter.shouldDrop(
                text: "Don't we need the sandbox?",
                recordingDuration: 1.8,
                signal: AudioSignalAnalysis(
                    sampleCount: 28_800,
                    rms: 0.0018,
                    peak: 0.006,
                    activeRatio: 0.55
                )
            )
        )
    }

    func testKeepsLowInformationLongCapture() {
        XCTAssertFalse(
            TranscriptHallucinationFilter.shouldDrop(
                text: "Blue table.",
                recordingDuration: 3.4,
                signal: AudioSignalAnalysis(
                    sampleCount: 54_400,
                    rms: 0.0018,
                    peak: 0.006,
                    activeRatio: 0.55
                )
            )
        )
    }
}
