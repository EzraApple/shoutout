import Foundation
import XCTest
@testable import ShoutOut

@MainActor
final class AppControlRouterTests: XCTestCase {
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
        XCTAssertTrue(service.streamingTrialEnabled)
        let off = await router.handle(AppControlRequest(command: "settings.set", key: "streaming", value: "off", path: nil))
        XCTAssertTrue(off.ok)
        let nextLaunch = TranscriptionService(defaults: defaults)
        XCTAssertEqual(nextLaunch.selectedBackend, .parakeet)
        XCTAssertFalse(nextLaunch.streamingTrialEnabled)
    }

    func testDisabledTrialCannotRestoreStoredHexBackend() throws {
        let suite = "ShoutOut.CLI.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("hexStreaming", forKey: Defaults.transcriptionBackend)
        let service = TranscriptionService(defaults: defaults)
        XCTAssertEqual(service.selectedBackend, .parakeet)
        XCTAssertFalse(service.streamingTrialEnabled)
    }

    func testOfflineStatusPreservesConfiguredNonStreamingBackend() async throws {
        let suite = "ShoutOut.CLI.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("whisperkit", forKey: Defaults.transcriptionBackend)
        let response = await AppControlRouter(defaults: defaults).handle(AppControlRequest(command: "status"))
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.values["engine"], "whisperkit")
    }

    func testInvalidSettingDoesNotReplaceSavedValue() async throws {
        let suite = "ShoutOut.CLI.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("casual", forKey: Defaults.languagePassStyle)
        let router = AppControlRouter(defaults: defaults)
        let response = await router.handle(AppControlRequest(command: "settings.set", key: "style", value: "anything", path: nil))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(defaults.string(forKey: Defaults.languagePassStyle), "casual")
    }

    func testSettingsCannotUnloadAnEngineDuringDictation() async throws {
        let suite = "ShoutOut.CLI.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = TranscriptionService(defaults: defaults)
        service.isDictationInProgress = true
        let router = AppControlRouter(defaults: defaults, transcription: service)
        let response = await router.handle(AppControlRequest(command: "settings.set", key: "streaming", value: "on", path: nil))
        XCTAssertFalse(response.ok)
        XCTAssertFalse(defaults.bool(forKey: "streamingTranscriptionEnabled"))
        XCTAssertEqual(service.selectedBackend, .parakeet)
    }
}
