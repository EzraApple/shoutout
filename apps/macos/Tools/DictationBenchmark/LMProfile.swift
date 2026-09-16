import Foundation
import MLXLMCommon

actor LMProfile {
    static let shared = LMProfile()
    private var entries: [Entry] = []

    struct Entry: Codable, Sendable {
        var input: String
        var stage: String
        var wallMs: Double
        var promptMs: Double?
        var decodeMs: Double?
        var promptTokens: Int?
        var outputTokens: Int?
    }

    func reset() { entries = [] }

    func save(_ entry: Entry) throws {
        entries.append(entry)
        let path = ProcessInfo.processInfo.environment["BENCH_LM_PROFILE"]!
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    static func respond(_ session: ChatSession, prompt: String, input: String, stage: String) async throws -> String {
        let start = ContinuousClock.now
        var output = ""
        var info: GenerateCompletionInfo?
        // Same chunk concatenation as ChatSession.respond, retaining its native timing event.
        for try await event in session.streamDetails(to: prompt, images: [], videos: []) {
            if let chunk = event.chunk { output += chunk }
            if case .info(let value) = event { info = value }
        }
        let elapsed = start.duration(to: .now).components
        try await shared.save(Entry(input: input, stage: stage,
            wallMs: Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15,
            promptMs: info.map { $0.promptTime * 1000 }, decodeMs: info.map { $0.generateTime * 1000 },
            promptTokens: info?.promptTokenCount, outputTokens: info?.generationTokenCount))
        return output
    }
}
