import AppKit
import Carbon.HIToolbox
import ShoutOutCore

// MARK: - Hotkey Manager

/// Manages the global shortcut for dictation:
/// - **Double-press shortcut**: Hands-free mode (recording starts, press again to stop + transcribe)
/// - **Hold shortcut**: Hold-to-talk (release to stop + transcribe)
///
/// Uses a CGEvent tap so hold-to-talk works outside the app.
@MainActor
class HotkeyManager {
    var onRecordArmed: (() -> Void)?
    var onRecordCancelled: (() -> Void)?
    var onRecordStart: ((ShortcutTimingStateMachine.RecordingMode) -> Void)?
    var onRecordStop: (() -> Void)?
    var onShortcutUnavailable: ((String) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentTrigger: HotkeyTrigger = .defaultTrigger

    /// Keep the state object alive for the C callback
    private var stateRef: AnyObject?

    /// Saved original Fn key usage type so we can restore on quit
    private var originalFnUsageType: Int?
    private var originalFnUsageTypeWasMissing = false

    private enum FnDefaults {
        static let suiteName = "com.apple.HIToolbox"
        static let appleFnUsageType = "AppleFnUsageType"
        static let didOverride = "hotkey.didOverrideAppleFnUsageType"
        static let savedValue = "hotkey.savedAppleFnUsageType"
        static let savedValueWasMissing = "hotkey.savedAppleFnUsageTypeWasMissing"
    }

    @discardableResult
    func start(trigger: HotkeyTrigger = .stored) -> Bool {
        currentTrigger = trigger
        recoverSystemFnBehaviorIfNeeded()

        guard AXIsProcessTrusted() else {
            RuntimeLog.write("hotkey start blocked accessibility=false")
            onShortcutUnavailable?("Accessibility off")
            return false
        }
        stop()

        if trigger.usesFunctionKey {
            // Disable the system Globe key behavior (emoji picker / input switching)
            // by setting AppleFnUsageType to 0 ("Do Nothing"). We restore on stop().
            disableSystemFnBehavior()
        }

        let state = ShortcutKeyState(trigger: trigger)
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
            onShortcutUnavailable?("\(trigger.displayName) blocked")
            restoreSystemFnBehavior()
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        RuntimeLog.write("hotkey start success trigger=\(trigger.rawValue) eventMask=\(eventMask)")
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
        guard let defaults = UserDefaults(suiteName: FnDefaults.suiteName) else {
            RuntimeLog.write("hotkey disable system Fn failed defaultsUnavailable")
            return
        }

        let existingValue = defaults.object(forKey: FnDefaults.appleFnUsageType) as? Int
        originalFnUsageType = existingValue
        originalFnUsageTypeWasMissing = existingValue == nil
        persistOriginalFnUsageType(value: existingValue, wasMissing: originalFnUsageTypeWasMissing)

        defaults.set(0, forKey: FnDefaults.appleFnUsageType)
        RuntimeLog.write("hotkey disabled system Fn original=\(existingValue ?? -1)")
    }

    /// Restore the user's original Globe key behavior
    private func restoreSystemFnBehavior() {
        guard originalFnUsageType != nil || originalFnUsageTypeWasMissing else { return }
        restoreSystemFnBehavior(
            value: originalFnUsageType,
            wasMissing: originalFnUsageTypeWasMissing
        )
        originalFnUsageType = nil
        originalFnUsageTypeWasMissing = false
        clearPersistedOriginalFnUsageType()
    }

    private func recoverSystemFnBehaviorIfNeeded() {
        guard UserDefaults.standard.bool(forKey: FnDefaults.didOverride) else { return }

        let wasMissing = UserDefaults.standard.bool(forKey: FnDefaults.savedValueWasMissing)
        let value = UserDefaults.standard.object(forKey: FnDefaults.savedValue) as? Int
        restoreSystemFnBehavior(value: value, wasMissing: wasMissing)
        clearPersistedOriginalFnUsageType()
    }

    private func restoreSystemFnBehavior(value: Int?, wasMissing: Bool) {
        guard let defaults = UserDefaults(suiteName: FnDefaults.suiteName) else {
            RuntimeLog.write("hotkey restore system Fn failed defaultsUnavailable")
            return
        }

        if wasMissing {
            defaults.removeObject(forKey: FnDefaults.appleFnUsageType)
            RuntimeLog.write("hotkey restored system Fn original=missing")
        } else if let value {
            defaults.set(value, forKey: FnDefaults.appleFnUsageType)
            RuntimeLog.write("hotkey restored system Fn original=\(value)")
        }
    }

    private func persistOriginalFnUsageType(value: Int?, wasMissing: Bool) {
        UserDefaults.standard.set(true, forKey: FnDefaults.didOverride)
        UserDefaults.standard.set(wasMissing, forKey: FnDefaults.savedValueWasMissing)
        if let value {
            UserDefaults.standard.set(value, forKey: FnDefaults.savedValue)
        } else {
            UserDefaults.standard.removeObject(forKey: FnDefaults.savedValue)
        }
    }

    private func clearPersistedOriginalFnUsageType() {
        UserDefaults.standard.removeObject(forKey: FnDefaults.didOverride)
        UserDefaults.standard.removeObject(forKey: FnDefaults.savedValue)
        UserDefaults.standard.removeObject(forKey: FnDefaults.savedValueWasMissing)
    }

    func cancelRecording() {
        if let state = stateRef as? ShortcutKeyState {
            applyShortcutTimingEffects(state.timing.cancel(), state: state)
        }
    }

    func restartAfterEventTapDisabled() {
        RuntimeLog.write("hotkey restarting after event tap disabled")
        _ = start(trigger: currentTrigger)
    }
}

private class ShortcutKeyState: @unchecked Sendable {
    let trigger: HotkeyTrigger
    var timing = ShortcutTimingStateMachine()
    var holdTimer: DispatchWorkItem?
    var doubleTapTimer: DispatchWorkItem?
    weak var manager: HotkeyManager?

