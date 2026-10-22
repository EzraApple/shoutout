import Foundation

struct MiniCleanupWord: Sendable {
    let range: Range<String.Index>
    let text: String
}

public struct MiniCleanupWindow: Sendable, Encodable {
    public let inputIDs: [Int32]
    public let attentionMask: [Int32]
    public let firstPositions: [Int: Int]
}

struct MiniCleanupTokenizer: Sendable {
    static let maxLength = 256
    static let overlap = 64

    let vocabulary: [String: Int32]
    let unknownID: Int32
    let classID: Int32
    let separatorID: Int32
    let paddingID: Int32

    init(vocabularyText: String) throws {
        var vocabulary: [String: Int32] = [:]
        for (index, token) in vocabularyText.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let value = String(token).trimmingCharacters(in: .newlines)
            if !value.isEmpty { vocabulary[value] = Int32(index) }
        }
        guard let unknownID = vocabulary["[UNK]"], let classID = vocabulary["[CLS]"],
              let separatorID = vocabulary["[SEP]"], let paddingID = vocabulary["[PAD]"] else {
            throw MiniCleanupError.invalidVocabulary
        }
        self.vocabulary = vocabulary
        self.unknownID = unknownID
        self.classID = classID
        self.separatorID = separatorID
        self.paddingID = paddingID
    }

    func words(in source: String) -> [MiniCleanupWord] {
        var words: [MiniCleanupWord] = []
        let scalars = source.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            if Self.isWhitespace(scalars[index]) {
                index = scalars.index(after: index)
                continue
            }
            let start = index
            repeat { index = scalars.index(after: index) }
            while index < scalars.endIndex && !Self.isWhitespace(scalars[index])
            words.append(MiniCleanupWord(range: start..<index, text: String(source[start..<index])))
        }
        return words
    }

    func windows(for words: [MiniCleanupWord]) throws -> [MiniCleanupWindow] {
        guard !words.isEmpty else { return [] }
        var tokenIDs: [Int32] = []
        var wordIDs: [Int] = []
        for (wordIndex, word) in words.enumerated() {
            for id in tokenize(word.text) {
                tokenIDs.append(id)
                wordIDs.append(wordIndex)
            }
        }
        guard !tokenIDs.isEmpty else { throw MiniCleanupError.missingPrediction }

        let contentLength = Self.maxLength - 2
        var windows: [MiniCleanupWindow] = []
        var covered = Set<Int>()
        var start = 0
        while start < tokenIDs.count {
            let end = min(start + contentLength, tokenIDs.count)
            let ids = [classID] + Array(tokenIDs[start..<end]) + [separatorID]
            var firstPositions: [Int: Int] = [:]
            for offset in 0..<(end - start) {
                let wordIndex = wordIDs[start + offset]
                if firstPositions[wordIndex] == nil { firstPositions[wordIndex] = offset + 1 }
            }
            covered.formUnion(firstPositions.keys)
            windows.append(MiniCleanupWindow(
                inputIDs: ids,
                attentionMask: Array(repeating: 1, count: ids.count),
                firstPositions: firstPositions
            ))
            if end == tokenIDs.count { break }
            start = end - Self.overlap
        }
        guard covered.count == words.count else { throw MiniCleanupError.missingPrediction }
        return windows
    }

    private func tokenize(_ word: String) -> [Int32] {
        let specialTokens = ["[UNK]", "[SEP]", "[PAD]", "[CLS]", "[MASK]"]
        var remaining = word[...]
        var ids: [Int32] = []
        while !remaining.isEmpty {
            let nextSpecial = specialTokens.compactMap { token -> (Range<String.Index>, String)? in
                guard let range = remaining.range(of: token) else { return nil }
                return (range, token)
            }.min { $0.0.lowerBound < $1.0.lowerBound }
            guard let (range, token) = nextSpecial else {
                ids.append(contentsOf: tokenizeBasic(String(remaining)))
                break
            }
            ids.append(contentsOf: tokenizeBasic(String(remaining[..<range.lowerBound])))
            if let id = vocabulary[token] { ids.append(id) }
            remaining = remaining[range.upperBound...]
        }
        return ids
    }

    private func tokenizeBasic(_ word: String) -> [Int32] {
        var cleaned = ""
        for scalar in word.unicodeScalars {
            if scalar.value == 0 || scalar.value == 0xFFFD || Self.isControl(scalar) { continue }
            if Self.isWhitespace(scalar) {
                cleaned.append(" ")
            } else if Self.isChinese(scalar) {
                cleaned.append(" ")
                cleaned.unicodeScalars.append(scalar)
                cleaned.append(" ")
            } else {
                cleaned.unicodeScalars.append(scalar)
            }
        }

        var ids: [Int32] = []
        for basic in cleaned.unicodeScalars.split(whereSeparator: { Self.isWhitespace($0) }) {
            let normalized = basic.map(String.init).joined().lowercased().decomposedStringWithCanonicalMapping
                .unicodeScalars.filter { $0.properties.generalCategory != .nonspacingMark }
                .map(String.init).joined()
            var segment = ""
            for scalar in normalized.unicodeScalars {
                if Self.isPunctuation(scalar) {
                    if !segment.isEmpty { ids.append(contentsOf: wordPieces(segment)); segment = "" }
                    ids.append(contentsOf: wordPieces(String(scalar)))
                } else {
                    segment.unicodeScalars.append(scalar)
                }
            }
            if !segment.isEmpty { ids.append(contentsOf: wordPieces(segment)) }
        }
        return ids
    }

    private func wordPieces(_ token: String) -> [Int32] {
        let scalars = Array(token.unicodeScalars)
        guard scalars.count <= 100 else { return [unknownID] }
        var pieces: [Int32] = []
        var start = 0
        while start < scalars.count {
            var match: (Int32, Int)?
            for end in stride(from: scalars.count, through: start + 1, by: -1) {
                let candidate = (start == 0 ? "" : "##") + scalars[start..<end].map(String.init).joined()
                if let id = vocabulary[candidate] { match = (id, end); break }
            }
            guard let (id, end) = match else { return [unknownID] }
            pieces.append(id)
            start = end
        }
        return pieces
    }

    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (0x09...0x0D).contains(value) || (0x1C...0x20).contains(value)
            || value == 0x85 || value == 0xA0 || value == 0x1680
            || (0x2000...0x200A).contains(value) || value == 0x2028 || value == 0x2029
            || value == 0x202F || value == 0x205F || value == 0x3000
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format: return !isWhitespace(scalar)
        default: return false
        }
    }

    private static func isChinese(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value)
            || (0x20000...0x2A6DF).contains(value) || (0x2A700...0x2B73F).contains(value)
            || (0x2B740...0x2B81F).contains(value) || (0x2B820...0x2CEAF).contains(value)
            || (0xF900...0xFAFF).contains(value) || (0x2F800...0x2FA1F).contains(value)
    }

    private static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if (33...47).contains(value) || (58...64).contains(value)
            || (91...96).contains(value) || (123...126).contains(value) { return true }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation: return true
        default: return false
        }
    }
}
