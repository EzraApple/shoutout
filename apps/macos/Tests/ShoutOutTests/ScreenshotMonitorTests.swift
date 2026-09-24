import AppKit
import Carbon.HIToolbox
import XCTest
@testable import ShoutOut

final class ScreenshotMonitorTests: XCTestCase {
    @MainActor
    func testAllScreenshotShortcutsHideSynchronouslyIncludingClipboardVariants() {
        for key in [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5] {
            for flags: CGEventFlags in [
                [.maskCommand, .maskShift],
                [.maskCommand, .maskShift, .maskControl],
                [.maskCommand, .maskShift, .maskSecondaryFn],
            ] {
                let monitor = ScreenshotMonitor()
                var changes: [Bool] = []
                monitor.onSuppressionChanged = { changes.append($0) }
                monitor.handleInput(input(key: key, flags: flags))
                XCTAssertEqual(changes, [true], "Must hide before returning the key event")
                monitor.stop()
                XCTAssertEqual(changes, [true, false])
            }
        }
    }

    @MainActor
    func testOrdinaryTypingFnAndOtherShortcutsDoNotHide() {
        let monitor = ScreenshotMonitor()
        var changes: [Bool] = []
        monitor.onSuppressionChanged = { changes.append($0) }
        for key in [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5] {
            for flags: CGEventFlags in [[], .maskShift, .maskCommand, [.maskCommand, .maskShift, .maskAlternate]] {
                monitor.handleInput(input(key: key, flags: flags))
            }
        }
        monitor.handleInput(input(key: kVK_Function, flags: .maskSecondaryFn))
        monitor.handleInput(input(key: kVK_ANSI_Z, flags: [.maskCommand, .maskShift]))
        XCTAssertTrue(changes.isEmpty)
        monitor.stop()
    }

    @MainActor
    func testKeyUpAndRepeatsDoNotStartSuppression() {
        let monitor = ScreenshotMonitor()
        var changes: [Bool] = []
        monitor.onSuppressionChanged = { changes.append($0) }
        monitor.handleInput(input(key: kVK_ANSI_3, type: .keyUp))
        monitor.handleInput(input(key: kVK_ANSI_3, repeatKey: true))
        XCTAssertTrue(changes.isEmpty)
        monitor.stop()
    }

    private func input(
        key: Int,
        flags: CGEventFlags = [.maskCommand, .maskShift],
        type: CGEventType = .keyDown,
        repeatKey: Bool = false
    ) -> ScreenshotInput {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: type == .keyDown)!
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
        return ScreenshotInput(type: type, event: event)
    }
}
