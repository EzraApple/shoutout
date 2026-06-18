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
            return "Best local model control and often strongest quality; requires a download and more startup time."
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
