import CoreML
import CryptoKit
import Foundation

enum MiniCleanupError: Error {
    case invalidVocabulary
    case invalidModelOutput
    case missingPrediction
    case unexpectedModelAssets
}

public struct MiniCleanupResult: Sendable {
    public let candidateText: String?
    public let finalText: String
    public let fallbackReason: String?
    public let elapsedMilliseconds: Double
    public let wordDeleteProbabilities: [Double]?
    public let windows: [MiniCleanupWindow]

    public var windowCount: Int { windows.count }
}

public actor MiniCleanupEngine {
    public static let modelID = "native-mini-2026-10-21"

    typealias Predictor = @Sendable ([Int32], [Int32]) throws -> [Float]

    private let modelDirectory: URL
    private var tokenizer: MiniCleanupTokenizer?
    private var model: MLModel?
    private var compiledModelURL: URL?
    private let testPredictor: Predictor?

    public init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
        self.testPredictor = nil
    }

    init(tokenizer: MiniCleanupTokenizer, predictor: @escaping Predictor) {
        self.modelDirectory = URL(fileURLWithPath: "/")
        self.tokenizer = tokenizer
        self.testPredictor = predictor
    }

    public func prepare() throws {
        if tokenizer != nil && (model != nil || testPredictor != nil) { return }
        let vocabularyURL = modelDirectory.appendingPathComponent("vocab.txt")
        let vocabularyData = try Data(contentsOf: vocabularyURL)
        let configURL = modelDirectory.appendingPathComponent("tokenizer-config.json")
        let packageURL = modelDirectory.appendingPathComponent("mini-fixed256.mlpackage")
        guard Self.sha256(vocabularyData) == "07eced375cec144d27c900241f3e339478dec958f92fddbc551f295c992038a3",
              Self.sha256(try Data(contentsOf: configURL)) == "7a248d081af1990bbbb20e98f58f07759f13991aec65a97858bdfd593697efc8",
              try Self.packageSHA256(packageURL) == "6c62bb511b9f639998907e578b062d1932e6c79ad55dea6c94fa47f79edc93f5" else {
            throw MiniCleanupError.unexpectedModelAssets
        }
        let vocabularyText = String(decoding: vocabularyData, as: UTF8.self)
        let tokenizer = try MiniCleanupTokenizer(vocabularyText: vocabularyText)
        let compiledURL = try MLModel.compileModel(at: packageURL)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let model: MLModel
        do {
            model = try MLModel(contentsOf: compiledURL, configuration: configuration)
        } catch {
            try? FileManager.default.removeItem(at: compiledURL)
            throw error
        }
        self.tokenizer = tokenizer
        self.model = model
        self.compiledModelURL = compiledURL
    }

    public func unload() {
        model = nil
        if let compiledModelURL { try? FileManager.default.removeItem(at: compiledModelURL) }
        compiledModelURL = nil
        if testPredictor == nil { tokenizer = nil }
    }

    deinit {
        if let compiledModelURL { try? FileManager.default.removeItem(at: compiledModelURL) }
    }

    public func cleanup(source: String) -> MiniCleanupResult {
        let start = ContinuousClock.now
        guard !source.isEmpty else {
            return MiniCleanupResult(candidateText: source, finalText: source, fallbackReason: nil,
                                     elapsedMilliseconds: 0, wordDeleteProbabilities: [], windows: [])
        }
        do {
            try prepare()
            guard let tokenizer else { throw MiniCleanupError.invalidVocabulary }
            let words = tokenizer.words(in: source)
            guard !words.isEmpty else {
                return MiniCleanupResult(candidateText: source, finalText: source, fallbackReason: nil,
                                         elapsedMilliseconds: elapsed(since: start),
                                         wordDeleteProbabilities: [], windows: [])
            }
            let windows = try tokenizer.windows(for: words)
            var sums = Array(repeating: 0.0, count: words.count)
            var counts = Array(repeating: 0, count: words.count)
            for window in windows {
                let ids = window.inputIDs + Array(repeating: tokenizer.paddingID,
                                                   count: MiniCleanupTokenizer.maxLength - window.inputIDs.count)
                let mask = window.attentionMask + Array(repeating: 0,
                                                         count: MiniCleanupTokenizer.maxLength - window.attentionMask.count)
                let logits = try predict(ids: ids, mask: mask)
                guard logits.count == MiniCleanupTokenizer.maxLength * 2 else {
                    throw MiniCleanupError.invalidModelOutput
                }
                guard logits.prefix(window.inputIDs.count * 2).allSatisfy(\.isFinite) else {
                    throw MiniCleanupError.invalidModelOutput
                }
                for (wordIndex, position) in window.firstPositions {
                    let keepLogit = Double(logits[position * 2])
                    let deleteLogit = Double(logits[position * 2 + 1])
                    guard keepLogit.isFinite && deleteLogit.isFinite else {
                        throw MiniCleanupError.invalidModelOutput
                    }
                    let probability = 1 / (1 + exp(keepLogit - deleteLogit))
                    guard probability.isFinite else { throw MiniCleanupError.invalidModelOutput }
                    sums[wordIndex] += probability
                    counts[wordIndex] += 1
                }
            }
            guard counts.allSatisfy({ $0 > 0 }) else { throw MiniCleanupError.missingPrediction }
            let probabilities = zip(sums, counts).map { $0 / Double($1) }
            let candidate = Self.reconstruct(source: source, words: words,
                                             delete: probabilities.map { $0 >= 0.98 })
            return MiniCleanupResult(candidateText: candidate, finalText: candidate, fallbackReason: nil,
                                     elapsedMilliseconds: elapsed(since: start),
                                     wordDeleteProbabilities: probabilities, windows: windows)
        } catch {
            return MiniCleanupResult(candidateText: nil, finalText: source,
                                     fallbackReason: String(describing: error),
                                     elapsedMilliseconds: elapsed(since: start),
                                     wordDeleteProbabilities: nil, windows: [])
        }
    }

    static func reconstruct(source: String, words: [MiniCleanupWord], delete: [Bool]) -> String {
        guard words.count == delete.count, let first = words.first, let last = words.last else { return source }
        let kept = words.indices.filter { !delete[$0] }
        guard let firstKept = kept.first else {
            return String(source[..<first.range.lowerBound]) + String(source[last.range.upperBound...])
        }
        var result = String(source[..<first.range.lowerBound])
        result += words[firstKept].text
        for index in kept.dropFirst() {
            result += source[words[index - 1].range.upperBound..<words[index].range.lowerBound]
            result += words[index].text
        }
        result += source[last.range.upperBound...]
        return result
    }

    private func predict(ids: [Int32], mask: [Int32]) throws -> [Float] {
        if let testPredictor { return try testPredictor(ids, mask) }
        guard let model else { throw MiniCleanupError.invalidModelOutput }
        let idsArray = try MLMultiArray(shape: [1, 256], dataType: .int32)
        let maskArray = try MLMultiArray(shape: [1, 256], dataType: .int32)
        let idsPointer = idsArray.dataPointer.bindMemory(to: Int32.self, capacity: 256)
        let maskPointer = maskArray.dataPointer.bindMemory(to: Int32.self, capacity: 256)
        for position in 0..<256 {
            idsPointer[position] = ids[position]
            maskPointer[position] = mask[position]
        }
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: idsArray),
            "attention_mask": MLFeatureValue(multiArray: maskArray),
        ])
        let prediction = try model.prediction(from: input)
        guard let logits = prediction.featureValue(for: "logits")?.multiArrayValue,
              logits.dataType == .float32, logits.shape.map(\.intValue) == [1, 256, 2] else {
            throw MiniCleanupError.invalidModelOutput
        }
        let pointer = logits.dataPointer.bindMemory(to: Float.self, capacity: 512)
        let tokenStride = logits.strides[1].intValue
        let classStride = logits.strides[2].intValue
        return (0..<256).flatMap { position in
            [pointer[position * tokenStride], pointer[position * tokenStride + classStride]]
        }
    }

    private func elapsed(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func packageSHA256(_ packageURL: URL) throws -> String {
        guard let enumerator = FileManager.default.enumerator(at: packageURL,
                                                               includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw MiniCleanupError.unexpectedModelAssets
        }
        let files = enumerator.allObjects.compactMap { $0 as? URL }.sorted { $0.path < $1.path }
        var digest = SHA256()
        for file in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            let relativePath = String(file.path.dropFirst(packageURL.path.count + 1))
            digest.update(data: Data(relativePath.utf8))
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                digest.update(data: chunk)
            }
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
