import Foundation

public struct ShortcutTimingStateMachine: Sendable {
    public enum RecordingMode: Equatable, Sendable {
        case hold
        case handsFree
    }

    public enum Effect: Equatable, Sendable {
        case startHoldTimer
        case cancelHoldTimer
        case startDoubleTapTimer
        case cancelDoubleTapTimer
        case armRecording
        case cancelPendingRecording
        case commitRecording(RecordingMode)
        case stopRecording
        case delayedHoldCommitted(milliseconds: Int)
    }

    private enum Phase: Equatable, Sendable {
        case idle
        case shortcutDownPending
        case waitingForDoubleTap(committed: Bool)
        case holdRecording
        case handsFreeRecording
    }

    public let holdThreshold: TimeInterval
    public let doubleTapWindow: TimeInterval
    public let tapCandidateThreshold: TimeInterval

    private var phase: Phase = .idle
    private var shortcutDownTime: TimeInterval?

    public init(
        holdThreshold: TimeInterval = 0.12,
        doubleTapWindow: TimeInterval = 0.4,
        tapCandidateThreshold: TimeInterval = 0.2
    ) {
        self.holdThreshold = holdThreshold
        self.doubleTapWindow = doubleTapWindow
        self.tapCandidateThreshold = tapCandidateThreshold
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
            return [.cancelDoubleTapTimer, .commitRecording(.handsFree)]

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
                if heldDuration <= tapCandidateThreshold {
                    phase = .waitingForDoubleTap(committed: true)
                    return [
                        .cancelHoldTimer,
                        .delayedHoldCommitted(milliseconds: Int(heldDuration * 1000)),
                        .commitRecording(.hold),
                        .startDoubleTapTimer,
                    ]
                }

                phase = .idle
                shortcutDownTime = nil
                return [
                    .cancelHoldTimer,
                    .delayedHoldCommitted(milliseconds: Int(heldDuration * 1000)),
                    .commitRecording(.hold),
                    .stopRecording,
                ]
            }

            phase = .waitingForDoubleTap(committed: false)
            return [
                .cancelHoldTimer,
                .startDoubleTapTimer,
            ]

        case .holdRecording:
            let heldDuration = max(0, timestamp - (shortcutDownTime ?? timestamp))
            if heldDuration <= tapCandidateThreshold {
                phase = .waitingForDoubleTap(committed: true)
                return [.startDoubleTapTimer]
            }

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
        return [.commitRecording(.hold)]
    }

    public mutating func doubleTapTimerFired() -> [Effect] {
        guard case .waitingForDoubleTap(let committed) = phase else { return [] }
        phase = .idle
        shortcutDownTime = nil
        return committed ? [.stopRecording] : [.cancelPendingRecording]
    }

    public mutating func cancel() -> [Effect] {
        phase = .idle
        shortcutDownTime = nil
        return [.cancelHoldTimer, .cancelDoubleTapTimer]
    }
}
