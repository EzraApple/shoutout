import Foundation

public enum TranscriptionHistorySearch {
    /// Searches visible transcript text, retaining the caller's chronological order.
    public static func search(
        _ entries: [TranscriptionHistoryEntry], query: String
    ) throws -> [TranscriptionHistoryEntry] {
        let terms = words(in: query)
        guard !terms.isEmpty else { return entries }
        return try entries.filter { entry in
            try Task.checkCancellation()
            let transcriptWords = words(in: entry.text)
            return terms.allSatisfy { term in
                transcriptWords.contains { word in
                    word.contains(term) || (term.count >= 4 && differsByOneEdit(term, word))
                }
            }
        }
    }

    private static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Allows one insertion, deletion, substitution, or adjacent transposition.
    private static func differsByOneEdit(_ query: String, _ word: String) -> Bool {
        let lhs = Array(query), rhs = Array(word)
        guard abs(lhs.count - rhs.count) <= 1 else { return false }
        var index = 0
        while index < min(lhs.count, rhs.count), lhs[index] == rhs[index] { index += 1 }
        if index == min(lhs.count, rhs.count) { return true }
        if lhs.count == rhs.count {
            if lhs.dropFirst(index + 1).elementsEqual(rhs.dropFirst(index + 1)) { return true }
            return index + 1 < lhs.count
                && lhs[index] == rhs[index + 1] && lhs[index + 1] == rhs[index]
                && lhs.dropFirst(index + 2).elementsEqual(rhs.dropFirst(index + 2))
        }
        if lhs.count > rhs.count {
            return lhs.dropFirst(index + 1).elementsEqual(rhs.dropFirst(index))
        }
        return lhs.dropFirst(index).elementsEqual(rhs.dropFirst(index + 1))
    }
}
