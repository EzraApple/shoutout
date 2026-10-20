import Foundation

private struct Capture: Decodable {
    let engine: String
    let name: String
    let text: String
}

@main
struct PipelineProbe {
    static func main() throws {
        let captures = try JSONDecoder().decode([Capture].self,
            from: FileHandle.standardInput.readDataToEndOfFile())
        let processed = captures.map { capture in
            ["engine": capture.engine, "name": capture.name, "baseText": TextPostProcessor.process(capture.text)]
        }
        let entries = [
            DictionaryEntry(phrase: "Maya Chen", aliases: ["Mayochen"]),
            DictionaryEntry(phrase: "PostgreSQL", aliases: ["post-GurSQL"]),
            DictionaryEntry(phrase: "Siobhan McKenzie", aliases: ["Siobhan Mackenzie"]),
        ]
        let examples = [
            "Mayochen is preparing the release plan.",
            "Maya Chen will review the post-GurSQL migration after lunch.",
            "Send this to Siobhan Mackenzie.",
            "Ask for Maya Chenner Jordan Lee.",
            "The total should be 1250.50.",
            "Charge the card twice.",
        ]
        let dictionary = examples.map { text in
            ["input": text, "output": DictionaryReplacer.replace(text, entries: entries)]
        }
        let result: [String: Any] = ["mechanical": processed, "dictionaryDemonstration": dictionary,
            "dictionaryScope": "Hand-configured aliases demonstrate the existing replacement stage; excluded from benchmark scores."]
        let output = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try FileHandle.standardOutput.write(contentsOf: output + Data([0x0A]))
    }
}
