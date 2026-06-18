import Foundation
import ShoutOutCore

enum ModelState: Equatable, Sendable {
    case unloaded
    case downloading(progress: Double)
    case loading
    case ready
    case error(String)

    var isReady: Bool {
        self == .ready
    }

    var startupProgress: Double? {
        switch self {
        case .downloading(let progress):
            return min(max(progress, 0), 1)
        case .loading, .ready:
            return 1
        case .unloaded, .error:
            return nil
        }
    }
}

struct TranscriptionTimingSnapshot: Sendable {
    var engineID: String
    var modelIdentifier: String
    var modelWaitMs: Int
    var engineWallMs: Int
    var postProcessMs: Int
    var firstTokenMs: Int?
    var enginePipelineMs: Int?
    var realTimeFactor: Double?
    var speedFactor: Double?
    var tokensPerSecond: Double?
    var fallbackCount: Int?

    var whisperWallMs: Int { engineWallMs }
    var whisperPipelineMs: Int? { enginePipelineMs }

    var logFields: String {
        [
            "engine=\(engineID)",
            "engineModel=\(modelIdentifier)",
            "modelWaitMs=\(modelWaitMs)",
            "engineWallMs=\(engineWallMs)",
            "postProcessMs=\(postProcessMs)",
            optionalMetric("firstTokenMs", firstTokenMs),
            optionalMetric("enginePipelineMs", enginePipelineMs),
            optionalMetric("rtf", realTimeFactor),
            optionalMetric("speedFactor", speedFactor),
            optionalMetric("tokensPerSecond", tokensPerSecond),
            optionalMetric("fallbacks", fallbackCount),
        ].compactMap { $0 }.joined(separator: " ")
    }

    private func optionalMetric(_ name: String, _ value: Int?) -> String? {
        guard let value else { return nil }
        return "\(name)=\(value)"
    }

    private func optionalMetric(_ name: String, _ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        return "\(name)=\(String(format: "%.3f", value))"
    }
}

