import Foundation

public struct AudioSignalAnalysis: Equatable, Sendable {
    private static let activeSampleThreshold: Float = 0.001
    private static let speechPeakThreshold: Float = 0.003
    private static let speechRMSThreshold: Float = 0.0006
    private static let speechActiveRatioThreshold: Float = 0.002

    public let sampleCount: Int
    public let rms: Float
    public let peak: Float
    public let activeRatio: Float

    public var hasSpeechLikeAudio: Bool {
        peak >= Self.speechPeakThreshold
            && rms >= Self.speechRMSThreshold
            && activeRatio >= Self.speechActiveRatioThreshold
    }

    public func hasSustainedSpeechLikeAudio(sampleRate: Double) -> Bool {
        guard sampleRate > 0, hasSpeechLikeAudio else { return false }

        let duration = Double(sampleCount) / sampleRate
        let activeDuration = duration * Double(activeRatio)
        return duration >= 0.25
            && activeDuration >= 0.12
            && rms >= 0.0012
            && activeRatio >= 0.015
    }

    public static func analyze(samples: [Float]) -> AudioSignalAnalysis {
        guard !samples.isEmpty else {
            return AudioSignalAnalysis(sampleCount: 0, rms: 0, peak: 0, activeRatio: 0)
        }

        var sumSquares: Double = 0
        var peak: Float = 0
        var activeSampleCount = 0

        for sample in samples {
            let magnitude = abs(sample)
            guard magnitude.isFinite else {
                continue
            }

            sumSquares += Double(magnitude * magnitude)
            peak = max(peak, magnitude)
            if magnitude >= activeSampleThreshold {
                activeSampleCount += 1
            }
        }

        return AudioSignalAnalysis(
            sampleCount: samples.count,
            rms: Float((sumSquares / Double(samples.count)).squareRoot()),
            peak: peak,
            activeRatio: Float(Double(activeSampleCount) / Double(samples.count))
        )
    }

    public static func trimmingTrailingSilence(
        from samples: [Float],
        sampleRate: Double,
        minimumTrailingSilence: TimeInterval = 0.7,
        preservedTail: TimeInterval = 0.2,
        windowDuration: TimeInterval = 0.1
    ) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0 else { return samples }

        let windowSize = max(Int(sampleRate * windowDuration), 1)
        let minimumTrimSamples = max(Int(sampleRate * minimumTrailingSilence), 1)
        let preservedTailSamples = max(Int(sampleRate * preservedTail), 0)

        var windowEnd = samples.count
        var lastSpeechLikeWindowEnd: Int?

        while windowEnd > 0 {
            let windowStart = max(0, windowEnd - windowSize)
            let analysis = analyze(samples: Array(samples[windowStart..<windowEnd]))
            if analysis.hasSpeechLikeAudio {
                lastSpeechLikeWindowEnd = windowEnd
                break
            }
            windowEnd = windowStart
        }

        guard let lastSpeechLikeWindowEnd else {
            return []
        }

        let keepCount = min(samples.count, lastSpeechLikeWindowEnd + preservedTailSamples)
        guard samples.count - keepCount >= minimumTrimSamples else {
            return samples
        }

        return Array(samples[..<keepCount])
    }
}
