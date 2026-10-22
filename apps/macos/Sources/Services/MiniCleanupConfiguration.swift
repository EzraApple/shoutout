import Foundation
import MiniCleanup
import ShoutOutCore

enum MiniCleanupConfiguration {
    static let modelID = MiniCleanupEngine.modelID

    @MainActor
    static func makeLanguagePassService(
        defaults: UserDefaults = .standard,
        miniModelDirectory: URL? = nil
    ) -> LanguagePassService {
        SettingsMigration.useMiniCleanupByDefault(in: defaults)
        let directory = miniModelDirectory
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/MiniCleanup")
        return LanguagePassService(miniModelDirectory: directory, defaults: defaults)
    }
}
