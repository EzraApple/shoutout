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

    func testRemovesTerminalThankYouAfterSilentGap() {
        var samples = Array(repeating: Float(0), count: 4_000)
        for index in 400..<1_000 {
            samples[index] = index.isMultiple(of: 2) ? 0.02 : -0.02
        }

        let cleanup = TranscriptHallucinationFilter.removingTerminalSilenceHallucination(
            from: "Please ship the smaller version. Thank you.",
            wordTimings: [
                .init(text: "version.", start: 0.4, end: 1.0, probability: 0.95),
                .init(text: " Thank", start: 2.0, end: 2.2, probability: 0.92),
                .init(text: " you.", start: 2.2, end: 2.4, probability: 0.91),
            ],
            audioSamples: samples,
            sampleRate: 1_000
        )

        XCTAssertEqual(cleanup.text, "Please ship the smaller version.")
        XCTAssertEqual(cleanup.candidatePhrase, "thank_you")
        XCTAssertTrue(cleanup.removed)
        XCTAssertEqual(cleanup.gapSeconds ?? -1, 1.0, accuracy: 0.001)
    }

    func testKeepsTerminalThankYouWhenItHasSpeechEnergy() {
        var samples = Array(repeating: Float(0), count: 4_000)
        for index in 400..<1_000 {
            samples[index] = index.isMultiple(of: 2) ? 0.02 : -0.02
        }
        for index in 2_000..<2_400 {
            samples[index] = index.isMultiple(of: 2) ? 0.018 : -0.018
        }

        let cleanup = TranscriptHallucinationFilter.removingTerminalSilenceHallucination(
            from: "Please ship the smaller version. Thank you.",
            wordTimings: [
                .init(text: "version.", start: 0.4, end: 1.0, probability: 0.95),
                .init(text: " Thank", start: 2.0, end: 2.2, probability: 0.92),
                .init(text: " you.", start: 2.2, end: 2.4, probability: 0.91),
            ],
            audioSamples: samples,
            sampleRate: 1_000
        )

        XCTAssertEqual(cleanup.text, "Please ship the smaller version. Thank you.")
        XCTAssertFalse(cleanup.removed)
    }

    func testKeepsLowConfidenceThankYouWithoutLongGap() {
        let samples = Array(repeating: Float(0), count: 2_000)
        let cleanup = TranscriptHallucinationFilter.removingTerminalSilenceHallucination(
            from: "Please ship it. Thank you.",
            wordTimings: [
                .init(text: "it.", start: 0.5, end: 1.0, probability: 0.95),
                .init(text: " Thank", start: 1.2, end: 1.4, probability: 0.40),
                .init(text: " you.", start: 1.4, end: 1.6, probability: 0.42),
            ],
            audioSamples: samples,
            sampleRate: 1_000
        )

        XCTAssertEqual(cleanup.text, "Please ship it. Thank you.")
        XCTAssertFalse(cleanup.removed)
    }

    func testKeepsStandaloneThankYou() {
        let cleanup = TranscriptHallucinationFilter.removingTerminalSilenceHallucination(
            from: "Thank you.",
            wordTimings: [
                .init(text: "Thank", start: 0.2, end: 0.4, probability: 0.95),
                .init(text: " you.", start: 0.4, end: 0.7, probability: 0.95),
            ],
            audioSamples: Array(repeating: 0.02, count: 1_000),
            sampleRate: 1_000
        )

        XCTAssertEqual(cleanup.text, "Thank you.")
        XCTAssertNil(cleanup.candidatePhrase)
        XCTAssertFalse(cleanup.removed)
    }
}
