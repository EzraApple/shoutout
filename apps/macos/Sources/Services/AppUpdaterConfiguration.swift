import Foundation

enum AppUpdaterConfiguration {
    static let defaultFeedURL = "https://shoutout.sh/appcast.xml"
    static let placeholderPublicKey = "__SPARKLE_PUBLIC_ED_KEY__"
    static let examplePublicKey = "paste SUPublicEDKey here"

    static var feedURLString: String {
        normalizedString(for: "SUFeedURL") ?? defaultFeedURL
    }

    static var publicKey: String? {
        let value = normalizedString(for: "SUPublicEDKey")
        guard value != placeholderPublicKey else { return nil }
        guard value != examplePublicKey else { return nil }
        return value
    }

    static var isConfigured: Bool {
        guard let publicKey,
            !publicKey.isEmpty,
            let feedURL = URL(string: feedURLString),
            feedURL.scheme == "https"
        else {
            return false
        }
        return true
    }

    static var statusText: String {
        if isConfigured {
            return "Automatic updates enabled"
        }
        if publicKey == nil {
            return "Waiting on Sparkle public key"
        }
        return "Waiting on HTTPS appcast"
    }

    private static func normalizedString(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
