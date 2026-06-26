import Testing
@testable import ShoutOutCore

struct ShortcutTimingStateMachineTests {
    @Test func quickTapKeepsPendingRecordingUntilDoubleTapWindowExpires() {
        var machine = ShortcutTimingStateMachine()

        #expect(machine.shortcutDown(at: 0) == [.startHoldTimer, .armRecording])
        #expect(
            machine.shortcutUp(at: 0.05) == [
                .cancelHoldTimer,
                .startDoubleTapTimer,
            ]
        )
        #expect(machine.doubleTapTimerFired() == [.cancelPendingRecording])
    }

    @Test func releaseAfterHoldThresholdCommitsEvenWhenTimerHasNotFired() {
        var machine = ShortcutTimingStateMachine()

        #expect(machine.shortcutDown(at: 1.0) == [.startHoldTimer, .armRecording])
        #expect(
            machine.shortcutUp(at: 1.225) == [
                .cancelHoldTimer,
                .delayedHoldCommitted(milliseconds: 225),
                .commitRecording(.hold),
                .stopRecording,
            ]
        )
    }

    @Test func holdTimerCommitsThenReleaseStopsRecording() {
        var machine = ShortcutTimingStateMachine()

        #expect(machine.shortcutDown(at: 0) == [.startHoldTimer, .armRecording])
        #expect(machine.holdTimerFired() == [.commitRecording(.hold)])
        #expect(machine.shortcutUp(at: 0.25) == [.stopRecording])
    }

    @Test func secondTapInsideWindowStartsHandsFreeAndNextPressStops() {
        var machine = ShortcutTimingStateMachine()

        _ = machine.shortcutDown(at: 0)
        _ = machine.shortcutUp(at: 0.04)

        #expect(machine.shortcutDown(at: 0.30) == [.cancelDoubleTapTimer, .commitRecording(.handsFree)])
        #expect(machine.shortcutUp(at: 0.34) == [])
        #expect(machine.shortcutDown(at: 1.0) == [.stopRecording])
    }

    @Test func normalLengthFirstTapStillWaitsForHandsFreeSecondTap() {
        var machine = ShortcutTimingStateMachine()

        _ = machine.shortcutDown(at: 0)
        #expect(
            machine.shortcutUp(at: 0.15) == [
                .cancelHoldTimer,
                .delayedHoldCommitted(milliseconds: 150),
                .commitRecording(.hold),
                .startDoubleTapTimer,
            ]
        )
        #expect(machine.shortcutDown(at: 0.45) == [.cancelDoubleTapTimer, .commitRecording(.handsFree)])
    }

    @Test func committedTapCandidateStopsWhenDoubleTapDoesNotArrive() {
        var machine = ShortcutTimingStateMachine()

        _ = machine.shortcutDown(at: 0)
        _ = machine.holdTimerFired()
        #expect(machine.shortcutUp(at: 0.15) == [.startDoubleTapTimer])
        #expect(machine.doubleTapTimerFired() == [.stopRecording])
    }

    @Test func secondTapAfterWindowStartsNewPendingRecording() {
        var machine = ShortcutTimingStateMachine()

        _ = machine.shortcutDown(at: 0)
        _ = machine.shortcutUp(at: 0.04)
        _ = machine.doubleTapTimerFired()

        #expect(machine.shortcutDown(at: 0.80) == [.startHoldTimer, .armRecording])
    }
}
