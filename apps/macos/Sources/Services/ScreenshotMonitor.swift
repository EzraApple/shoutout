import AppKit
import Carbon.HIToolbox
import ShoutOutCore

/// A value snapshot; CGEvent itself must not cross an actor boundary.
struct ScreenshotInput: Sendable {
    let type: CGEventType
    let keyCode: Int64
    let flags: CGEventFlags
    let isRepeat: Bool

    init(type: CGEventType, event: CGEvent) {
        self.type = type
        keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        flags = event.flags
        isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    }
}

/// Observes native screenshot shortcuts without consuming or replaying input.
@MainActor
final class ScreenshotMonitor {
    var onSuppressionChanged: ((Bool) -> Void)?

    private var suppression = ScreenshotSuppression()
    private var pollTask: Task<Void, Never>?
    private var baselineWindows: Set<CGWindowID> = []

    func handleInput(_ input: ScreenshotInput) {
        let time = ProcessInfo.processInfo.systemUptime
        if input.type == .keyDown {
            let keyCode = input.keyCode
            if let mode = screenshotMode(keyCode: keyCode, flags: input.flags) {
                guard !input.isRepeat else { return }
                begin(mode, at: time)
            } else if keyCode == Int64(kVK_Escape) {
                suppression.cancel(at: time)
            } else if keyCode == Int64(kVK_Return) || keyCode == Int64(kVK_ANSI_KeypadEnter) {
                suppression.completeInteraction(at: time)
            }
        } else if input.type == .leftMouseUp {
            suppression.completeInteraction(at: time)
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        if suppression.isSuppressed {
            suppression = ScreenshotSuppression()
            onSuppressionChanged?(false)
        }
        baselineWindows.removeAll()
    }

    private func begin(_ mode: ScreenshotSuppression.Mode, at time: TimeInterval) {
        // This callback runs synchronously on the event tap's main run loop,
        // before the original shortcut continues to the system screenshot tool.
        // Do not dispatch the hide asynchronously: immediate captures can race it.
        let wasSuppressed = suppression.isSuppressed
        suppression.begin(mode, at: time)
        onSuppressionChanged?(true)
        if !wasSuppressed {
            // Screenshot can retain an idle, full-screen window. Only windows
            // appearing during this interaction count as capture UI.
            baselineWindows = screenshotWindowIDs()
        }
        RuntimeLog.write("screenshot overlay suppressed mode=\(mode)")
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    return
                }
                guard let self else { return }
                let captureUIVisible = self.suppression.mode != .entireScreen
                    && !screenshotWindowIDs().subtracting(self.baselineWindows).isEmpty
                self.suppression.update(
                    captureUIVisible: captureUIVisible,
                    at: ProcessInfo.processInfo.systemUptime
                )
                if !self.suppression.isSuppressed {
                    self.baselineWindows.removeAll()
                    self.onSuppressionChanged?(false)
                    RuntimeLog.write("screenshot overlay restored")
                    self.pollTask = nil
                    return
                }
            }
        }
    }
}

private func screenshotMode(keyCode: Int64, flags: CGEventFlags) -> ScreenshotSuppression.Mode? {
    guard flags.contains([.maskCommand, .maskShift]),
        !flags.contains(.maskAlternate)
    else { return nil }
    // Control is deliberately allowed for the native copy-to-clipboard variants.
    switch keyCode {
    case Int64(kVK_ANSI_3): return .entireScreen
    case Int64(kVK_ANSI_4): return .selection
    case Int64(kVK_ANSI_5): return .toolbar
    default: return nil
    }
}

@MainActor
private func screenshotWindowIDs() -> Set<CGWindowID> {
    let processIDs = Set(NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.apple.screencaptureui"
    ).map(\.processIdentifier))
    guard !processIDs.isEmpty,
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]]
    else { return [] }

    // Window IDs and owner PIDs are available without Screen Recording access;
    // no window titles, contents, or screenshot files are read.
    return Set(windows.compactMap { window in
        guard let owner = window[kCGWindowOwnerPID as String] as? pid_t,
            processIDs.contains(owner),
            let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0
        else { return nil }
        return window[kCGWindowNumber as String] as? CGWindowID
    })
}
