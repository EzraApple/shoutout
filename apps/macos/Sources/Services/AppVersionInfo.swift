import Foundation

enum AppVersionInfo {
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.ezraapple.shoutout"
    }

    static var version: String {
        value(for: "CFBundleShortVersionString") ?? "0.0.0"
    }

    static var build: String {
        value(for: "CFBundleVersion") ?? "0"
    }

    static var gitCommit: String? {
        normalizedOptionalValue(for: "ShoutOutGitCommit")
    }

    static var builtAt: String? {
        normalizedOptionalValue(for: "ShoutOutBuiltAt")
    }

    static var display: String {
        "v\(version) (\(build))"
    }

    static var displayWithCommit: String {
        guard let shortCommit else { return display }
        return "\(display) · \(shortCommit)"
    }

    static var diagnosticsSummary: String {
        [
            "Bundle ID: \(bundleIdentifier)",
            "Version: \(version)",
            "Build: \(build)",
            gitCommit.map { "Git commit: \($0)" },
            builtAt.map { "Built at: \($0)" },
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private static var shortCommit: String? {
        gitCommit.map { String($0.prefix(7)) }
    }

    private static func value(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private static func normalizedOptionalValue(for key: String) -> String? {
        guard let value = value(for: key),
            !value.isEmpty,
            value != "unknown"
        else {
            return nil
        }
        return value
    }
}
