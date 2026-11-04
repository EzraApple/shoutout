import XCTest
@testable import ShoutOutCore

final class TranscriptTextDiffTests: XCTestCase {
    func testFillerRemovalPreservesBothVersions() {
        let before = "I, um, sent the note."
        let after = "I sent the note."
        let segments = TranscriptTextDiff.segments(from: before, to: after)
        XCTAssertTrue(segments.contains { $0.kind == .removed && $0.text.contains("um") })
        assertReconstruction(segments, before: before, after: after)
    }

    func testCapitalizationAndReplacementAreVisible() {
        let before = "meet alex on monday"
        let after = "Meet Alex on Tuesday"
        let segments = TranscriptTextDiff.segments(from: before, to: after)
        XCTAssertTrue(segments.contains { $0.kind == .removed && $0.text.contains("monday") })
        XCTAssertTrue(segments.contains { $0.kind == .added && $0.text.contains("Tuesday") })
        assertReconstruction(segments, before: before, after: after)
    }

    func testMultilineAndUnicodeRemainExact() {
        let before = "First line\nCafé ☕️ is open."
        let after = "First line\nThe café ☕️ is open!"
        let segments = TranscriptTextDiff.segments(from: before, to: after)
        assertReconstruction(segments, before: before, after: after)
    }

    func testLongMiddleUsesBoundedFallbackAndKeepsCommonEdges() {
        let sharedStart = "Start. "
        let sharedEnd = " End."
        let before = sharedStart + String(String(repeating: "old word ", count: 300).dropLast()) + sharedEnd
        let after = sharedStart + String(String(repeating: "new term ", count: 300).dropLast()) + sharedEnd
        let segments = TranscriptTextDiff.segments(from: before, to: after, maxMatrixCells: 100)
        XCTAssertEqual(segments.first, .init(kind: .unchanged, text: sharedStart))
        XCTAssertEqual(segments.last, .init(kind: .unchanged, text: sharedEnd))
        assertReconstruction(segments, before: before, after: after)
    }

    func testEmptyAndUnchangedText() {
        XCTAssertEqual(TranscriptTextDiff.segments(from: "", to: ""), [])
        XCTAssertEqual(TranscriptTextDiff.segments(from: "Hello", to: "Hello"),
                       [.init(kind: .unchanged, text: "Hello")])
        assertReconstruction(TranscriptTextDiff.segments(from: "", to: "Hello"), before: "", after: "Hello")
    }

    private func assertReconstruction(
        _ segments: [TranscriptTextDiff.Segment], before: String, after: String
    ) {
        XCTAssertEqual(segments.filter { $0.kind != .added }.map(\.text).joined(), before)
        XCTAssertEqual(segments.filter { $0.kind != .removed }.map(\.text).joined(), after)
    }
}
