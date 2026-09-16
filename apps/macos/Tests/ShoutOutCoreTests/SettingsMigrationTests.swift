import Foundation
import XCTest
@testable import ShoutOutCore

final class SettingsMigrationTests: XCTestCase {
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

        SettingsMigration.removeRetiredOverrides(from: defaults)
        SettingsMigration.removeRetiredOverrides(from: defaults)

        XCTAssertEqual(defaults.string(forKey: "transcriptionBackend"), "parakeet")
        XCTAssertTrue(defaults.bool(forKey: "smartSpacing"))
        XCTAssertNil(defaults.object(forKey: "languagePassModel"))
        XCTAssertNil(defaults.object(forKey: "boringMode"))
        XCTAssertFalse(defaults.bool(forKey: "languagePassEnabled"))
        XCTAssertEqual(defaults.string(forKey: "languagePassStyle"), "casual")
        XCTAssertEqual(defaults.string(forKey: "crabColorVariant"), "black")
        XCTAssertEqual(defaults.string(forKey: "overlayStyle"), "capsule")
        XCTAssertEqual(defaults.string(forKey: "hotkeyTrigger"), "rightOption")
        XCTAssertTrue(defaults.bool(forKey: "hasCompletedOnboarding"))
    }
}
