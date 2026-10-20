import Foundation

public enum SettingsMigration {
    /// Version 0.2.0 enables streaming once, including upgrades from the batch setup.
    public static func enableStreamingByDefault(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: "hasEnabledStreamingDefault") else { return }
        defaults.set(true, forKey: "streamingTranscriptionEnabled")
        defaults.set(true, forKey: "hasEnabledStreamingDefault")
        defaults.synchronize()
    }

    /// Retired controls must not leave invisible overrides of the standard setup.
    /// Run before constructing services; the app registers their default values.
    public static func removeRetiredOverrides(from defaults: UserDefaults) {
        if let style = defaults.string(forKey: "overlayStyle"),
            style != "crab", style != "capsule", style != "glass" {
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
