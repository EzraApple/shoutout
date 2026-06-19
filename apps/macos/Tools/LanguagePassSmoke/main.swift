import Foundation
import Hub
import MLXLLM
import MLXLMCommon
import ShoutOutCore
import Tokenizers

struct SmokeCase {
    enum Expectation: Equatable {
        case requiredRewrite
        case safeRewriteOrFallback
    }

    var name: String
    var input: String
    var style: LanguagePassStyle
    var expectedFragments: [String]
    var rejectedFragments: [String]
    var expectation: Expectation

    init(
        name: String,
        input: String,
        style: LanguagePassStyle = .defaultStyle,
        expectedFragments: [String],
        rejectedFragments: [String],
        expectation: Expectation
    ) {
        self.name = name
        self.input = input
        self.style = style
        self.expectedFragments = expectedFragments
        self.rejectedFragments = rejectedFragments
        self.expectation = expectation
    }
}

@main
struct LanguagePassSmoke {
    static let defaultModelID = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"

    static var modelID: String {
        ProcessInfo.processInfo.environment["LANGUAGE_PASS_MODEL_ID"] ?? defaultModelID
    }

    static let cases: [SmokeCase] = [
        SmokeCase(
            name: "filler and repeat cleanup",
            input: "um can you can you send this over when you get a chance",
            expectedFragments: ["send this over", "get a chance"],
            rejectedFragments: ["um", "can you can you", "i can"],
            expectation: .safeRewriteOrFallback
        ),
        SmokeCase(
            name: "self correction keeps final choice",
            input: "i want to meet on tuesday wait no monday",
            expectedFragments: ["monday"],
            rejectedFragments: ["tuesday", "wait no", "wait, no"],
            expectation: .safeRewriteOrFallback
        ),
        SmokeCase(
            name: "short correction keeps final choice",
            input: "i want to meet on tuesday er monday",
            expectedFragments: ["monday"],
            rejectedFragments: ["tuesday", "er"],
            expectation: .safeRewriteOrFallback
        ),
        SmokeCase(
            name: "auto punctuation",
            input: "i think this works but maybe we should test it first",
            expectedFragments: ["this works", "test it first"],
            rejectedFragments: [],
            expectation: .requiredRewrite
        ),
        SmokeCase(
            name: "command wording stays intact",
            input: "open the settings panel and turn on the beta option",
            expectedFragments: ["settings panel", "beta option"],
            rejectedFragments: ["here", "sure"],
            expectation: .requiredRewrite
        ),
        SmokeCase(
            name: "casual wait-no wording stays intact",
            input: "wait no actually make it the smaller one",
            expectedFragments: ["wait", "actually", "smaller one"],
            rejectedFragments: [],
            expectation: .requiredRewrite
        ),
        SmokeCase(
            name: "casual style stays lowercase and unpunctuated",
            input: "um yeah yeah that works can you send it over",
            style: .casual,
            expectedFragments: ["yeah", "that works", "send it over"],
            rejectedFragments: ["um", ".", "?", "please", "certainly", "i can"],
            expectation: .requiredRewrite
        ),
        SmokeCase(
            name: "formal style keeps original words",
            input: "i can join monday probably around three",
            style: .formal,
            expectedFragments: ["I can join Monday", "around three"],
            rejectedFragments: ["I will", "Please", "certainly"],
            expectation: .requiredRewrite
        ),
    ]

    static func main() async throws {
        let startedAt = Date()
        print("Loading \(modelID)...")

        let container = try await loadContainer()
        print("Loaded in \(elapsedMilliseconds(since: startedAt))ms")

        var failures: [String] = []
        for smokeCase in cases {
            let result = try await run(smokeCase, container: container)
            if let failure = result {
                failures.append(failure)
            }
        }

        if failures.isEmpty {
            print("\nLanguage pass smoke passed (\(cases.count) cases).")
        } else {
            print("\nLanguage pass smoke failed:")
            for failure in failures {
                print("- \(failure)")
            }
            Foundation.exit(1)
        }
    }

    static func run(_ smokeCase: SmokeCase, container: ModelContainer) async throws -> String? {
        let startedAt = Date()
        let rawOutput = try await generate(
            input: smokeCase.input,
            style: smokeCase.style,
            container: container
        )
        let wallMs = elapsedMilliseconds(since: startedAt)
        let validation = LanguagePassValidator.validate(output: rawOutput, baseText: smokeCase.input)
        let finalText = validation.acceptedText ?? smokeCase.input
        let finalLower = finalText.lowercased()
        let rawCandidate = LanguagePassValidator.extractCandidate(from: rawOutput)

        print("\n[\(smokeCase.name)] \(wallMs)ms style=\(smokeCase.style.rawValue)")
        print("input: \(smokeCase.input)")
        print("raw: \(rawCandidate)")
        print("final: \(finalText)")
        print("accepted: \(validation.acceptedText != nil) fallback: \(validation.fallbackReason ?? "none")")

        if smokeCase.expectation == .requiredRewrite, validation.acceptedText == nil {
            return "\(smokeCase.name): expected accepted rewrite, got \(validation.fallbackReason ?? "no rewrite")"
        }

        if smokeCase.expectation == .safeRewriteOrFallback, validation.acceptedText == nil {
            return nil
        }

        for fragment in smokeCase.expectedFragments {
            if !finalLower.contains(fragment.lowercased()) {
                return "\(smokeCase.name): missing expected fragment '\(fragment)' in '\(finalText)'"
            }
        }

        for fragment in smokeCase.rejectedFragments {
            if finalLower.contains(fragment.lowercased()) {
                return "\(smokeCase.name): kept rejected fragment '\(fragment)' in '\(finalText)'"
            }
        }

        return nil
    }

    static func generate(input: String, style: LanguagePassStyle, container: ModelContainer) async throws -> String {
        let session = ChatSession(
            container,
            instructions: LanguagePassPrompt.systemInstructions(for: style),
            history: fewShotHistory(style: style),
            generateParameters: GenerateParameters(
                maxTokens: 96,
                maxKVSize: 2048,
                temperature: 0.0,
                topP: 1.0
            )
        )

        return try await session.respond(to: LanguagePassPrompt.userPrompt(for: input, style: style))
    }

    static func fewShotHistory(style: LanguagePassStyle) -> [Chat.Message] {
        LanguagePassPrompt.examples(for: style).flatMap { example in
            [
                Chat.Message.user(LanguagePassPrompt.userPrompt(for: example.input, style: style)),
                Chat.Message.assistant(example.output),
            ]
        }
    }

    static func loadContainer() async throws -> ModelContainer {
        let downloader = SwiftTransformersHubDownloader(
            hub: HubApi(downloadBase: modelsDirectory())
        )
        let configuration = ModelConfiguration(
            id: modelID,
            extraEOSTokens: ["<|im_end|>"]
        )
        return try await LLMModelFactory.shared.loadContainer(
            from: downloader,
            using: SwiftTransformersTokenizerLoader(),
            configuration: configuration
        ) { progress in
            let percent = Int(progress.fractionCompleted * 100)
            if percent > 0 {
                print("download: \(percent)%")
            }
        }
    }

    static func modelsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("com.ezraapple.shoutout")
            .appendingPathComponent("LanguageModels")
    }

    static func elapsedMilliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
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
