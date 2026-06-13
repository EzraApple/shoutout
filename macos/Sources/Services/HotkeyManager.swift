import AppKit
import Carbon.HIToolbox

// MARK: - Hotkey Manager

/// Manages the Fn (Globe) key for dictation:
/// - **Double-press Fn**: Hands-free mode (recording starts, press Fn again to stop + transcribe)
/// - **Hold Fn**: Hold-to-talk (release to stop + transcribe)
///
/// Uses a CGEvent tap to intercept Fn before macOS shows the emoji picker.
@MainActor
class HotkeyManager {
    var onRecordArmed: (() -> Void)?
    var onRecordCancelled: (() -> Void)?
    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?
    var onShortcutUnavailable: ((String) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Keep the state object alive for the C callback
    private var stateRef: AnyObject?

    /// Saved original Fn key usage type so we can restore on quit
    private var originalFnUsageType: Int?

    @discardableResult
    func start() -> Bool {
        guard AXIsProcessTrusted() else {
            RuntimeLog.write("hotkey start blocked accessibility=false")
            onShortcutUnavailable?("Accessibility off")
            return false
        }
        stop()

        // Disable the system Globe key behavior (emoji picker / input switching)
        // by setting AppleFnUsageType to 0 ("Do Nothing"). We restore on stop().
        disableSystemFnBehavior()

        let state = FnKeyState()
        state.manager = self
        stateRef = state

        let userInfo = Unmanaged.passUnretained(state).toOpaque()

        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: fnEventCallback,
                userInfo: userInfo
            )
        else {
            RuntimeLog.write("hotkey start failed tapCreate")
            onShortcutUnavailable?("Fn blocked")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        RuntimeLog.write("hotkey start success eventMask=\(eventMask)")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            RuntimeLog.write("hotkey stop")
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        stateRef = nil

        restoreSystemFnBehavior()
    }

    // MARK: - System Fn Key Override

    /// Disable macOS Globe key system action by writing AppleFnUsageType = 0
    private func disableSystemFnBehavior() {
        let defaults = UserDefaults(suiteName: "com.apple.HIToolbox")
        originalFnUsageType = defaults?.integer(forKey: "AppleFnUsageType")
        defaults?.set(0, forKey: "AppleFnUsageType")
        RuntimeLog.write("hotkey disabled system Fn original=\(originalFnUsageType ?? -1)")
    }

    /// Restore the user's original Globe key behavior
    private func restoreSystemFnBehavior() {
        guard let original = originalFnUsageType else { return }
        let defaults = UserDefaults(suiteName: "com.apple.HIToolbox")
        defaults?.set(original, forKey: "AppleFnUsageType")
        originalFnUsageType = nil
        RuntimeLog.write("hotkey restored system Fn original=\(original)")
    }

    func cancelRecording() {
        if let state = stateRef as? FnKeyState {
            state.holdTimer?.cancel()
            state.doubleTapTimer?.cancel()
            state.phase = .idle
        }
    }

    func restartAfterEventTapDisabled() {
        RuntimeLog.write("hotkey restarting after event tap disabled")
        _ = start()
    }
}

// MARK: - State Machine

/// Fn key detection phases:
/// ```
/// idle → fnDown:
///   start audio capture immediately
///   start holdTimer (300ms)
///   → if held past timer → holdRecording → fnUp → stop + transcribe → idle
///   → if released quickly → discard capture, waitingForDoubleTap (400ms window)
///       → fnDown within window → handsFreeRecording starts immediately → fnDown → stop + transcribe → idle
///       → timeout → idle (single tap, ignored)
/// ```
private enum FnPhase {
    case idle
    case fnDownPending          // Fn pressed, waiting to see if it's a hold or first tap
    case waitingForDoubleTap    // First quick tap done, waiting for second tap
    case holdRecording          // Holding Fn, recording in progress
    case handsFreeRecording     // Double-tapped, recording until next Fn press
}

private class FnKeyState: @unchecked Sendable {
    var phase: FnPhase = .idle
    var fnDownTime: CFAbsoluteTime = 0
    var holdTimer: DispatchWorkItem?
    var doubleTapTimer: DispatchWorkItem?
    weak var manager: HotkeyManager?

    /// Track previous Fn flag state so we only suppress events where Fn actually changed.
    /// Without this, modifier key-up events (Shift, Cmd, etc.) get swallowed because
    /// their flags are empty after release, causing "stuck keys" in remote desktop apps.
    var previousFnDown: Bool = false

