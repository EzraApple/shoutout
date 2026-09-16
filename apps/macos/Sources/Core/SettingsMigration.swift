import Foundation

public enum SettingsMigration {
    /// Retired controls must not leave invisible overrides of the standard setup.
    /// Run before constructing services; the app registers their default values.
    public static func removeRetiredOverrides(from defaults: UserDefaults) {
        if let style = defaults.string(forKey: "overlayStyle"),
            style != "crab", style != "capsule" {
            defaults.removeObject(forKey: "overlayStyle")
        }
        for key in [
            "transcriptionBackend", "selectedModel", "languagePassModel",
            "boringMode", "removeFillerWords", "smartSpacing",
            "appendTrailingSpace", "showInDock", "dimSystemAudio",
        ] {
            defaults.removeObject(forKey: key)
        }
    }
}
