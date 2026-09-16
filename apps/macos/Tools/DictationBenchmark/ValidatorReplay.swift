import Foundation

@main
struct ValidatorReplay {
    static func main() throws {
        var changes: [[String: Any]] = []
        var evaluated = 0
        var skipped = 0
        for path in CommandLine.arguments.dropFirst() {
            let rows = try JSONSerialization.jsonObject(with: Data(contentsOf:
                URL(fileURLWithPath: path))) as! [[String: Any]]
            for (index, row) in rows.enumerated() {
                guard let candidate = row["candidate"] as? String,
                    let input = row["input"] as? String,
                    let styleName = row["style"] as? String,
                    let style = LanguagePassStyle(rawValue: styleName)
                else { skipped += 1; continue }
                evaluated += 1
                let validation = LanguagePassValidator.validate(candidate: candidate, baseText: input)
                var final = validation.acceptedText ?? input
                var accepted = validation.isAccepted
                var reason = validation.fallbackReason
                if !validation.isAccepted,
                    let fallback = LanguagePassFallbackPolicy.fallback(baseText: input,
                        candidateText: candidate, reason: reason ?? "rejected", style: style) {
                    final = fallback.finalText
                    accepted = true
                    reason = fallback.reason
                }
                if final != row["final"] as? String || accepted != row["accepted"] as? Bool
                    || reason != row["fallback"] as? String {
                    changes.append([
                        "file": path, "index": index, "input": input, "candidate": candidate,
                        "style": styleName, "beforeFinal": row["final"]!, "afterFinal": final,
                        "beforeAccepted": row["accepted"]!, "afterAccepted": accepted,
                        "beforeFallback": row["fallback"] ?? NSNull(),
                        "afterFallback": reason as Any? ?? NSNull(),
                    ])
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject:
            ["evaluated": evaluated, "skippedWithoutCandidate": skipped, "changes": changes],
            options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