    /// How long Fn must be held before hold-to-talk activates
    let holdThreshold: TimeInterval = 0.3
    /// Window to detect second tap of double-tap
    let doubleTapWindow: TimeInterval = 0.4
}

// MARK: - CGEvent Callback (C-function, runs on event tap thread)

private func fnEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable if macOS disabled the tap
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        RuntimeLog.write("hotkey event tap disabled type=\(type.rawValue)")
        if let userInfo {
            let state = Unmanaged<FnKeyState>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                state.manager?.restartAfterEventTapDisabled()
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard
        type == .flagsChanged || type == .keyDown || type == .keyUp,
        let userInfo
    else {
        return Unmanaged.passUnretained(event)
    }

    let state = Unmanaged<FnKeyState>.fromOpaque(userInfo).takeUnretainedValue()

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let isFunctionKeyCode = keyCode == Int64(kVK_Function)
    let fnFlag: UInt64 = 0x800000
    let flagsContainFn = (event.flags.rawValue & fnFlag) != 0
    let fnIsDown: Bool
    let detection: String

    if isFunctionKeyCode && (type == .keyDown || type == .keyUp) {
        fnIsDown = type == .keyDown
        detection = "keyCode"
    } else if type == .flagsChanged {
        fnIsDown = flagsContainFn
        detection = "flags"
    } else {
        return Unmanaged.passUnretained(event)
    }

    // Only act on events where the Fn flag actually toggled.
    // flagsChanged fires for ALL modifier changes (Shift, Cmd, etc.).
    // If we suppress non-Fn events, their key-up never reaches the system,
    // causing "stuck" modifiers in remote desktop apps like Parsec.
    let fnChanged = (fnIsDown != state.previousFnDown)
    state.previousFnDown = fnIsDown

    if !fnChanged {
        return Unmanaged.passUnretained(event)
    }

    RuntimeLog.write(
        "hotkey fnChanged detection=\(detection) pressed=\(fnIsDown) type=\(type.rawValue) keyCode=\(keyCode) flags=\(event.flags.rawValue)"
    )

    // Fn flag changed — ignore if other modifiers are also held (Cmd, Opt, Shift, Ctrl)
    let otherModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
    let hasOtherModifiers = !event.flags.intersection(otherModifiers).isEmpty
    if hasOtherModifiers {
        return Unmanaged.passUnretained(event)
    }

    DispatchQueue.main.async {
        handleFnStateChange(state: state, fnPressed: fnIsDown)
    }

    // Suppress Fn events to prevent macOS from showing
    // the emoji picker, keyboard switcher, or dictation panel.
    return nil
}

@MainActor
private func handleFnStateChange(state: FnKeyState, fnPressed: Bool) {
    switch state.phase {

    case .idle:
        if fnPressed {
            state.phase = .fnDownPending
            state.fnDownTime = CFAbsoluteTimeGetCurrent()
            state.manager?.onRecordArmed?()

            // Start hold timer
            state.holdTimer?.cancel()
            let holdWork = DispatchWorkItem { [weak state] in
                guard let state, state.phase == .fnDownPending else { return }
                // Held long enough → hold-to-talk
                state.phase = .holdRecording
                state.manager?.onRecordStart?()
            }
            state.holdTimer = holdWork
            DispatchQueue.main.asyncAfter(
                deadline: .now() + state.holdThreshold, execute: holdWork)
        }

    case .fnDownPending:
        if !fnPressed {
            // Released quickly → could be first tap of double-tap
            state.holdTimer?.cancel()
            state.holdTimer = nil
            state.phase = .waitingForDoubleTap
            state.manager?.onRecordCancelled?()

            // Start double-tap window timer
            state.doubleTapTimer?.cancel()
            let dtWork = DispatchWorkItem { [weak state] in
                guard let state, state.phase == .waitingForDoubleTap else { return }
                // Timeout: was just a single tap → do nothing
                state.phase = .idle
                state.manager?.onRecordCancelled?()
            }
            state.doubleTapTimer = dtWork
            DispatchQueue.main.asyncAfter(
                deadline: .now() + state.doubleTapWindow, execute: dtWork)
        }

    case .waitingForDoubleTap:
        if fnPressed {
            // Second tap! → hands-free recording
            state.doubleTapTimer?.cancel()
            state.doubleTapTimer = nil
            state.phase = .handsFreeRecording
            state.manager?.onRecordStart?()
        }

    case .holdRecording:
        if !fnPressed {
            // Released → stop recording + transcribe
            state.phase = .idle
            state.manager?.onRecordStop?()
        }

    case .handsFreeRecording:
        if fnPressed {
            // Next Fn press → stop recording + transcribe
            state.phase = .idle
            state.manager?.onRecordStop?()
        }
    }
}
