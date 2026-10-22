import Foundation
import MiniCleanup
import Darwin

private struct Input: Decodable {
    let id: String
    let source: String
}

private struct Output: Encodable {
    let id: String
    let repetition: Int
    let raw: String?
    let final: String
    let fallbackReason: String?
    let elapsedMilliseconds: Double
    let loadMilliseconds: Double
    let windowCount: Int
    let wordDeleteProbabilities: [Double]?
    let windows: [MiniCleanupWindow]?
}

@main
private enum MiniCleanupPanel {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        var options: [String: String] = [:]
        var trace = false
        var position = 0
        while position < arguments.count {
            let key = arguments[position]
            if key == "--trace" {
                trace = true
                position += 1
                continue
            }
            guard ["--model-dir", "--input", "--output", "--warmups", "--repetitions"].contains(key),
                  options[key] == nil, position + 1 < arguments.count else { throw PanelError.usage }
            options[key] = arguments[position + 1]
            position += 2
        }
        guard let modelPath = options["--model-dir"], let inputPath = options["--input"],
              let outputPath = options["--output"],
              let warmups = Int(options["--warmups"] ?? "0"), warmups >= 0,
              let repetitions = Int(options["--repetitions"] ?? "1"), repetitions > 0 else {
            throw PanelError.usage
        }
        let modelDirectory = URL(fileURLWithPath: modelPath, isDirectory: true)
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = URL(fileURLWithPath: outputPath)
        guard modelDirectory.pathComponents.contains(".private") else { throw PanelError.privateModelRequired }
        guard outputURL.pathComponents.contains(".private") else { throw PanelError.privateOutputRequired }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else { throw PanelError.outputExists }

        let engine = MiniCleanupEngine(modelDirectory: modelDirectory)
        let loadStart = ContinuousClock.now
        try await engine.prepare()
        let loadDuration = loadStart.duration(to: .now)
        let loadMilliseconds = Double(loadDuration.components.seconds) * 1_000
            + Double(loadDuration.components.attoseconds) / 1_000_000_000_000_000
        FileHandle.standardError.write(Data("model_load_ms=\(loadMilliseconds)\n".utf8))

        let data = try Data(contentsOf: inputURL)
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var rows: [Input] = []
        for (index, line) in String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let row: Input
            do {
                row = try decoder.decode(Input.self, from: Data(line.utf8))
            } catch {
                throw PanelError.invalidInput(index + 1, error)
            }
            rows.append(row)
        }
        for _ in 0..<warmups {
            for row in rows { _ = await engine.cleanup(source: row.source) }
        }
        var output = Data()
        for repetition in 0..<repetitions {
            for row in rows {
                let result = await engine.cleanup(source: row.source)
                let record = Output(id: row.id, repetition: repetition, raw: result.candidateText,
                                    final: result.finalText, fallbackReason: result.fallbackReason,
                                    elapsedMilliseconds: result.elapsedMilliseconds,
                                    loadMilliseconds: loadMilliseconds,
                                    windowCount: result.windowCount,
                                    wordDeleteProbabilities: trace ? result.wordDeleteProbabilities : nil,
                                    windows: trace ? result.windows : nil)
                output.append(try encoder.encode(record))
                output.append(0x0A)
            }
        }
        let descriptor = open(outputURL.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw PanelError.cannotWrite }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: output)
        try handle.close()
    }
}

private enum PanelError: Error, CustomStringConvertible {
    case usage
    case privateModelRequired
    case privateOutputRequired
    case outputExists
    case invalidInput(Int, Error)
    case cannotWrite

    var description: String {
        switch self {
        case .usage:
            return "Usage: MiniCleanupPanel --model-dir PRIVATE_DIR --input INPUT.jsonl --output PRIVATE_OUTPUT.jsonl [--trace] [--warmups N] [--repetitions N]"
        case .privateModelRequired: return "Model must be inside a .private directory"
        case .privateOutputRequired: return "Output must be inside a .private directory"
        case .outputExists: return "Output exists; refusing to overwrite"
        case let .invalidInput(line, error): return "Invalid input at line \(line): \(error)"
        case .cannotWrite: return "Could not create output"
        }
    }
}
