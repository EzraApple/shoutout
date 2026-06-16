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
}