    /// Track previous Fn flag state so we only suppress events where Fn actually changed.
    /// Without this, modifier key-up events (Shift, Cmd, etc.) get swallowed because
    /// their flags are empty after release, causing "stuck keys" in remote desktop apps.
    var previousShortcutDown: Bool = false

    init(trigger: HotkeyTrigger) {
        self.trigger = trigger
    }
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
            let state = Unmanaged<ShortcutKeyState>.fromOpaque(userInfo).takeUnretainedValue()
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

    let state = Unmanaged<ShortcutKeyState>.fromOpaque(userInfo).takeUnretainedValue()
    let trigger = state.trigger

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let shortcutIsDown: Bool
    let detection: String

    if trigger.usesFunctionKey {
        let isFunctionKeyCode = keyCode == Int64(kVK_Function)
        let fnFlag: UInt64 = 0x800000
        let flagsContainFn = (event.flags.rawValue & fnFlag) != 0

        if isFunctionKeyCode && (type == .keyDown || type == .keyUp) {
            shortcutIsDown = type == .keyDown
            detection = "functionKeyCode"
        } else if type == .flagsChanged {
            shortcutIsDown = flagsContainFn
            detection = "functionFlags"
        } else {
            return Unmanaged.passUnretained(event)
        }
    } else {
        guard
            let triggerKeyCode = trigger.keyCode,
            keyCode == triggerKeyCode,
            type == .keyDown || type == .keyUp
        else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            guard trigger.modifiersMatch(event.flags) else {
                return Unmanaged.passUnretained(event)
            }
            shortcutIsDown = true
            detection = "keyComboDown"
        } else {
            guard state.previousShortcutDown else {
                return Unmanaged.passUnretained(event)
            }
            shortcutIsDown = false
            detection = "keyComboUp"
        }
    }

    // Only act on events where the shortcut actually toggled.
    // flagsChanged fires for ALL modifier changes (Shift, Cmd, etc.).
    // If we suppress non-Fn events, their key-up never reaches the system,
    // causing "stuck" modifiers in remote desktop apps like Parsec.
    let shortcutChanged = (shortcutIsDown != state.previousShortcutDown)
    state.previousShortcutDown = shortcutIsDown

    if !shortcutChanged {
        return nil
    }

    RuntimeLog.write(
        "hotkey changed trigger=\(trigger.rawValue) detection=\(detection) pressed=\(shortcutIsDown) type=\(type.rawValue) keyCode=\(keyCode) flags=\(event.flags.rawValue)"
    )

    if trigger.usesFunctionKey {
        // Fn flag changed. Ignore if other modifiers are also held.
        let otherModifiers: CGEventFlags = [
            .maskCommand,
            .maskAlternate,
            .maskShift,
            .maskControl,
        ]
        let hasOtherModifiers = !event.flags.intersection(otherModifiers).isEmpty
        if hasOtherModifiers {
            return Unmanaged.passUnretained(event)
        }
    }

    let eventTimestamp = CFAbsoluteTimeGetCurrent()
    DispatchQueue.main.async {
        handleShortcutStateChange(
            state: state,
            shortcutPressed: shortcutIsDown,
            eventTimestamp: eventTimestamp
        )
    }

    // Suppress shortcut events so the chosen trigger does not leak into the app.
    return nil
}

@MainActor
private func handleShortcutStateChange(
    state: ShortcutKeyState,
    shortcutPressed: Bool,
    eventTimestamp: TimeInterval
) {
    let effects = shortcutPressed
        ? state.timing.shortcutDown(at: eventTimestamp)
        : state.timing.shortcutUp(at: eventTimestamp)
    applyShortcutTimingEffects(effects, state: state)
}

@MainActor
private func applyShortcutTimingEffects(
    _ effects: [ShortcutTimingStateMachine.Effect],
    state: ShortcutKeyState
) {
    for effect in effects {
        switch effect {
        case .startHoldTimer:
            state.holdTimer?.cancel()
            let holdWork = DispatchWorkItem { [weak state] in
                guard let state else { return }
                applyShortcutTimingEffects(state.timing.holdTimerFired(), state: state)
            }
            state.holdTimer = holdWork
            DispatchQueue.main.asyncAfter(
                deadline: .now() + state.timing.holdThreshold,
                execute: holdWork
            )

        case .cancelHoldTimer:
            state.holdTimer?.cancel()
            state.holdTimer = nil

        case .startDoubleTapTimer:
            state.doubleTapTimer?.cancel()
            let doubleTapWork = DispatchWorkItem { [weak state] in
                guard let state else { return }
                applyShortcutTimingEffects(state.timing.doubleTapTimerFired(), state: state)
            }
            state.doubleTapTimer = doubleTapWork
            DispatchQueue.main.asyncAfter(
                deadline: .now() + state.timing.doubleTapWindow,
                execute: doubleTapWork
            )

        case .cancelDoubleTapTimer:
            state.doubleTapTimer?.cancel()
            state.doubleTapTimer = nil

        case .armRecording:
            // start audio capture immediately on key-down so speech is not clipped.
            state.manager?.onRecordArmed?()

        case .cancelPendingRecording:
            state.manager?.onRecordCancelled?()

        case .commitRecording(let mode):
            state.manager?.onRecordStart?(mode)

        case .stopRecording:
            state.manager?.onRecordStop?()

        case .delayedHoldCommitted(let milliseconds):
            RuntimeLog.write("hotkey hold release committed heldMs=\(milliseconds)")
        }
    }
}
