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
            return "Smaller"
        case .system:
            return "System"
        }
    }

    var detail: String {
        switch self {
        case .best:
            return "Fast English dictation with larger local models."
        case .fast:
            return "Smaller download and lower memory use, with a quality tradeoff."
        case .system:
            return "No model download. Uses Apple's built-in speech engine."
        }
    }

    var backend: TranscriptionBackend {
        switch self {
        case .best:
            return .parakeet
        case .fast:
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
        case .parakeet:
            return .best
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
