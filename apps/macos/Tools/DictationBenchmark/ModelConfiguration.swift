import Foundation
import ShoutOutCore

// Only model identity/template adaptation differs from the production cleanup prompt.
enum BenchmarkLanguageConfiguration {
    static var modelID: String {
        ProcessInfo.processInfo.environment["BENCH_LM_MODEL"] ?? LanguagePassModelOption.defaultID
    }

    @MainActor static func modelDirectory(_ modelID: String) -> URL {
        if let directory = ProcessInfo.processInfo.environment["BENCH_LM_DIRECTORY"] {
            return URL(fileURLWithPath: directory)
        }
        return LanguagePassService.modelsDirectory.appendingPathComponent("models/" + modelID)
    }

    static func instructions(for style: LanguagePassStyle) -> String {
        let original = LanguagePassPrompt.systemInstructions(for: style)
        return modelID == LanguagePassModelOption.defaultID ? original : original.replacingOccurrences(
            of: "You are Llama, created by Meta. ", with: "")
    }

    static var context: [String: any Sendable]? {
        modelID.contains("Qwen") ? ["enable_thinking": false] : nil
    }
}
