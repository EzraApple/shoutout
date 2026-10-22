import Foundation
import XCTest
@testable import ShoutOutCore

final class SettingsMigrationTests: XCTestCase {
    func testNewInstallsAndUpgradesAdoptStreaming() throws {
        for previousValue: Bool? in [nil, false, true] {
            let suite = "ShoutOut.SettingsMigrationTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            if let previousValue {
                defaults.set(previousValue, forKey: "streamingTranscriptionEnabled")
            }

            SettingsMigration.enableStreamingByDefault(in: defaults)

            XCTAssertTrue(defaults.bool(forKey: "streamingTranscriptionEnabled"))
        }
    }

    func testStreamingMigrationPreservesLaterDiagnosticOptOut() throws {
        let suite = "ShoutOut.SettingsMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsMigration.enableStreamingByDefault(in: defaults)
        defaults.set(false, forKey: "streamingTranscriptionEnabled")
        defaults.synchronize()

        let nextLaunch = try XCTUnwrap(UserDefaults(suiteName: suite))
        SettingsMigration.enableStreamingByDefault(in: nextLaunch)

        XCTAssertFalse(nextLaunch.bool(forKey: "streamingTranscriptionEnabled"))
    }

    func testGlassIndicatorSurvivesStartupMigration() throws {
        let suite = "ShoutOut.SettingsMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("glass", forKey: "overlayStyle")
        defaults.set(true, forKey: "streamingTranscriptionEnabled")
        defaults.synchronize()

        let nextLaunch = try XCTUnwrap(UserDefaults(suiteName: suite))
        SettingsMigration.removeRetiredOverrides(from: nextLaunch)

        XCTAssertEqual(nextLaunch.string(forKey: "overlayStyle"), "glass")
        XCTAssertTrue(nextLaunch.bool(forKey: "streamingTranscriptionEnabled"))
    }

    func testRecordingAudioPreferenceSurvivesStartupMigration() throws {
        for isDimmingEnabled in [false, true] {
            let suite = "ShoutOut.SettingsMigrationTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.register(defaults: ["dimSystemAudio": true])
            defaults.set(isDimmingEnabled, forKey: "dimSystemAudio")
            defaults.synchronize()

            let nextLaunch = try XCTUnwrap(UserDefaults(suiteName: suite))
            nextLaunch.register(defaults: ["dimSystemAudio": true])
            SettingsMigration.removeRetiredOverrides(from: nextLaunch)
            SettingsMigration.removeRetiredOverrides(from: nextLaunch)

            XCTAssertEqual(nextLaunch.bool(forKey: "dimSystemAudio"), isDimmingEnabled)
        }
    }

    func testRetiredOverridesResetWithoutChangingPersonalPreferences() throws {
        let suite = "ShoutOut.SettingsMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.register(defaults: ["transcriptionBackend": "parakeet", "smartSpacing": true])
        defaults.set("appleSpeech", forKey: "transcriptionBackend")
        defaults.set("old-experimental-model", forKey: "languagePassModel")
        defaults.set(false, forKey: "smartSpacing")
        defaults.set(true, forKey: "boringMode")
        defaults.set(false, forKey: "languagePassEnabled")
        defaults.set("casual", forKey: "languagePassStyle")
        defaults.set("black", forKey: "crabColorVariant")
        defaults.set("capsule", forKey: "overlayStyle")
        defaults.set("rightOption", forKey: "hotkeyTrigger")
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set(true, forKey: "streamingTranscriptionEnabled")

        SettingsMigration.removeRetiredOverrides(from: defaults)
        SettingsMigration.useMiniCleanupByDefault(in: defaults)
        SettingsMigration.removeRetiredOverrides(from: defaults)
        SettingsMigration.useMiniCleanupByDefault(in: defaults)

        XCTAssertEqual(defaults.string(forKey: "transcriptionBackend"), "parakeet")
        XCTAssertTrue(defaults.bool(forKey: "smartSpacing"))
        XCTAssertNil(defaults.object(forKey: "languagePassModel"))
        XCTAssertNil(defaults.object(forKey: "boringMode"))
        XCTAssertFalse(defaults.bool(forKey: "languagePassEnabled"))
        XCTAssertNil(defaults.object(forKey: "languagePassStyle"))
        XCTAssertEqual(defaults.string(forKey: "crabColorVariant"), "black")
        XCTAssertEqual(defaults.string(forKey: "overlayStyle"), "capsule")
        XCTAssertEqual(defaults.string(forKey: "hotkeyTrigger"), "rightOption")
        XCTAssertTrue(defaults.bool(forKey: "hasCompletedOnboarding"))
        XCTAssertTrue(defaults.bool(forKey: "streamingTranscriptionEnabled"))
    }

    func testMiniMigrationClearsLegacyChoicesOnceAndKeepsPersonalSettings() throws {
        for (model, style, enabled) in [
            ("mlx-community/Llama-3.2-1B-Instruct-4bit", "formal", true),
            ("mlx-community/Qwen2.5-0.5B-Instruct-4bit", "casual", false),
            ("custom/model", "standard", true),
        ] {
            let suite = "ShoutOut.MiniMigration.Tests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(model, forKey: "languagePassModel")
            defaults.set(style, forKey: "languagePassStyle")
            defaults.set(enabled, forKey: "languagePassEnabled")
            defaults.set("rightOption", forKey: "hotkeyTrigger")
            defaults.set("Example", forKey: "dictionaryUnrelatedValue")
            defaults.set("history sentinel", forKey: "transcriptionHistoryUnrelatedValue")

            SettingsMigration.useMiniCleanupByDefault(in: defaults)
            XCTAssertNil(defaults.object(forKey: "languagePassModel"))
            XCTAssertNil(defaults.object(forKey: "languagePassStyle"))
            XCTAssertEqual(defaults.bool(forKey: "languagePassEnabled"), enabled)
            XCTAssertEqual(defaults.string(forKey: "hotkeyTrigger"), "rightOption")
            XCTAssertEqual(defaults.string(forKey: "dictionaryUnrelatedValue"), "Example")
            XCTAssertEqual(defaults.string(forKey: "transcriptionHistoryUnrelatedValue"), "history sentinel")

            defaults.set("later value", forKey: "languagePassStyle")
            SettingsMigration.useMiniCleanupByDefault(in: defaults)
            XCTAssertEqual(defaults.string(forKey: "languagePassStyle"), "later value")
        }
    }
}
