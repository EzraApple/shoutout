import Foundation

struct TranscriptionModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String

    static let bestID = "large-v3-v20240930_626MB"
    static let benchmarkTurboID = "large-v3-v20240930_turbo_632MB"
    static let fastID = "small.en"
    static let defaultID = bestID

    static let advancedOptions: [TranscriptionModelOption] = [
        TranscriptionModelOption(
            id: bestID,
            title: "Large v3 Turbo 626 MB",
            detail: "Current default. Strong quality with good Mac speed, ~626 MB download."
        ),
        TranscriptionModelOption(
            id: benchmarkTurboID,
            title: "Large v3 Turbo 632 MB",
            detail: "Benchmark candidate. Similar size and same WhisperKit engine; try it when comparing speed and transcript quality."
        ),
        TranscriptionModelOption(
            id: fastID,
            title: "Fast English",
            detail: "Smaller English-only model. Faster startup and transcription, with a quality tradeoff."
        ),
    ]

    static let all: [TranscriptionModelOption] = advancedOptions
    static let advancedComparisonText =
        "626 MB is the current default. 632 MB is the benchmark Turbo candidate. Fast English is smaller and quicker, with lower expected accuracy."

    static func option(for id: String) -> TranscriptionModelOption {
        all.first { $0.id == id }
            ?? TranscriptionModelOption(id: id, title: id, detail: "Custom WhisperKit model")
    }
}
