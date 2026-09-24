import XCTest
@testable import ShoutOutCore

final class ScreenshotSuppressionTests: XCTestCase {
    func testImmediateScreenCaptureExpiresAfterShortGrace() {
        var suppression = ScreenshotSuppression()

        suppression.begin(.entireScreen, at: 10)
        suppression.update(captureUIVisible: false, at: 11.49)
        XCTAssertTrue(suppression.isSuppressed)

        suppression.update(captureUIVisible: false, at: 11.5)
        XCTAssertFalse(suppression.isSuppressed)
    }

    func testSelectionStaysSuppressedAfterModifierReleaseWhileUIIsVisible() {
        var suppression = ScreenshotSuppression()

        suppression.begin(.selection, at: 0)
        suppression.update(captureUIVisible: true, at: 0.1)
        // Modifier release is not a completion signal: no state transition is sent.
        suppression.update(captureUIVisible: true, at: 45)

        XCTAssertTrue(suppression.isSuppressed)
    }

    func testMouseSelectionCompletionUsesShortRestoreGrace() {
        var suppression = ScreenshotSuppression()

        suppression.begin(.selection, at: 0)
        suppression.update(captureUIVisible: true, at: 0.1)
        suppression.completeInteraction(at: 4)
        suppression.update(captureUIVisible: false, at: 4)
        suppression.update(captureUIVisible: false, at: 4.99)
        XCTAssertTrue(suppression.isSuppressed)

        suppression.update(captureUIVisible: false, at: 5)
        XCTAssertFalse(suppression.isSuppressed)
    }

    func testToolbarRemainsSuppressedAcrossVisibleMenuInteractions() {
        var suppression = ScreenshotSuppression()

        suppression.begin(.toolbar, at: 0)
        suppression.update(captureUIVisible: true, at: 0.1)
        // Opening or dismissing a toolbar menu leaves capture UI present.
        suppression.completeInteraction(at: 10)
        suppression.update(captureUIVisible: true, at: 10.1)
        suppression.update(captureUIVisible: true, at: 30)

        XCTAssertTrue(suppression.isSuppressed)
    }

    func testToolbarDisappearanceKeepsSuppressionThroughTenSecondTimer() {
        var suppression = ScreenshotSuppression()

        suppression.begin(.toolbar, at: 0)
        suppression.update(captureUIVisible: true, at: 1)
        suppression.update(captureUIVisible: false, at: 2)

        suppression.update(captureUIVisible: false, at: 13.99)
        XCTAssertTrue(suppression.isSuppressed)

        suppression.update(captureUIVisible: false, at: 14)
        XCTAssertFalse(suppression.isSuppressed)
    }

    func testEscapeCancellationRestoresAfterBriefGrace() {
        var suppression = ScreenshotSuppression()

        suppression.begin(.selection, at: 0)
        suppression.update(captureUIVisible: true, at: 0.1)
        suppression.cancel(at: 2)
        suppression.update(captureUIVisible: false, at: 2.29)
        XCTAssertTrue(suppression.isSuppressed)

        suppression.update(captureUIVisible: false, at: 2.3)
        XCTAssertFalse(suppression.isSuppressed)
    }

    func testRepeatedShortcutInvalidatesEarlierRestoreDeadline() {
        var suppression = ScreenshotSuppression()

        suppression.begin(.entireScreen, at: 0)
        suppression.begin(.selection, at: 1)
        suppression.update(captureUIVisible: true, at: 1.1)
        suppression.update(captureUIVisible: true, at: 2)

        XCTAssertTrue(suppression.isSuppressed)
    }

    func testEscapeBeforeUIDisappearsPreservesCancellationGrace() {
        var suppression = ScreenshotSuppression()
        suppression.begin(.toolbar, at: 0)
        suppression.update(captureUIVisible: true, at: 1)
        suppression.cancel(at: 2)
        suppression.update(captureUIVisible: true, at: 2.1)
        suppression.update(captureUIVisible: false, at: 2.2)
        suppression.update(captureUIVisible: false, at: 2.51)
        XCTAssertFalse(suppression.isSuppressed)
    }

    func testSelectionWithoutObservableUIStillRestoresAfterMouseRelease() {
        var suppression = ScreenshotSuppression()
        suppression.begin(.selection, at: 0)
        suppression.update(captureUIVisible: false, at: 45)
        XCTAssertTrue(suppression.isSuppressed)
        suppression.completeInteraction(at: 50)
        suppression.update(captureUIVisible: false, at: 50.9)
        XCTAssertTrue(suppression.isSuppressed)
        suppression.update(captureUIVisible: false, at: 51)
        XCTAssertFalse(suppression.isSuppressed)
    }

    func testRecoveryTimeoutRestoresIfCaptureUINeverCompletes() {
        var suppression = ScreenshotSuppression()

        suppression.begin(.selection, at: 0)
        suppression.update(captureUIVisible: true, at: 1)
        suppression.update(captureUIVisible: true, at: 299.99)
        XCTAssertTrue(suppression.isSuppressed)

        suppression.update(captureUIVisible: true, at: 300)
        XCTAssertFalse(suppression.isSuppressed)
    }

    func testUnrelatedClicksAfterCaptureDoNotKeepExtendingRestoration() {
        var suppression = ScreenshotSuppression()
        suppression.begin(.toolbar, at: 0)
        suppression.completeInteraction(at: 2)
        suppression.update(captureUIVisible: false, at: 3)
        suppression.completeInteraction(at: 10)
        suppression.update(captureUIVisible: false, at: 14)
        XCTAssertFalse(suppression.isSuppressed)
    }
}
