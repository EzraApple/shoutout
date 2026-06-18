import Foundation

enum DictationPreset: String, CaseIterable, Identifiable, Sendable {
    case best
    case fast
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .best:
            return "Best"
        case .fast:
            return "Fast"
        case .system:
            return "System"
        }
    }

    var detail: String {
        switch self {
        case .best:
            return "Highest quality local dictation. Recommended for most Macs."
        case .fast:
            return "Lower latency for weaker Macs, with a small quality tradeoff."
        case .system:
            return "No model download. Uses Apple's built-in speech engine."
        }
    }

    var backend: TranscriptionBackend {
        switch self {
        case .best, .fast:
            return .whisperKit
        case .system:
            return .appleSpeech
        }
    }

    var modelID: String? {
        switch self {
        case .best:
            return TranscriptionModelOption.bestID
        case .fast:
            return TranscriptionModelOption.fastID
        case .system:
            return nil
        }
    }

    static func matching(backend: TranscriptionBackend, modelID: String) -> DictationPreset {
        switch backend {
        case .whisperKit:
            return modelID == TranscriptionModelOption.fastID ? .fast : .best
        case .appleSpeech, .appleDictation:
            return .system
        }
    }
}

@MainActor
extension TranscriptionService {
    var selectedPreset: DictationPreset {
        DictationPreset.matching(backend: selectedBackend, modelID: selectedModel)
    }

    func applyPreset(_ preset: DictationPreset) {
        selectedBackend = preset.backend
        if let modelID = preset.modelID {
            selectedModel = modelID
        }
    }
}
