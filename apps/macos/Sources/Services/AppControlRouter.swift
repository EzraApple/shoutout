import AVFoundation
import Foundation
import MiniCleanup
import ShoutOutCore

@MainActor
final class AppControlRouter {
    private let defaults: UserDefaults
    private var transcription: TranscriptionService?
    private var cleanup: LanguagePassService?
    private var dictionary: DictionaryStore?
    private let modelsDirectory: URL
    private let languageModelsDirectory: URL
    private let settingsChanged: ((String) -> Void)?

    init(
        defaults: UserDefaults = .standard,
        transcription: TranscriptionService? = nil,
        cleanup: LanguagePassService? = nil,
        dictionary: DictionaryStore? = nil,
        modelsDirectory: URL = TranscriptionService.modelsDirectory,
        languageModelsDirectory: URL = LanguagePassService.modelsDirectory,
        settingsChanged: ((String) -> Void)? = nil
    ) {
        self.defaults = defaults
        self.transcription = transcription
        self.cleanup = cleanup
        self.dictionary = dictionary
        self.modelsDirectory = modelsDirectory
        self.languageModelsDirectory = languageModelsDirectory
        self.settingsChanged = settingsChanged
    }

    func handle(_ request: AppControlRequest) async -> AppControlResponse {
        do {
            switch request.command {
            case "status", "settings.get":
                var values = settingsSnapshot()
                if let key = request.key {
                    guard let value = values[key] else { throw invalid("Unknown setting: \(key)") }
                    values = [key: value]
                }
                return response(values: values)
            case "settings.set":
                guard transcription?.isDictationInProgress != true else {
                    throw invalid("Finish dictating before changing settings.")
                }
                guard let key = request.key, let value = request.value else {
                    throw invalid("Use settings set KEY VALUE.")
                }
                try updateSetting(key, value: value)
                settingsChanged?(key)
                return response(values: settingsSnapshot())
            case "models.prepare":
                let service = transcriptionService()
                guard !service.isDictationInProgress else { throw invalid("Dictation is in progress.") }
                try await prepareModels(service)
                return response(values: settingsSnapshot())
            case "transcribe":
                guard let path = request.path else { throw invalid("Provide a mono 16 kHz WAV path.") }
                return try await transcribeFile(URL(fileURLWithPath: path))
            default:
                throw invalid("Unknown command: \(request.command)")
            }
        } catch {
            return AppControlResponse(ok: false, message: error.localizedDescription, values: [:], text: nil, rawText: nil)
        }
    }

    private func settingsSnapshot() -> [String: String] {
        [
            "streaming": String((transcription?.selectedBackend
                ?? TranscriptionService.configuredBackend(defaults: defaults)) == .hexStreaming),
            "cleanup": String(defaults.object(forKey: Defaults.languagePassEnabled) == nil
                || defaults.bool(forKey: Defaults.languagePassEnabled)),
            "style": defaults.string(forKey: Defaults.languagePassStyle) ?? LanguagePassStyle.defaultStyle.rawValue,
            "shortcut": defaults.string(forKey: Defaults.hotkeyTrigger) ?? HotkeyTrigger.defaultTrigger.rawValue,
            "indicator": defaults.string(forKey: Defaults.overlayStyle) ?? "crab",
            "color": defaults.string(forKey: Defaults.crabColorVariant) ?? "ocean",
            "engine": transcription?.selectedBackend.rawValue
                ?? TranscriptionService.configuredBackend(defaults: defaults).rawValue,
            "modelState": transcription.map { String(describing: $0.modelState) } ?? "unloaded",
            "cleanupModel": cleanup?.selectedModelID ?? (MiniTrialConfiguration.isEnabled ? MiniCleanupEngine.modelID : LanguagePassModelOption.defaultID),
            "cleanupState": cleanup.map { String(describing: $0.modelState) } ?? "unloaded",
            "busy": String(transcription?.isDictationInProgress ?? false),
        ]
    }

