import Foundation

public struct ShortcutTimingStateMachine: Sendable {
    public enum Effect: Equatable, Sendable {
        case startHoldTimer
        case cancelHoldTimer
        case startDoubleTapTimer
        case cancelDoubleTapTimer
        case armRecording
        case cancelPendingRecording
        case commitRecording
        case stopRecording
        case delayedHoldCommitted(milliseconds: Int)
    }

    private enum Phase: Equatable, Sendable {
        case idle
        case shortcutDownPending
        case waitingForDoubleTap
        case holdRecording
        case handsFreeRecording
    }

    public let holdThreshold: TimeInterval
    public let doubleTapWindow: TimeInterval

    private var phase: Phase = .idle
    private var shortcutDownTime: TimeInterval?

    public init(holdThreshold: TimeInterval = 0.12, doubleTapWindow: TimeInterval = 0.4) {
        self.holdThreshold = holdThreshold
        self.doubleTapWindow = doubleTapWindow
    }

    public mutating func shortcutDown(at timestamp: TimeInterval) -> [Effect] {
        switch phase {
        case .idle:
            phase = .shortcutDownPending
            shortcutDownTime = timestamp
            return [.startHoldTimer, .armRecording]

        case .waitingForDoubleTap:
            phase = .handsFreeRecording
            shortcutDownTime = timestamp
            return [.cancelDoubleTapTimer, .commitRecording]

        case .handsFreeRecording:
            phase = .idle
            shortcutDownTime = nil
            return [.stopRecording]

        case .shortcutDownPending, .holdRecording:
            return []
        }
    }

    public mutating func shortcutUp(at timestamp: TimeInterval) -> [Effect] {
        switch phase {
        case .shortcutDownPending:
            let heldDuration = max(0, timestamp - (shortcutDownTime ?? timestamp))
            if heldDuration >= holdThreshold {
                phase = .idle
                shortcutDownTime = nil
                return [
                    .cancelHoldTimer,
                    .delayedHoldCommitted(milliseconds: Int(heldDuration * 1000)),
                    .commitRecording,
                    .stopRecording,
                ]
            }

            phase = .waitingForDoubleTap
            return [
                .cancelHoldTimer,
                .cancelPendingRecording,
                .startDoubleTapTimer,
            ]

        case .holdRecording:
            phase = .idle
            shortcutDownTime = nil
            return [.stopRecording]

        case .idle, .waitingForDoubleTap, .handsFreeRecording:
            return []
        }
    }

    public mutating func holdTimerFired() -> [Effect] {
        guard phase == .shortcutDownPending else { return [] }
        phase = .holdRecording
        return [.commitRecording]
    }

    public mutating func doubleTapTimerFired() -> [Effect] {
        guard phase == .waitingForDoubleTap else { return [] }
        phase = .idle
        shortcutDownTime = nil
        return [.cancelPendingRecording]
    }

    public mutating func cancel() -> [Effect] {
        phase = .idle
        shortcutDownTime = nil
        return [.cancelHoldTimer, .cancelDoubleTapTimer]
    }
}
