import Foundation

public enum LanguagePassDisplayCopy {
    public static func didChange(input: String?, output: String) -> Bool {
        guard let input else {
            return false
        }
        return input.trimmingCharacters(in: .whitespacesAndNewlines)
            != output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func status(
        accepted: Bool?,
        changed: Bool,
        fallbackReason: String?
    ) -> String {
        if let accepted {
            if accepted {
                return changed ? "Cleaned" : "No cleanup necessary"
            }
            return fallbackStatus(fallbackReason)
        }

        if let fallbackReason {
            return fallbackStatus(fallbackReason)
        }
        return "Recorded"
    }

    public static func reason(
        accepted: Bool?,
        changed: Bool,
        fallbackReason: String?,
        styleRawValue: String? = nil
    ) -> String {
        let toneTitle = toneTitle(styleRawValue)

        if let accepted {
            if accepted {
                return changed
                    ? "Meaning preserved · Tone applied"
                    : "Meaning + tone matched"
            }
            return fallbackReasonText(fallbackReason, toneTitle: toneTitle)
        }

        if let fallbackReason {
            return fallbackReasonText(fallbackReason, toneTitle: toneTitle)
        }
        return "Legacy entry · Details unavailable"
    }

    public static func summary(
        accepted: Bool,
        changed: Bool,
        fallbackReason: String?,
        wallMs: Int?,
        styleRawValue: String? = nil
    ) -> String {
        var parts = [
            status(accepted: accepted, changed: changed, fallbackReason: fallbackReason)
        ]
        if let toneTitle = toneTitle(styleRawValue) {
            parts.append(toneTitle)
        }
        if let wallMs {
            parts.append("\(wallMs)ms")
        }
        return parts.joined(separator: " · ")
    }

    public static func toneTitle(_ styleRawValue: String?) -> String? {
        guard
            let normalized = normalizedOptional(styleRawValue),
            let style = LanguagePassStyle(rawValue: normalized)
        else {
            return nil
        }
        return style.title
    }

    private static func fallbackStatus(_ fallbackReason: String?) -> String {
        switch normalizedReason(fallbackReason) {
        case "disabled":
            return "Cleanup off"
        case "model_not_ready", "generation_failed", "cancelled", "empty_output":
            return "Cleanup skipped"
        default:
            return "No cleanup necessary"
        }
    }

    private static func fallbackReasonText(_ fallbackReason: String?, toneTitle _: String?) -> String {
        switch normalizedReason(fallbackReason) {
        case "disabled":
            return "Cleanup off"
        case "model_not_ready":
            return "Model preparing · Original kept"
        case "generation_failed", "cancelled", "empty_output":
            return "Cleanup unfinished · Original kept"
        case "empty_input":
            return "No transcript text"
        default:
            return "Meaning protected · Original kept"
        }
    }

    private static func normalizedReason(_ fallbackReason: String?) -> String {
        normalizedOptional(fallbackReason)?.lowercased() ?? ""
    }

    private static func normalizedOptional(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
