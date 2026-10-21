import Foundation

enum MiniTrialConfiguration {
    static var appName: String { isEnabled ? "ShoutOut Mini Trial" : "ShoutOut" }

    static var isEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "ShoutOutMiniTrial") as? Bool == true
    }
}
