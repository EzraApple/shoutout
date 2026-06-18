import Foundation

struct TranscriptionModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String

    static let bestID = "large-v3-v20240930_626MB"
    static let fastID = "small.en"
    static let defaultID = bestID

    static let all: [TranscriptionModelOption] = [
        TranscriptionModelOption(
            id: bestID,
            title: "Large v3 Turbo",
            detail: "Best default. Strong quality, good Mac speed, ~626 MB download."
        ),
        TranscriptionModelOption(
            id: fastID,
            title: "Fast English",
            detail: "Lighter English-only fallback when speed matters more than accuracy."
        ),
    ]

    static func option(for id: String) -> TranscriptionModelOption {
        all.first { $0.id == id }
            ?? TranscriptionModelOption(id: id, title: id, detail: "Custom WhisperKit model")
    }
}
