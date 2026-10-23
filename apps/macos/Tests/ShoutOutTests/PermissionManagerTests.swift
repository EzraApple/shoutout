import Foundation
import XCTest
@testable import ShoutOut

@MainActor
final class PermissionManagerTests: XCTestCase {
    func testInputMonitoringRequestSurvivesFalsePreflightUntilAccessibilityIsRevoked() {
        var state = InputMonitoringPermissionState()

        XCTAssertFalse(state.refresh(accessibilityGranted: true, preflightGranted: false))
        state.recordRequest(granted: true)
        XCTAssertTrue(state.refresh(accessibilityGranted: true, preflightGranted: false))
        XCTAssertTrue(state.refresh(accessibilityGranted: true, preflightGranted: false))

        XCTAssertFalse(state.refresh(accessibilityGranted: false, preflightGranted: false))
        XCTAssertFalse(state.refresh(accessibilityGranted: true, preflightGranted: false))
    }

    func testFailedInputMonitoringRequestDoesNotGrantAccess() {
        var state = InputMonitoringPermissionState()
        state.recordRequest(granted: false)

        XCTAssertFalse(state.refresh(accessibilityGranted: true, preflightGranted: false))
        XCTAssertTrue(state.refresh(accessibilityGranted: true, preflightGranted: true))
    }

    func testSpeechRecognitionRequirementUsesEffectiveBackend() throws {
        let suite = "ShoutOut.Permission.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(TranscriptionBackend.appleSpeech.rawValue, forKey: Defaults.transcriptionBackend)

        XCTAssertFalse(PermissionManager.requiresSpeechRecognition(defaults: defaults))
        defaults.set(true, forKey: Defaults.streamingTranscriptionEnabled)
        XCTAssertFalse(PermissionManager.requiresSpeechRecognition(defaults: defaults))
        defaults.set(false, forKey: Defaults.streamingTranscriptionEnabled)
        XCTAssertTrue(PermissionManager.requiresSpeechRecognition(defaults: defaults))

        defaults.set(TranscriptionBackend.parakeet.rawValue, forKey: Defaults.transcriptionBackend)
        XCTAssertFalse(PermissionManager.requiresSpeechRecognition(defaults: defaults))
    }
}
