import XCTest
@testable import MiniCleanup

final class MiniCleanupTests: XCTestCase {
    private let vocabulary = """
    [PAD]
    [UNK]
    [CLS]
    [SEP]
    hello
    cafe
    東
    京
    !
    un
    ##seen
    [MASK]
    foo
    bar
    """

    func testUncasedPunctuationUnicodeAndSourceSpans() throws {
        let tokenizer = try MiniCleanupTokenizer(vocabularyText: vocabulary)
        let words = tokenizer.words(in: "  Café\t東京!  unseen ")
        XCTAssertEqual(words.map(\.text), ["Café", "東京!", "unseen"])
        let windows = try tokenizer.windows(for: words)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].inputIDs, [2, 5, 6, 7, 8, 9, 10, 3])
        XCTAssertEqual(windows[0].firstPositions, [0: 1, 1: 2, 2: 5])
    }

    func testOverflowIncludesContinuationWordsAndEveryWord() throws {
        let tokenizer = try MiniCleanupTokenizer(vocabularyText: vocabulary)
        let source = Array(repeating: "hello", count: 270).joined(separator: " ")
        let windows = try tokenizer.windows(for: tokenizer.words(in: source))
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].inputIDs.count, 256)
        XCTAssertEqual(windows[1].firstPositions[190], 1)
        XCTAssertEqual(windows[1].firstPositions[269], 80)
    }

    func testEmbeddedSpecialTokenStaysAtomic() throws {
        let tokenizer = try MiniCleanupTokenizer(vocabularyText: vocabulary)
        let words = tokenizer.words(in: "foo[MASK]bar [MASK],")
        let windows = try tokenizer.windows(for: words)
        XCTAssertEqual(windows[0].inputIDs, [2, 12, 11, 13, 11, 1, 3])
        XCTAssertEqual(windows[0].firstPositions, [0: 1, 1: 4])
    }

    func testReconstructionPreservesKeptSourceExactly() throws {
        let tokenizer = try MiniCleanupTokenizer(vocabularyText: vocabulary)
        let source = "  Café\t東京!  unseen \n"
        let words = tokenizer.words(in: source)
        XCTAssertEqual(MiniCleanupEngine.reconstruct(source: source, words: words,
                                                     delete: [false, true, false]),
                       "  Café  unseen \n")
        XCTAssertEqual(MiniCleanupEngine.reconstruct(source: source, words: words,
                                                     delete: [true, true, true]), "   \n")
    }

    func testValidDeletionAndNonFiniteFallback() async throws {
        let tokenizer = try MiniCleanupTokenizer(vocabularyText: vocabulary)
        let engine = MiniCleanupEngine(tokenizer: tokenizer) { ids, _ in
            var logits = Array(repeating: Float(0), count: 512)
            for position in 0..<ids.count where ids[position] == 4 {
                logits[position * 2 + 1] = 10
            }
            return logits
        }
        let result = await engine.cleanup(source: "hello\tCafé")
        XCTAssertEqual(result.finalText, "Café")
        XCTAssertNil(result.fallbackReason)
        XCTAssertEqual(result.wordDeleteProbabilities?.count, 2)

        let brokenEngine = MiniCleanupEngine(tokenizer: tokenizer) { _, _ in
            Array(repeating: Float.nan, count: 512)
        }
        let original = "hello\tCafé"
        let brokenResult = await brokenEngine.cleanup(source: original)
        XCTAssertEqual(brokenResult.finalText, original)
        XCTAssertNil(brokenResult.candidateText)
        XCTAssertNotNil(brokenResult.fallbackReason)

        let wrongSizeEngine = MiniCleanupEngine(tokenizer: tokenizer) { _, _ in [0] }
        let wrongSizeResult = await wrongSizeEngine.cleanup(source: original)
        XCTAssertEqual(wrongSizeResult.finalText, original)
        XCTAssertNil(wrongSizeResult.candidateText)
        XCTAssertNotNil(wrongSizeResult.fallbackReason)

        let allDeleteEngine = MiniCleanupEngine(tokenizer: tokenizer) { _, _ in
            var logits = Array(repeating: Float(0), count: 512)
            for position in 0..<256 { logits[position * 2 + 1] = 10 }
            return logits
        }
        let allDeleteResult = await allDeleteEngine.cleanup(source: "  hello\tCafé \n")
        XCTAssertEqual(allDeleteResult.finalText, "   \n")
        XCTAssertNil(allDeleteResult.fallbackReason)
    }

    func testExportedPythonTokenizerFixturesWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let assetPath = environment["MINI_CLEANUP_ASSET_DIR"],
              let fixturePath = environment["MINI_CLEANUP_TOKENIZER_FIXTURES"] else {
            throw XCTSkip("Set MINI_CLEANUP_ASSET_DIR and MINI_CLEANUP_TOKENIZER_FIXTURES")
        }
        let vocabulary = try String(contentsOfFile: assetPath + "/vocab.txt", encoding: .utf8)
        let fixtures = try JSONDecoder().decode(FixtureSet.self,
                                                from: Data(contentsOf: URL(fileURLWithPath: fixturePath)))
        let tokenizer = try MiniCleanupTokenizer(vocabularyText: vocabulary)
        for item in fixtures.cases {
            let words = tokenizer.words(in: item.input)
            XCTAssertEqual(words.map(\.text), item.sourceWords, item.name)
            let windows = try tokenizer.windows(for: words)
            XCTAssertEqual(windows.count, item.windows.count, item.name)
            for (actual, expected) in zip(windows, item.windows) {
                XCTAssertEqual(actual.inputIDs.map(Int.init), expected.inputIDs, item.name)
                XCTAssertEqual(actual.attentionMask.map(Int.init), expected.attentionMask, item.name)
                XCTAssertEqual(actual.firstPositions, expected.firstPositions, item.name)
            }
        }
    }
}

private struct FixtureSet: Decodable {
    let cases: [Fixture]
}

private struct Fixture: Decodable {
    let name: String
    let input: String
    let sourceWords: [String]
    let windows: [FixtureWindow]

    enum CodingKeys: String, CodingKey {
        case name, input, windows
        case sourceWords = "source_words"
    }
}

private struct FixtureWindow: Decodable {
    let inputIDs: [Int]
    let attentionMask: [Int]
    let firstPositions: [Int: Int]

    enum CodingKeys: String, CodingKey {
        case inputIDs = "input_ids"
        case attentionMask = "attention_mask"
        case firstPositions = "first_positions"
    }
}