@MainActor
class TranscriptionService: ObservableObject {
    @Published var modelState: ModelState = .unloaded
    @Published var selectedBackend: TranscriptionBackend {
        didSet {
            UserDefaults.standard.set(selectedBackend.rawValue, forKey: Defaults.transcriptionBackend)
            if selectedBackend != oldValue {
                activeEngine?.unload()
                activeEngine = nil
                appleDictationEngine?.unload()
                appleDictationEngine = nil
                appleDictationEngineIsReady = false
                appleDictationWarmupTask?.cancel()
                appleDictationWarmupTask = nil
                modelState = .unloaded
            }
        }
    }
    @Published var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "selectedModel")
            if selectedModel != oldValue, selectedBackend == .whisperKit {
                activeEngine?.unload()
                activeEngine = nil
                modelState = .unloaded
            }
        }
    }

    let availableModels = TranscriptionModelOption.all.map(\.id)
    let availableBackends = TranscriptionBackend.selectableCases

    private var activeEngine: TranscriptionEngine?
    private var appleDictationEngine: TranscriptionEngine?
    private var appleDictationEngineIsReady = false
    private var appleDictationWarmupTask: Task<Void, Never>?
    private var loadGeneration = 0
    private let appleDictationAutoSwitchDuration: TimeInterval = 15

    /// All model data lives here.
    /// App cleaners remove ~/Library/Application Support/<bundleID>/ on uninstall.
    static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ezraapple.shoutout"
        return appSupport.appendingPathComponent(bundleID).appendingPathComponent("Models")
    }()

    /// Total size of downloaded models on disk.
    var modelsDiskUsage: String {
        let url = Self.modelsDirectory
        guard FileManager.default.fileExists(atPath: url.path) else { return "0 MB" }
        let bytes = (try? FileManager.default.allocatedSizeOfDirectory(at: url)) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    init() {
        let backendRaw = UserDefaults.standard.string(forKey: Defaults.transcriptionBackend)
        let storedBackend = TranscriptionBackend(rawValue: backendRaw ?? "") ?? .whisperKit
        self.selectedBackend = TranscriptionBackend.selectableCases.contains(storedBackend)
            ? storedBackend
            : .appleSpeech
        let storedModel = UserDefaults.standard.string(forKey: "selectedModel")
            ?? TranscriptionModelOption.defaultID
        let normalizedModel = TranscriptionModelOption.all.contains { $0.id == storedModel }
            ? storedModel
            : TranscriptionModelOption.defaultID
        self.selectedModel = normalizedModel
        if normalizedModel != storedModel {
            UserDefaults.standard.set(normalizedModel, forKey: "selectedModel")
        }
    }

    var activeModelIdentifier: String {
        if let activeEngine {
            return activeEngine.modelIdentifier
        }

        switch selectedBackend {
        case .whisperKit:
            return selectedModel
        case .appleSpeech:
            return "apple-speech"
        case .appleDictation:
            return "apple-dictation"
        }
    }

    func loadModel() async {
        guard modelState != .loading else { return }
        if case .downloading = modelState { return }

        let backend = selectedBackend
        let engine = makeEngine(for: backend)
        activeEngine?.unload()
        activeEngine = engine
        loadGeneration += 1
        let generation = loadGeneration

        do {
            try await engine.load { [weak self] state in
                guard let self,
                    self.loadGeneration == generation,
                    self.selectedBackend == backend
                else {
                    return
                }
                self.modelState = state
            }
        } catch {
            guard loadGeneration == generation, selectedBackend == backend else { return }
            modelState = .error(error.localizedDescription)
            RuntimeLog.write(
                "model load failed backend=\(backend.rawValue) selected=\(engine.modelIdentifier) error=\(error)"
            )
        }
    }

    /// Delete all downloaded models from disk.
    func deleteAllModels() {
        activeEngine?.unload()
        activeEngine = nil
        appleDictationEngine?.unload()
        appleDictationEngine = nil
        appleDictationEngineIsReady = false
        appleDictationWarmupTask?.cancel()
        appleDictationWarmupTask = nil
        modelState = .unloaded
        try? FileManager.default.removeItem(at: Self.modelsDirectory)
    }

    func resetAfterTranscriptionTimeout() {
        loadGeneration += 1
        activeEngine?.unload()
        activeEngine = nil
        appleDictationEngine?.unload()
        appleDictationEngine = nil
        appleDictationEngineIsReady = false
        appleDictationWarmupTask?.cancel()
        appleDictationWarmupTask = nil
        modelState = .unloaded
        Task { await loadModel() }
    }

    /// Wait until the model is ready. If nothing is loading yet, kicks off a load.
    func waitUntilReady() async throws {
        if modelState == .ready, activeEngine != nil { return }

        // If idle or errored, start a fresh load
        let needsLoad: Bool
        switch modelState {
        case .unloaded, .error:
            needsLoad = true
        case .ready:
            needsLoad = activeEngine == nil
        default: needsLoad = false
        }
        if needsLoad {
            Task { await loadModel() }
            // Give loadModel a moment to set its state
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // Poll until ready or terminal error
        while true {
            if modelState == .ready { return }
            if case .error(let msg) = modelState {
                throw TranscriptionError.modelLoadFailed(msg)
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    func transcribe(audioSamples: [Float]) async throws -> DictationResult {
        try await transcribeWithTiming(audioSamples: audioSamples).result
    }

    func transcribeWithTiming(audioSamples: [Float]) async throws
        -> (result: DictationResult, timing: TranscriptionTimingSnapshot)
    {
        RuntimeLog.write(
            "transcription start samples=\(audioSamples.count) model=\(activeModelIdentifier)"
        )
        // Wait for the selected engine, or the long-form Apple engine when a recording needs it.
        let modelWaitStart = Date()
        let engine = try await engineForTranscription(audioSamples: audioSamples)
        let modelWaitMs = Self.elapsedMilliseconds(since: modelWaitStart)

        let engineStart = Date()
        let engineResult = try await engine.transcribe(audioSamples: audioSamples)
        let engineWallMs = Self.elapsedMilliseconds(since: engineStart)
        let rawText = engineResult.rawText
        let postProcessingOptions = TextPostProcessingOptions(
            removeFillerWords: UserDefaults.standard.object(forKey: "removeFillerWords") == nil
                || UserDefaults.standard.bool(forKey: "removeFillerWords"),
            applySpokenCommands: true,
            collapseWhitespace: true
        )
        let postProcessStart = Date()
        let finalText = TextPostProcessor.process(
            rawText,
            options: postProcessingOptions
        )
        let postProcessMs = Self.elapsedMilliseconds(since: postProcessStart)
        let timing = TranscriptionTimingSnapshot(
            engineID: engine.backend.rawValue,
            modelIdentifier: engine.modelIdentifier,
            modelWaitMs: modelWaitMs,
            engineWallMs: engineWallMs,
            postProcessMs: postProcessMs,
            firstTokenMs: engineResult.firstTokenMs,
            enginePipelineMs: engineResult.pipelineMs,
            realTimeFactor: engineResult.realTimeFactor,
            speedFactor: engineResult.speedFactor,
            tokensPerSecond: engineResult.tokensPerSecond,
            fallbackCount: engineResult.fallbackCount
        )
        RuntimeLog.write("transcription postprocessed rawLength=\(rawText.count) finalLength=\(finalText.count)")
        RuntimeLog.write("transcription timing \(timing.logFields)")
        return (DictationResult(rawText: rawText, finalText: finalText), timing)
    }

    func prepareLongFormEngineIfNeeded() async {
        guard selectedBackend == .appleSpeech else { return }
        guard !appleDictationEngineIsReady else { return }
        guard appleDictationWarmupTask == nil else { return }

#if swift(>=6.2)
        if #available(macOS 26.0, *) {
            RuntimeLog.write("appleDictation warmup scheduled")
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let engine = self.appleDictationEngine ?? AppleDictationTranscriptionEngine()
                    self.appleDictationEngine = engine
                    try await engine.load { _ in }
                    self.appleDictationEngineIsReady = true
                    RuntimeLog.write("appleDictation warmup ready")
                } catch {
                    self.appleDictationEngine?.unload()
                    self.appleDictationEngine = nil
                    self.appleDictationEngineIsReady = false
                    RuntimeLog.write("appleDictation warmup failed error=\(error)")
                }
                self.appleDictationWarmupTask = nil
            }
            appleDictationWarmupTask = task
        }
#endif
    }

    private func makeEngine(for backend: TranscriptionBackend) -> TranscriptionEngine {
        switch backend {
        case .whisperKit:
            return WhisperKitTranscriptionEngine(
                modelIdentifier: selectedModel,
                modelsDirectory: Self.modelsDirectory
            )
        case .appleSpeech:
            return AppleSpeechTranscriptionEngine()
        case .appleDictation:
#if swift(>=6.2)
            if #available(macOS 26.0, *) {
                return AppleDictationTranscriptionEngine()
            }
#endif
            return UnavailableTranscriptionEngine(
                backend: backend,
                message: "Apple Dictation requires macOS 26 and a Swift 6.2 toolchain."
            )
        }
    }

    private func engineForTranscription(audioSamples: [Float]) async throws -> TranscriptionEngine {
        if shouldUseAppleDictation(for: audioSamples) {
            return try await readyAppleDictationEngine()
        }

        try await waitUntilReady()
        guard let engine = activeEngine else {
            throw TranscriptionError.modelNotReady
        }
        return engine
    }

    private func shouldUseAppleDictation(for audioSamples: [Float]) -> Bool {
        guard selectedBackend == .appleSpeech else { return false }
        let duration = Double(audioSamples.count) / AudioRecorder.sampleRate
        guard duration >= appleDictationAutoSwitchDuration else { return false }

#if swift(>=6.2)
        if #available(macOS 26.0, *) {
            return true
        }
#endif
        return false
    }

    private func readyAppleDictationEngine() async throws -> TranscriptionEngine {
#if swift(>=6.2)
        if #available(macOS 26.0, *) {
            if let warmupTask = appleDictationWarmupTask {
                await warmupTask.value
            }
            if appleDictationEngineIsReady, let appleDictationEngine {
                return appleDictationEngine
            }

            let engine = appleDictationEngine ?? AppleDictationTranscriptionEngine()
            appleDictationEngine = engine
            if !appleDictationEngineIsReady {
                appleDictationWarmupTask = nil
                RuntimeLog.write("transcription autoswitch backend=appleDictation")
                do {
                    try await engine.load { [weak self] state in
                        guard let self, self.selectedBackend == .appleSpeech else { return }
                        self.modelState = state
                    }
                    appleDictationEngineIsReady = true
                } catch {
                    engine.unload()
                    appleDictationEngine = nil
                    appleDictationEngineIsReady = false
                    if selectedBackend == .appleSpeech, activeEngine != nil {
                        modelState = .ready
                    } else {
                        modelState = .error(error.localizedDescription)
                    }
                    throw error
                }
            }
            return engine
        }
