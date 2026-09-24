import Foundation

/// Best-effort lifetime of a native macOS screenshot. Times use a monotonic clock.
public struct ScreenshotSuppression {
    public enum Mode: Sendable {
        case entireScreen, selection, toolbar
    }

    public private(set) var mode: Mode?
    private var restoreAt: TimeInterval?
    private var recoveryAt: TimeInterval = 0
    private var captureUIWasVisible = false
    private var cancellationRequested = false

    public init() {}

    public var isSuppressed: Bool { mode != nil }

    public mutating func begin(_ mode: Mode, at time: TimeInterval) {
        self.mode = mode
        restoreAt = mode == .entireScreen ? time + 1.5 : nil
        recoveryAt = time + 300
        captureUIWasVisible = false
        cancellationRequested = false
    }

    public mutating func completeInteraction(at time: TimeInterval) {
        guard let mode, mode != .entireScreen, restoreAt == nil else { return }
        cancellationRequested = false
        // The Screenshot toolbar supports a ten-second timer. Its disappearance
        // or Capture click is not proof that the image has been taken yet.
        restoreAt = time + (mode == .toolbar ? 12 : 1)
        recoveryAt = time + 300
    }

    public mutating func cancel(at time: TimeInterval) {
        guard isSuppressed else { return }
        cancellationRequested = true
        restoreAt = time + 0.3
    }

    public mutating func update(captureUIVisible: Bool, at time: TimeInterval) {
        guard let mode else { return }
        if mode != .entireScreen {
            if captureUIVisible {
                // Includes toolbar menus: clicking Options or dismissing one
                // must not reveal the overlay while capture is still pending.
                restoreAt = nil
            } else if captureUIWasVisible && restoreAt == nil {
                if cancellationRequested {
                    cancel(at: time)
                } else {
                    completeInteraction(at: time)
                }
            }
            captureUIWasVisible = captureUIVisible
        }
        if time >= recoveryAt || restoreAt.map({ time >= $0 }) == true {
            self.mode = nil
            restoreAt = nil
        }
    }
}
