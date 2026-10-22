import Foundation
import XCTest
@testable import ShoutOut

@MainActor
final class AppControlRouterTests: XCTestCase {
    func testNewSettingsUseStreamingInServiceAndOfflineStatus() async throws {
        let suite = "ShoutOut.CLI.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let service = TranscriptionService(defaults: defaults)
        let response = await AppControlRouter(defaults: defaults).handle(AppControlRequest(command: "status"))

        XCTAssertEqual(service.selectedBackend, .hexStreaming)
        XCTAssertEqual(response.values["engine"], "hexStreaming")
        XCTAssertEqual(response.values["streaming"], "true")
    }

    func testSettingsPersistAndSelectStreamingOnNextLaunch() async throws {
        let suite = "ShoutOut.CLI.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let router = AppControlRouter(defaults: defaults)
        let response = await router.handle(AppControlRequest(command: "settings.set", key: "streaming", value: "on", path: nil))
        XCTAssertTrue(response.ok)
        XCTAssertTrue(defaults.bool(forKey: "streamingTranscriptionEnabled"))
        let service = TranscriptionService(defaults: defaults)
        XCTAssertEqual(service.selectedBackend, .hexStreaming)
        let off = await router.handle(AppControlRequest(command: "settings.set", key: "streaming", value: "off", path: nil))
        XCTAssertTrue(off.ok)
        let nextLaunch = TranscriptionService(defaults: defaults)
        XCTAssertEqual(nextLaunch.selectedBackend, .parakeet)
    }

    func testDisabledStreamingCannotRestoreStoredHexBackend() throws {
        let suite = "ShoutOut.CLI.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("hexStreaming", forKey: Defaults.transcriptionBackend)
        defaults.set(false, forKey: Defaults.streamingTranscriptionEnabled)
        let service = TranscriptionService(defaults: defaults)
        XCTAssertEqual(service.selectedBackend, .parakeet)
    }

    func testOfflineStatusPreservesConfiguredNonStreamingBackend() async throws {
        let suite = "ShoutOut.CLI.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("whisperkit", forKey: Defaults.transcriptionBackend)
        defaults.set(false, forKey: Defaults.streamingTranscriptionEnabled)
        let response = await AppControlRouter(defaults: defaults).handle(AppControlRequest(command: "status"))
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.values["engine"], "whisperkit")
    }

    func testLegacyStyleSettingIsRejectedAndHidden() async throws {
        let suite = "ShoutOut.CLI.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("casual", forKey: Defaults.languagePassStyle)
        let router = AppControlRouter(defaults: defaults)
        let response = await router.handle(AppControlRequest(command: "settings.set", key: "style", value: "formal", path: nil))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(defaults.string(forKey: Defaults.languagePassStyle), "casual")
        let status = await router.handle(AppControlRequest(command: "status"))
        XCTAssertNil(status.values["style"])
        XCTAssertEqual(status.values["cleanupModel"], MiniCleanupConfiguration.modelID)
    }

    func testIndicatorStylesPersistWithoutChangingTheTranscriptionEngine() async throws {
        let suite = "ShoutOut.CLI.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "streamingTranscriptionEnabled")
        let router = AppControlRouter(defaults: defaults)
        for (value, expected) in [("crab", "crab"), ("classic", "capsule"), ("glass", "glass")] {
            let response = await router.handle(AppControlRequest(command: "settings.set", key: "indicator", value: value))
            XCTAssertTrue(response.ok)
            XCTAssertEqual(response.values["indicator"], expected)
            XCTAssertEqual(defaults.string(forKey: Defaults.overlayStyle), expected)
            XCTAssertEqual(response.values["engine"], "hexStreaming")
        }
        let invalid = await router.handle(AppControlRequest(command: "settings.set", key: "indicator", value: "off"))
        XCTAssertFalse(invalid.ok)
        XCTAssertEqual(defaults.string(forKey: Defaults.overlayStyle), "glass")
    }

    func testSettingsCannotUnloadAnEngineDuringDictation() async throws {
        let suite = "ShoutOut.CLI.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: Defaults.streamingTranscriptionEnabled)
        let service = TranscriptionService(defaults: defaults)
        service.isDictationInProgress = true
        let router = AppControlRouter(defaults: defaults, transcription: service)
        let response = await router.handle(AppControlRequest(command: "settings.set", key: "streaming", value: "off", path: nil))
        XCTAssertFalse(response.ok)
        XCTAssertTrue(defaults.bool(forKey: Defaults.streamingTranscriptionEnabled))
        XCTAssertEqual(service.selectedBackend, .hexStreaming)
    }
}
