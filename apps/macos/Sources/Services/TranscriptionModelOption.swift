import Foundation

struct TranscriptionModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String

    static let defaultID = "large-v3-v20240930_626MB"

    static let all: [TranscriptionModelOption] = [
        TranscriptionModelOption(
            id: "large-v3-v20240930_626MB",
            title: "Large v3 Turbo",
            detail: "Best default. Strong quality, good Mac speed, ~626 MB download."
        ),
        TranscriptionModelOption(
            id: "small.en",
            title: "Fast English",
            detail: "Lighter English-only fallback when speed matters more than accuracy."
        ),
        TranscriptionModelOption(
            id: "tiny.en",
            title: "Tiny fallback",
            detail: "Smallest English model for quick tests or very low memory."
        ),
    ]

    static func option(for id: String) -> TranscriptionModelOption {
        all.first { $0.id == id }
            ?? TranscriptionModelOption(id: id, title: id, detail: "Custom WhisperKit model")
    }
}
