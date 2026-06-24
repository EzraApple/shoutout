import Testing
@testable import ShoutOutCore

struct ShortcutTimingStateMachineTests {
    @Test func quickTapWaitsForDoubleTapAndCancelsPendingRecording() {
        var machine = ShortcutTimingStateMachine()

        #expect(machine.shortcutDown(at: 0) == [.startHoldTimer, .armRecording])
        #expect(
            machine.shortcutUp(at: 0.05) == [
                .cancelHoldTimer,
                .cancelPendingRecording,
                .startDoubleTapTimer,
            ]
        )
        #expect(machine.doubleTapTimerFired() == [.cancelPendingRecording])
    }

    @Test func releaseAfterHoldThresholdCommitsEvenWhenTimerHasNotFired() {
        var machine = ShortcutTimingStateMachine()

        #expect(machine.shortcutDown(at: 1.0) == [.startHoldTimer, .armRecording])
        #expect(
            machine.shortcutUp(at: 1.125) == [
                .cancelHoldTimer,
                .delayedHoldCommitted(milliseconds: 125),
                .commitRecording,
                .stopRecording,
            ]
        )
    }

    @Test func holdTimerCommitsThenReleaseStopsRecording() {
        var machine = ShortcutTimingStateMachine()

        #expect(machine.shortcutDown(at: 0) == [.startHoldTimer, .armRecording])
        #expect(machine.holdTimerFired() == [.commitRecording])
        #expect(machine.shortcutUp(at: 0.25) == [.stopRecording])
    }

    @Test func secondTapInsideWindowStartsHandsFreeAndNextPressStops() {
        var machine = ShortcutTimingStateMachine()

        _ = machine.shortcutDown(at: 0)
        _ = machine.shortcutUp(at: 0.04)

        #expect(machine.shortcutDown(at: 0.30) == [.cancelDoubleTapTimer, .commitRecording])
        #expect(machine.shortcutUp(at: 0.34) == [])
        #expect(machine.shortcutDown(at: 1.0) == [.stopRecording])
    }

    @Test func secondTapAfterWindowStartsNewPendingRecording() {
        var machine = ShortcutTimingStateMachine()

        _ = machine.shortcutDown(at: 0)
        _ = machine.shortcutUp(at: 0.04)
        _ = machine.doubleTapTimerFired()

        #expect(machine.shortcutDown(at: 0.50) == [.startHoldTimer, .armRecording])
    }
}
