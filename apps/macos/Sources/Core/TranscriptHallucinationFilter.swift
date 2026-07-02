import Foundation

public enum TranscriptHallucinationFilter {
    private static let lowInformationCaptureDuration: TimeInterval = 3.0
    private static let lowEnergyRMS: Float = 0.0025
    private static let lowEnergyPeak: Float = 0.018
    private static let lowInformationWordCount = 2
    private static let lowInformationAlphanumericCount = 24

    public static func shouldDrop(
        text: String,
        recordingDuration: TimeInterval,
        signal: AudioSignalAnalysis
    ) -> Bool {
        let info = transcriptInfo(text)
        if info.alphanumericCharacterCount == 0 || info.wordCount == 0 {
            return true
        }

        guard recordingDuration <= lowInformationCaptureDuration else { return false }
        guard signal.rms <= lowEnergyRMS, signal.peak <= lowEnergyPeak else { return false }

        return info.wordCount <= lowInformationWordCount
            && info.alphanumericCharacterCount <= lowInformationAlphanumericCount
    }

    private struct TranscriptInfo {
        let wordCount: Int
        let alphanumericCharacterCount: Int
    }

    private static func transcriptInfo(_ text: String) -> TranscriptInfo {
        var wordCount = 0
        var alphanumericCharacterCount = 0
        var isInsideWord = false

        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                alphanumericCharacterCount += 1
                if !isInsideWord {
                    wordCount += 1
                    isInsideWord = true
                }
            } else {
                isInsideWord = false
            }
        }

        return TranscriptInfo(
            wordCount: wordCount,
            alphanumericCharacterCount: alphanumericCharacterCount
        )
    }
}
