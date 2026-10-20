import Foundation
import ShoutOutCore

enum TranscriptionBackend: String, CaseIterable, Hashable, Identifiable, Sendable {
    case whisperKit = "whisperkit"
    case parakeet = "parakeet"
    case hexStreaming = "hexStreaming"
    case appleSpeech = "appleSpeech"
    case appleDictation = "appleDictation"

    var id: String { rawValue }

    static let defaultBackend: TranscriptionBackend = .hexStreaming

    static var selectableCases: [TranscriptionBackend] {
        var backends: [TranscriptionBackend] = [.appleSpeech]
#if swift(>=6.2)
        if #available(macOS 26.0, *) {
            backends.append(.appleDictation)
        }
#endif
        backends.append(contentsOf: [.parakeet, .whisperKit, .hexStreaming])
        return backends
    }

    var displayName: String {
        switch self {
        case .whisperKit:
            return "WhisperKit"
        case .hexStreaming:
            return "Parakeet streaming"
        case .parakeet:
            return "Parakeet English"
        case .appleSpeech:
            return "Apple Speech"
        case .appleDictation:
            return "Apple Dictation"
        }
    }

    var detailText: String {
        switch self {
        case .whisperKit:
            return "Best local model control and often strongest quality; requires a download and more startup time."
        case .hexStreaming:
            return "Local English transcription that processes speech while you talk; requires a 731 MB model download."
        case .parakeet:
            return "Fast local English transcription. About 5 GB of models, including Whisper for checking uncertain endings."
        case .appleSpeech:
            return "Fastest startup with no download; good for short dictation, but less consistent on long speech."
        case .appleDictation:
            return "Apple's newer on-device dictation path; better for longer speech, with some warmup/setup cost."
        }
    }

    var speedLabel: String {
        switch self {
        case .appleSpeech:
            return "Fastest"
        case .appleDictation:
            return "Balanced"
        case .whisperKit:
            return "Slower start"
        case .parakeet, .hexStreaming:
            return "Fast inference"
        }
    }

    var qualityLabel: String {
        switch self {
        case .appleSpeech:
            return "Good"
        case .appleDictation:
            return "Better"
        case .whisperKit:
            return "Best control"
        case .parakeet, .hexStreaming:
            return "High English accuracy"
        }
    }

    var requiresManagedModel: Bool {
        self == .whisperKit
    }

    var requiresSpeechRecognitionPermission: Bool {
        switch self {
        case .appleSpeech, .appleDictation:
            return true
        case .whisperKit, .parakeet, .hexStreaming:
            return false
        }
    }
}

struct EngineTranscriptionResult: Sendable {
    var rawText: String
    var wordTimings: [TranscriptWordTiming] = []
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

@MainActor
protocol StreamingTranscriptionEngine: TranscriptionEngine {
    func startStreaming(id: UUID) async throws
    func feedStreaming(id: UUID, samples: [Float]) async throws
    func finishStreaming(id: UUID, audioSamples: [Float]) async throws -> EngineTranscriptionResult
    func cancelStreaming(id: UUID) async
}
