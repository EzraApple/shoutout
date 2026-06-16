import Foundation

enum TranscriptionBackend: String, CaseIterable, Hashable, Identifiable, Sendable {
    case whisperKit = "whisperkit"
    case appleSpeech = "appleSpeech"
    case appleDictation = "appleDictation"

    var id: String { rawValue }

    static var selectableCases: [TranscriptionBackend] {
        var backends: [TranscriptionBackend] = [.appleSpeech]
#if swift(>=6.2)
        if #available(macOS 26.0, *) {
            backends.append(.appleDictation)
        }
#endif
        backends.append(.whisperKit)
        return backends
    }

    var displayName: String {
        switch self {
        case .whisperKit:
            return "WhisperKit"
        case .appleSpeech:
            return "Apple Speech"
        case .appleDictation:
            return "Apple Dictation"
        }
    }

    var detailText: String {
        switch self {
        case .whisperKit:
            return "Local Whisper models, downloaded when selected"
        case .appleSpeech:
            return "Built in; no model download required"
        case .appleDictation:
            return "Built in on macOS 26+; assets install if needed"
        }
    }

    var requiresManagedModel: Bool {
        self == .whisperKit
    }

    var requiresSpeechRecognitionPermission: Bool {
        switch self {
        case .appleSpeech, .appleDictation:
            return true
        case .whisperKit:
            return false
        }
    }
}

struct EngineTranscriptionResult: Sendable {
    var rawText: String
    var firstTokenMs: Int?
    var pipelineMs: Int?
    var realTimeFactor: Double?
    var speedFactor: Double?
    var tokensPerSecond: Double?
    var fallbackCount: Int?
}

@MainActor
protocol TranscriptionEngine {
    var backend: TranscriptionBackend { get }
    var modelIdentifier: String { get }

    func load(updateState: @escaping @MainActor (ModelState) -> Void) async throws
    func transcribe(audioSamples: [Float]) async throws -> EngineTranscriptionResult
    func unload()
}