    private func updateSetting(_ key: String, value: String) throws {
        switch key {
        case "streaming":
            let enabled = try boolean(value)
            let backend: TranscriptionBackend = enabled ? .hexStreaming : .parakeet
            defaults.set(enabled, forKey: Defaults.streamingTranscriptionEnabled)
            defaults.set(backend.rawValue, forKey: Defaults.transcriptionBackend)
            if let transcription, transcription.selectedBackend != backend {
                transcription.selectedBackend = backend
                Task { await transcription.loadModel() }
            }
        case "cleanup":
            let enabled = try boolean(value)
            defaults.set(enabled, forKey: Defaults.languagePassEnabled)
            cleanup?.isEnabled = enabled
        case "style":
            let raw = value == "normal" ? "standard" : value
            guard let style = LanguagePassStyle(rawValue: raw) else { throw invalid("Style must be normal, casual, or formal.") }
            defaults.set(style.rawValue, forKey: Defaults.languagePassStyle)
            cleanup?.selectedStyle = style
        case "shortcut":
            guard HotkeyTrigger(rawValue: value) != nil else { throw invalid("Unknown shortcut: \(value)") }
            defaults.set(value, forKey: Defaults.hotkeyTrigger)
        case "indicator":
            let raw = value == "classic" ? OverlayStyle.capsule.rawValue : value
            guard let style = OverlayStyle(rawValue: raw), style != .off else {
                throw invalid("Indicator must be crab, classic, or glass.")
            }
            defaults.set(style.rawValue, forKey: Defaults.overlayStyle)
        case "color":
            guard CrabColorVariant(rawValue: value) != nil else { throw invalid("Unknown crab color: \(value)") }
            defaults.set(value, forKey: Defaults.crabColorVariant)
        default:
            throw invalid("Unknown setting: \(key)")
        }
        defaults.synchronize()
    }

    private func prepareModels(_ service: TranscriptionService) async throws {
        switch service.modelState {
        case .unloaded, .error:
            await service.loadModel()
        case .loading, .downloading, .ready:
            break
        }
        if case .error(let message) = service.modelState { throw invalid(message) }
        try await service.waitUntilReady()
    }

    private func transcriptionService() -> TranscriptionService {
        if let transcription { return transcription }
        let service = TranscriptionService(defaults: defaults, modelsDirectory: modelsDirectory)
        transcription = service
        return service
    }

    private func transcribeFile(_ url: URL) async throws -> AppControlResponse {
        let service = transcriptionService()
        guard !service.isDictationInProgress else { throw invalid("Dictation is in progress.") }
        service.isDictationInProgress = true
        defer { service.isDictationInProgress = false }
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1,
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { throw invalid("Audio must be mono 16 kHz WAV.") }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw invalid("Audio has no PCM samples.") }
        let samples = AudioSignalAnalysis.trimmingTrailingSilence(
            from: Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))), sampleRate: 16000
        )
        let signal = AudioSignalAnalysis.analyze(samples: samples)
        guard samples.count >= AudioRecorder.minimumSamples,
            signal.hasSustainedSpeechLikeAudio(sampleRate: 16000) else {
            return response(values: ["status": "silent"], text: "", rawText: "")
        }
        try await prepareModels(service)
        let result = try await service.transcribeWithTiming(audioSamples: samples)
        if TranscriptHallucinationFilter.shouldDrop(text: result.result.finalText,
            recordingDuration: Double(samples.count) / 16000, signal: signal) {
            return response(values: ["status": "lowInformation"], text: "", rawText: result.result.rawText)
        }
        let language = cleanup ?? MiniTrialConfiguration.makeLanguagePassService(defaults: defaults, modelsDirectory: languageModelsDirectory)
        cleanup = language
        if language.isEnabled { await language.prepareIfNeeded() }
        let dictionary = dictionary ?? DictionaryStore.defaultStore()
        self.dictionary = dictionary
        let corrected = DictionaryReplacer.replace(result.result.finalText, entries: dictionary.entries)
        let cleaned = await language.process(rawText: result.result.rawText, baseText: corrected)
        return response(values: ["engine": result.timing.engineID,
                                 "engineMs": String(result.timing.engineWallMs),
                                 "cleanupMs": cleaned.wallMs.map(String.init) ?? "0"],
                        text: cleaned.finalText, rawText: result.result.rawText)
    }

    private func response(values: [String: String], text: String? = nil, rawText: String? = nil) -> AppControlResponse {
        AppControlResponse(ok: true, message: nil, values: values, text: text, rawText: rawText)
    }

    private func boolean(_ value: String) throws -> Bool {
        switch value {
        case "true", "on": return true
        case "false", "off": return false
        default: throw invalid("Use on/off or true/false.")
        }
    }

    private func invalid(_ message: String) -> NSError {
        NSError(domain: "ShoutOut.CLI", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
