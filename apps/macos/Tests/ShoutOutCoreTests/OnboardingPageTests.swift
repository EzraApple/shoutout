import XCTest
@testable import ShoutOutCore

final class OnboardingPageTests: XCTestCase {
    func testRestoresEveryPageAfterRelaunch() {
        for page in OnboardingPage.allCases {
            XCTAssertEqual(OnboardingPage.restore(savedPage: page.rawValue, legacyStep: 6), page)
        }
    }

    func testMigratesInProgressSetupToPermissions() {
        for step in 1...6 {
            XCTAssertEqual(OnboardingPage.restore(savedPage: "", legacyStep: step), .permissions)
        }
    }

    func testStartsNewOrInvalidProgressAtWelcome() {
        XCTAssertEqual(OnboardingPage.restore(savedPage: "", legacyStep: 0), .welcome)
        XCTAssertEqual(OnboardingPage.restore(savedPage: "unknown", legacyStep: -1), .welcome)
    }
}
