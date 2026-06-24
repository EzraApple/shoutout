import Foundation
import Hub
import MLX
import MLXLLM
import MLXLMCommon
import ShoutOutCore
import Tokenizers

struct LanguagePassModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String

    fileprivate static let legacyDefaultID = "mlx-community/SmolLM2-135M-Instruct-8bit"
    fileprivate static let previousDefaultID = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    static let defaultID = "mlx-community/Llama-3.2-1B-Instruct-4bit"

    static let all: [LanguagePassModelOption] = [
        LanguagePassModelOption(
            id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            title: "Llama 3.2 1B",
            detail: "More reliable cleanup for casual style and filler removal, with moderate local memory use."
        )
    ]

    static func option(for id: String) -> LanguagePassModelOption {
        all.first { $0.id == id }
            ?? LanguagePassModelOption(id: id, title: id, detail: "Custom local language model")
    }
}

struct LanguagePassRunResult: Sendable {
    var finalText: String
    var inputText: String?
    var candidateText: String?
    var enabled: Bool
    var accepted: Bool
    var changed: Bool
    var wallMs: Int?
    var modelID: String?
    var fallbackReason: String?

    static func passthrough(
        _ text: String,
        enabled: Bool,
        wallMs: Int? = nil,
        modelID: String? = nil,
        fallbackReason: String,
        inputText: String? = nil,
        candidateText: String? = nil
    ) -> LanguagePassRunResult {
        LanguagePassRunResult(
            finalText: text,
            inputText: inputText ?? text,
            candidateText: candidateText,
            enabled: enabled,
            accepted: false,
            changed: false,
            wallMs: wallMs,
            modelID: modelID,
            fallbackReason: fallbackReason
        )
    }
}

struct LanguagePassRunSummary: Sendable {
    var date: Date
    var accepted: Bool
    var changed: Bool
    var wallMs: Int?
    var modelID: String?
    var fallbackReason: String?
}

