import Foundation

public enum SettingsMigration {
    /// The bundled Mini editor has no model or tone choice. Keep the cleanup
    /// switch, and leave past transcription records untouched.
    public static func useMiniCleanupByDefault(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: "hasMigratedMiniCleanupDefault") else { return }
        defaults.removeObject(forKey: "languagePassModel")
        defaults.removeObject(forKey: "languagePassStyle")
        defaults.set(true, forKey: "hasMigratedMiniCleanupDefault")
        defaults.synchronize()
    }

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
            "transcriptionBackend", "selectedModel",
            "boringMode", "removeFillerWords", "smartSpacing",
            "appendTrailingSpace", "showInDock",
        ] {
            defaults.removeObject(forKey: key)
        }
    }
}
