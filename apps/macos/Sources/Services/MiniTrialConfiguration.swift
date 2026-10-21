import Foundation
import MiniCleanup
import ShoutOutCore

enum MiniTrialConfiguration {
    static let modelID = MiniCleanupEngine.modelID
    static var appName: String { isEnabled ? "ShoutOut Mini Trial" : "ShoutOut" }

    static var isEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "ShoutOutMiniTrial") as? Bool == true
    }

    @MainActor
    static func makeLanguagePassService(
        defaults: UserDefaults = .standard,
        modelsDirectory: URL = LanguagePassService.modelsDirectory
    ) -> LanguagePassService {
        if isEnabled {
            let directory = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/MiniCleanup")
            return LanguagePassService(miniModelDirectory: directory, defaults: defaults)
        }
        return LanguagePassService(defaults: defaults, modelsDirectory: modelsDirectory)
    }
}