@MainActor
final class LanguagePassService: ObservableObject {
    @Published var modelState: ModelState = .unloaded
    @Published var selectedModelID: String {
        didSet {
            UserDefaults.standard.set(selectedModelID, forKey: Defaults.languagePassModel)
            if selectedModelID != oldValue {
                unload()
                if isEnabled {
                    Task { await prepareIfNeeded() }
                }
            }
        }
    }
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Defaults.languagePassEnabled)
            RuntimeLog.write("languagePass enabled=\(isEnabled)")
            if isEnabled {
                warmUpIfEnabled()
            } else {
                unload()
            }
        }
    }
    @Published var selectedStyle: LanguagePassStyle {
        didSet {
            UserDefaults.standard.set(selectedStyle.rawValue, forKey: Defaults.languagePassStyle)
            RuntimeLog.write("languagePass style=\(selectedStyle.rawValue)")
        }
    }
    @Published private(set) var lastRunSummary: LanguagePassRunSummary?

    let availableModels = LanguagePassModelOption.all.map(\.id)

    private var modelContainer: ModelContainer?
    private var loadTask: Task<ModelContainer, Error>?
    private var loadGeneration = 0
    private let generationTimeoutNanoseconds: UInt64 = 1_200_000_000
    private static let mlxCacheLimitBytes = 0
    private static var didConfigureMLXMemory = false
    private static let modelCleanupVersion = 1
    private static let retiredModelIDs = [
        LanguagePassModelOption.legacyDefaultID,
        LanguagePassModelOption.previousDefaultID,
    ]

    static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ezraapple.shoutout"
        return appSupport
            .appendingPathComponent(bundleID)
            .appendingPathComponent("LanguageModels")
    }()

    var selectedModel: LanguagePassModelOption {
        LanguagePassModelOption.option(for: selectedModelID)
    }

    init() {
        let storedModel = UserDefaults.standard.string(forKey: Defaults.languagePassModel)
        if storedModel == LanguagePassModelOption.legacyDefaultID
            || storedModel == LanguagePassModelOption.previousDefaultID
        {
            self.selectedModelID = LanguagePassModelOption.defaultID
            UserDefaults.standard.set(LanguagePassModelOption.defaultID, forKey: Defaults.languagePassModel)
        } else {
            self.selectedModelID = storedModel ?? LanguagePassModelOption.defaultID
        }

        if UserDefaults.standard.object(forKey: Defaults.languagePassEnabled) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: Defaults.languagePassEnabled)
        }

        self.selectedStyle = LanguagePassStyle(
            storedValue: UserDefaults.standard.string(forKey: Defaults.languagePassStyle)
        )

        cleanupRetiredModelsIfNeeded()
        Self.configureMLXMemoryIfNeeded()
    }

    private func cleanupRetiredModelsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Defaults.languagePassModelCleanupVersion) < Self.modelCleanupVersion else {
            return
        }

        var completed = true
        for modelID in Self.retiredModelIDs where modelID != selectedModelID {
            completed = deleteCachedModelIfPresent(modelID: modelID) && completed
        }

        if completed {
            defaults.set(Self.modelCleanupVersion, forKey: Defaults.languagePassModelCleanupVersion)
        }
    }

    private func deleteCachedModelIfPresent(modelID: String) -> Bool {
        let url = Self.cachedModelDirectory(for: modelID)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return true
        }

        do {
            try FileManager.default.removeItem(at: url)
            RuntimeLog.write("languagePass cleanup removed retiredModel=\(modelID) path=\(url.path)")
            return true
        } catch {
            RuntimeLog.write("languagePass cleanup failed retiredModel=\(modelID) path=\(url.path) error=\(error)")
            return false
        }
    }

    private static func cachedModelDirectory(for modelID: String) -> URL {
        modelID.split(separator: "/").reduce(modelsDirectory.appendingPathComponent("models")) { url, component in
            url.appendingPathComponent(String(component))
        }
    }

    func prepareIfNeeded() async {
        guard isEnabled else { return }
        Self.configureMLXMemoryIfNeeded()
        if modelState == .ready, modelContainer != nil { return }

        guard let runtimeURL = Self.mlxMetalRuntimeURL() else {
            modelContainer = nil
            modelState = .error("Language cleanup is not available in this build.")
            RuntimeLog.write("languagePass unavailable missingMetalRuntime")
            return
        }

        if let loadTask {
            _ = try? await loadTask.value
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        let modelID = selectedModelID
        let downloader = SwiftTransformersHubDownloader(
            hub: HubApi(downloadBase: Self.modelsDirectory)
        )
        let tokenizerLoader = SwiftTransformersTokenizerLoader()

        modelState = .loading
        RuntimeLog.write("languagePass load start model=\(modelID) runtime=\(runtimeURL.path)")

        let task = Task<ModelContainer, Error> {
            let configuration = ModelConfiguration(
                id: modelID,
                extraEOSTokens: ["<|im_end|>"]
            )
            return try await LLMModelFactory.shared.loadContainer(
                from: downloader,
                using: tokenizerLoader,
                configuration: configuration
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.loadGeneration == generation, self.selectedModelID == modelID else {
                        return
                    }
                    self.modelState = .downloading(progress: progress.fractionCompleted)
                }
            }
        }

        loadTask = task
        do {
            let container = try await task.value
            guard loadGeneration == generation, selectedModelID == modelID else { return }
            modelContainer = container
            modelState = .ready
            Self.clearMLXCache(reason: "load_ready")
            RuntimeLog.write(
                "languagePass load ready model=\(modelID) \(Self.mlxMemoryDescription())"
            )
        } catch {
            guard loadGeneration == generation, selectedModelID == modelID else { return }
            modelContainer = nil
            modelState = .error(error.localizedDescription)
            Self.clearMLXCache(reason: "load_failed")
            RuntimeLog.write("languagePass load failed model=\(modelID) error=\(error)")
        }
        loadTask = nil
    }

    func warmUpIfEnabled(delayNanoseconds: UInt64 = 0) {
        guard isEnabled else { return }
        Self.configureMLXMemoryIfNeeded()
        Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            await self?.prepareIfNeeded()
        }
    }

    func process(rawText _: String, baseText: String) async -> LanguagePassRunResult {
        let startedAt = Date()
        let modelID = selectedModelID
        let style = selectedStyle

        guard isEnabled else {
            return .passthrough(
                baseText,
                enabled: false,
                fallbackReason: "disabled",
                inputText: baseText
            )
        }

        guard !baseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .passthrough(
                baseText,
                enabled: true,
                modelID: modelID,
                fallbackReason: "empty_input",
                inputText: baseText
            )
        }

        if modelState != .ready || modelContainer == nil {
            await prepareIfNeeded()
        }

        guard modelState == .ready, let container = modelContainer else {
            let result = LanguagePassRunResult.passthrough(
                baseText,
                enabled: true,
                modelID: modelID,
                fallbackReason: "model_not_ready",
                inputText: baseText
            )
            recordSummary(result)
            return result
        }

        Self.clearMLXCache(reason: "process_start")
        let memoryBefore = Self.mlxMemoryDescription()
        defer {
            Self.clearMLXCache(reason: "process_end")
        }

        do {
            let output = try await runWithTimeout(seconds: generationTimeoutNanoseconds) {
                try await Self.generateCleanup(container: container, baseText: baseText, style: style)
            }
            let wallMs = Self.elapsedMilliseconds(since: startedAt)
            let memoryAfter = Self.mlxMemoryDescription()
            let candidateText = LanguagePassValidator.extractCandidate(from: output)
            let validation = LanguagePassValidator.validate(candidate: candidateText, baseText: baseText)
            guard let acceptedText = validation.acceptedText else {
                let result = LanguagePassRunResult.passthrough(
                    baseText,
                    enabled: true,
                    wallMs: wallMs,
                    modelID: modelID,
                    fallbackReason: validation.fallbackReason ?? "rejected",
                    inputText: baseText,
                    candidateText: candidateText
                )
                recordSummary(result)
                RuntimeLog.write(
                    "languagePass rejected model=\(modelID) style=\(style.rawValue) wallMs=\(wallMs) memoryBefore={\(memoryBefore)} memoryAfter={\(memoryAfter)}"
                )
                return result
            }

            let result = LanguagePassRunResult(
                finalText: acceptedText,
                inputText: baseText,
                candidateText: candidateText,
                enabled: true,
                accepted: true,
                changed: acceptedText != baseText,
                wallMs: wallMs,
                modelID: modelID,
                fallbackReason: nil
            )
            recordSummary(result)
            RuntimeLog.write(
                "languagePass accepted model=\(modelID) style=\(style.rawValue) wallMs=\(wallMs) inputChars=\(baseText.count) outputChars=\(acceptedText.count) memoryBefore={\(memoryBefore)} memoryAfter={\(memoryAfter)}"
            )
            return result
        } catch {
            let wallMs = Self.elapsedMilliseconds(since: startedAt)
            let memoryAfter = Self.mlxMemoryDescription()
            let fallbackReason = Task.isCancelled ? "cancelled" : "generation_failed"
            let result = LanguagePassRunResult.passthrough(
                baseText,
                enabled: true,
                wallMs: wallMs,
                modelID: modelID,
                fallbackReason: fallbackReason,
                inputText: baseText
            )
            recordSummary(result)
            RuntimeLog.write("languagePass fallback model=\(modelID) wallMs=\(wallMs) error=\(error) memoryBefore={\(memoryBefore)} memoryAfter={\(memoryAfter)}")
            return result
        }
    }

    func unload() {
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        modelContainer = nil
        modelState = .unloaded
        Self.clearMLXCache(reason: "unload")
    }

    nonisolated private static func generateCleanup(
        container: ModelContainer,
        baseText: String,
        style: LanguagePassStyle
    ) async throws -> String {
        let session = ChatSession(
            container,
            instructions: LanguagePassPrompt.systemInstructions(for: style),
            history: Self.fewShotHistory(style: style, input: baseText),
            generateParameters: GenerateParameters(
                maxTokens: 96,
                maxKVSize: 2048,
                temperature: 0.0,
                topP: 1.0
            )
        )
        let output = try await session.respond(to: LanguagePassPrompt.userPrompt(for: baseText, style: style))
        let candidate = LanguagePassValidator.extractCandidate(from: output)
        guard let retryPrompt = LanguagePassPrompt.retryPrompt(
            for: baseText,
            style: style,
            previousOutput: candidate
        ) else {
            return output
        }

        let retrySession = ChatSession(
            container,
            instructions: LanguagePassPrompt.systemInstructions(for: style),
            history: [],
            generateParameters: GenerateParameters(
                maxTokens: 48,
                maxKVSize: 2048,
                temperature: 0.0,
                topP: 1.0
            )
        )
        return try await retrySession.respond(to: retryPrompt)
    }

    nonisolated private static func fewShotHistory(style: LanguagePassStyle, input: String) -> [Chat.Message] {
        LanguagePassPrompt.examples(for: style, input: input).flatMap { example in
            [
                Chat.Message.user(LanguagePassPrompt.userPrompt(for: example.input, style: style)),
                Chat.Message.assistant(example.output),
            ]
        }
    }

    private func runWithTimeout<T: Sendable>(
        seconds timeoutNanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw LanguagePassError.timedOut
            }

            guard let value = try await group.next() else {
                throw LanguagePassError.timedOut
            }
            group.cancelAll()
            return value
        }
    }

    private func recordSummary(_ result: LanguagePassRunResult) {
        let inputMetrics = Self.textMetrics(result.inputText ?? "")
        let candidateMetrics = result.candidateText.map(Self.textMetrics)
        let finalMetrics = Self.textMetrics(result.finalText)
        lastRunSummary = LanguagePassRunSummary(
            date: Date(),
            accepted: result.accepted,
            changed: result.changed,
            wallMs: result.wallMs,
            modelID: result.modelID,
            fallbackReason: result.fallbackReason
        )
        RuntimeLog.write(
            [
                "languagePass result",
                "enabled=\(result.enabled)",
                "accepted=\(result.accepted)",
                "changed=\(result.changed)",
                "wallMs=\(result.wallMs.map(String.init) ?? "na")",
                "model=\(result.modelID ?? "none")",
                "style=\(selectedStyle.rawValue)",
                "fallback=\(result.fallbackReason ?? "none")",
                "inputChars=\(inputMetrics.characters)",
                "inputWords=\(inputMetrics.words)",
                "candidatePresent=\(result.candidateText != nil)",
                "candidateChars=\(candidateMetrics?.characters ?? 0)",
                "candidateWords=\(candidateMetrics?.words ?? 0)",
                "finalChars=\(finalMetrics.characters)",
                "finalWords=\(finalMetrics.words)",
            ].joined(separator: " ")
        )
    }

    private static func textMetrics(_ text: String) -> (characters: Int, words: Int) {
        (
            characters: text.count,
            words: text.split { $0.isWhitespace || $0.isNewline }.count
        )
    }

    private static func elapsedMilliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }

    private static func configureMLXMemoryIfNeeded() {
        guard !didConfigureMLXMemory else { return }
        didConfigureMLXMemory = true
        Memory.cacheLimit = mlxCacheLimitBytes
        Memory.peakMemory = 0
        Memory.clearCache()
        RuntimeLog.write(
            "languagePass mlxMemory configured cacheLimit=\(mlxCacheLimitBytes) \(mlxMemoryDescription())"
        )
    }

    private static func clearMLXCache(reason: String) {
        Stream().synchronize()
        Memory.clearCache()
        RuntimeLog.write("languagePass mlxMemory clear reason=\(reason) \(mlxMemoryDescription())")
    }

    private static func mlxMemoryDescription() -> String {
        let snapshot = Memory.snapshot()
        return "active=\(snapshot.activeMemory) cache=\(snapshot.cacheMemory) peak=\(snapshot.peakMemory) cacheLimit=\(Memory.cacheLimit)"
    }

    private static func mlxMetalRuntimeURL() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let executableURL = Bundle.main.executableURL {
            let executableDirectory = executableURL.deletingLastPathComponent()
            candidates.append(executableDirectory.appendingPathComponent("mlx.metallib"))
            candidates.append(executableDirectory.appendingPathComponent("Resources/mlx.metallib"))
            candidates.append(executableDirectory.appendingPathComponent("Resources/default.metallib"))
        }

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("mlx-swift_Cmlx.bundle/default.metallib"))
            candidates.append(resourceURL.appendingPathComponent("default.metallib"))
        }

        candidates.append(Bundle.main.bundleURL.appendingPathComponent("mlx-swift_Cmlx.bundle/default.metallib"))
        candidates.append(URL(fileURLWithPath: "default.metallib"))

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

}

private enum LanguagePassError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Language cleanup timed out."
        }
    }
}

private struct SwiftTransformersHubDownloader: MLXLMCommon.Downloader {
    let hub: HubApi

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        try await hub.snapshot(
            from: id,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: progressHandler
        )
    }
}

private struct SwiftTransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer = try await AutoTokenizer.from(modelFolder: directory, strict: false)
        return SwiftTransformersTokenizerAdapter(tokenizer: tokenizer)
    }
}

private struct SwiftTransformersTokenizerAdapter: MLXLMCommon.Tokenizer {
    let tokenizer: any Tokenizers.Tokenizer

    var bosToken: String? { tokenizer.bosToken }
    var eosToken: String? { tokenizer.eosToken }
    var unknownToken: String? { tokenizer.unknownToken }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        tokenizer.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        tokenizer.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        tokenizer.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        tokenizer.convertIdToToken(id)
    }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try tokenizer.applyChatTemplate(
            messages: messages,
            tools: tools,
            additionalContext: additionalContext
        )
    }
}
