import Testing
@testable import ShoutOutCore

struct AudioSignalAnalysisTests {
    @Test func silentSamplesAreNotSpeechLike() {
        let analysis = AudioSignalAnalysis.analyze(samples: Array(repeating: 0, count: 16_000))

        #expect(analysis.sampleCount == 16_000)
        #expect(analysis.rms == 0)
        #expect(analysis.peak == 0)
        #expect(analysis.activeRatio == 0)
        #expect(!analysis.hasSpeechLikeAudio)
    }

    @Test func nearSilentNoiseIsNotSpeechLike() {
        let samples = (0..<16_000).map { index in
            index.isMultiple(of: 2) ? Float(0.0002) : Float(-0.0002)
        }

        let analysis = AudioSignalAnalysis.analyze(samples: samples)

        #expect(!analysis.hasSpeechLikeAudio)
    }

    @Test func isolatedClickIsNotSpeechLike() {
        var samples = Array(repeating: Float(0), count: 16_000)
        samples[8_000] = 0.8

        let analysis = AudioSignalAnalysis.analyze(samples: samples)

        #expect(analysis.peak == 0.8)
        #expect(!analysis.hasSpeechLikeAudio)
    }

    @Test func shortSpeechLikeBurstPassesBasicGateOnly() {
        var samples = Array(repeating: Float(0), count: 16_000)
        for index in 6_000..<6_800 {
            samples[index] = index.isMultiple(of: 2) ? 0.02 : -0.02
        }

        let analysis = AudioSignalAnalysis.analyze(samples: samples)

        #expect(analysis.rms > 0.0006)
        #expect(analysis.peak > 0.003)
        #expect(analysis.activeRatio > 0.002)
        #expect(analysis.hasSpeechLikeAudio)
        #expect(!analysis.hasSustainedSpeechLikeAudio(sampleRate: 16_000))
    }

    @Test func sustainedSpeechLikeBurstPassesSustainedGate() {
        var samples = Array(repeating: Float(0), count: 16_000)
        for index in 6_000..<12_000 {
            samples[index] = index.isMultiple(of: 2) ? 0.02 : -0.02
        }

        let analysis = AudioSignalAnalysis.analyze(samples: samples)

        #expect(analysis.hasSpeechLikeAudio)
        #expect(analysis.hasSustainedSpeechLikeAudio(sampleRate: 16_000))
    }

    @Test func trimsLongTrailingSilenceAfterSpeech() {
        var samples = Array(repeating: Float(0), count: 48_000)
        for index in 8_000..<16_000 {
            samples[index] = index.isMultiple(of: 2) ? 0.02 : -0.02
        }

        let trimmed = AudioSignalAnalysis.trimmingTrailingSilence(
            from: samples,
            sampleRate: 16_000
        )

        #expect(trimmed.count < samples.count)
        #expect(trimmed.count >= 16_000)
        #expect(trimmed.count <= 20_000)
    }

    @Test func preservesShortTrailingSilenceAfterSpeech() {
        var samples = Array(repeating: Float(0), count: 20_000)
        for index in 8_000..<16_000 {
            samples[index] = index.isMultiple(of: 2) ? 0.02 : -0.02
        }

        let trimmed = AudioSignalAnalysis.trimmingTrailingSilence(
            from: samples,
            sampleRate: 16_000
        )

        #expect(trimmed.count == samples.count)
    }

    @Test func trimmingAllSilentSamplesReturnsEmpty() {
        let samples = Array(repeating: Float(0), count: 24_000)

        let trimmed = AudioSignalAnalysis.trimmingTrailingSilence(
            from: samples,
            sampleRate: 16_000
        )

        #expect(trimmed.isEmpty)
    }

}