#endif
        throw TranscriptionError.engineUnavailable("Apple Dictation requires macOS 26 and a Swift 6.2 toolchain.")
    }

    private static func elapsedMilliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}

// MARK: - FileManager Directory Size

extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> UInt64 {
        var totalSize: UInt64 = 0
        let enumerator = self.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [], errorHandler: nil)

        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [
                .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            ])
            totalSize += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return totalSize
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotReady
    case modelLoadFailed(String)
    case engineUnavailable(String)
    case speechRecognitionNotAuthorized(String)
    case audioConversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotReady: return "Transcription model is not ready"
        case .modelLoadFailed(let msg): return "Model failed to load: \(msg)"
        case .engineUnavailable(let msg): return msg
        case .speechRecognitionNotAuthorized(let status):
            return "Speech recognition permission is \(status)"
        case .audioConversionFailed(let msg):
            return "Audio conversion failed: \(msg)"
        }
    }
}

@MainActor
private final class UnavailableTranscriptionEngine: TranscriptionEngine {
    let backend: TranscriptionBackend
    let modelIdentifier: String
    private let message: String

    init(backend: TranscriptionBackend, message: String) {
        self.backend = backend
        self.modelIdentifier = backend.rawValue
        self.message = message
    }

    func load(updateState: @escaping @MainActor (ModelState) -> Void) async throws {
        updateState(.error(message))
        throw TranscriptionError.engineUnavailable(message)
    }

    func transcribe(audioSamples: [Float]) async throws -> EngineTranscriptionResult {
        throw TranscriptionError.engineUnavailable(message)
    }

    func unload() {}
}
