import Foundation

/// An exact, word-oriented edit script for showing cleanup changes inline.
public enum TranscriptTextDiff {
    public enum Kind: Equatable, Sendable {
        case unchanged
        case removed
        case added
    }

    public struct Segment: Equatable, Sendable {
        public let kind: Kind
        public let text: String

        public init(kind: Kind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// Common edges are removed before the bounded LCS calculation. A large,
    /// heavily edited middle falls back to two exact segments.
    public static func segments(
        from original: String,
        to revised: String,
        maxMatrixCells: Int = 120_000
    ) -> [Segment] {
        if original == revised {
            return original.isEmpty ? [] : [Segment(kind: .unchanged, text: original)]
        }
        let before = tokens(in: original)
        let after = tokens(in: revised)
        var prefix = 0
        while prefix < min(before.count, after.count), before[prefix] == after[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < min(before.count, after.count) - prefix,
              before[before.count - suffix - 1] == after[after.count - suffix - 1] {
            suffix += 1
        }

        let removed = Array(before[prefix..<(before.count - suffix)])
        let added = Array(after[prefix..<(after.count - suffix)])
        var result: [Segment] = []
        append(before.prefix(prefix).joined(), kind: .unchanged, to: &result)

        if !removed.isEmpty && !added.isEmpty,
           removed.count <= maxMatrixCells / added.count {
            appendMiddleDiff(removed, added, to: &result)
        } else {
            append(removed.joined(), kind: .removed, to: &result)
            append(added.joined(), kind: .added, to: &result)
        }

        append(before.suffix(suffix).joined(), kind: .unchanged, to: &result)
        return result
    }

    private static func tokens(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var currentKind: Int? = nil
        for character in text {
            let kind = character.isWhitespace ? 0 : (character.isLetter || character.isNumber ? 1 : 2)
            if kind == currentKind, kind != 2 {
                current.append(character)
            } else {
                if !current.isEmpty { result.append(current) }
                current = String(character)
                currentKind = kind
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func appendMiddleDiff(_ before: [String], _ after: [String], to result: inout [Segment]) {
        let width = after.count + 1
        var lengths = [Int32](repeating: 0, count: (before.count + 1) * width)
        for oldIndex in stride(from: before.count - 1, through: 0, by: -1) {
            for newIndex in stride(from: after.count - 1, through: 0, by: -1) {
                let index = oldIndex * width + newIndex
                lengths[index] = before[oldIndex] == after[newIndex]
                    ? lengths[(oldIndex + 1) * width + newIndex + 1] + 1
                    : max(lengths[(oldIndex + 1) * width + newIndex], lengths[index + 1])
            }
        }

        var oldIndex = 0
        var newIndex = 0
        while oldIndex < before.count || newIndex < after.count {
            if oldIndex < before.count, newIndex < after.count,
               before[oldIndex] == after[newIndex] {
                append(before[oldIndex], kind: .unchanged, to: &result)
                oldIndex += 1
                newIndex += 1
            } else if oldIndex < before.count,
                      (newIndex == after.count
                        || lengths[(oldIndex + 1) * width + newIndex]
                            >= lengths[oldIndex * width + newIndex + 1]) {
                append(before[oldIndex], kind: .removed, to: &result)
                oldIndex += 1
            } else {
                append(after[newIndex], kind: .added, to: &result)
                newIndex += 1
            }
        }
    }

    private static func append(_ text: String, kind: Kind, to result: inout [Segment]) {
        guard !text.isEmpty else { return }
        if let last = result.last, last.kind == kind {
            result[result.count - 1] = Segment(kind: kind, text: last.text + text)
        } else {
            result.append(Segment(kind: kind, text: text))
        }
    }
}
