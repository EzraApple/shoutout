import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ShoutOutCore

@MainActor
enum TextInserter {
    private static let clipboardRestoreTimeoutNanoseconds: UInt64 = 900_000_000
    private static let clipboardVerifiedRestoreGraceNanoseconds: UInt64 = 150_000_000
    private static let pasteVerificationPollNanoseconds: UInt64 = 50_000_000
    private static var pendingClipboardRestore: PendingClipboardRestore?
    private static var clipboardRestoreTask: Task<Void, Never>?

    /// Insert text into the currently focused text field by simulating Cmd+V.
    /// Saves and restores the clipboard content around the paste.
    static func insertText(
        _ text: String,
        options: TextInsertionFormattingOptions = .default,
        target preferredTarget: CapturedTarget? = nil
    ) {
        let target = refreshedTarget(from: preferredTarget) ?? captureFocusedTarget()
        let formatted = TextInsertionFormatter.prepare(text, context: target?.context, options: options)
        let pasteText = formatted.text
        RuntimeLog.write(
            "paste start length=\(pasteText.count) spacing=\(formatted.strategy) smartSpacing=\(options.useSmartSpacing) appendTrailingSpace=\(options.appendTrailingSpace)"
        )

        if let target {
            if shouldUseAccessibilityInsertion(for: target),
                insertWithAccessibility(pasteText, target: target)
            {
                RuntimeLog.write("paste accessibility inserted")
                return
            }
        }

        insertWithClipboard(pasteText, target: target)
    }

    static func captureFocusedTarget() -> CapturedTarget? {
        focusedTextInsertionTarget()
    }

    // MARK: - Private

    struct CapturedTarget: @unchecked Sendable {
        let element: AXUIElement
        let snapshot: TextInsertionTargetSnapshot
        let bundleIdentifier: String?
        let processIdentifier: pid_t

        var context: TextInsertionContext? {
            snapshot.context
        }
    }

    private struct PendingClipboardRestore {
        let savedItems: [NSPasteboardItem]
    }

    private struct FocusedTextState: Equatable {
        let text: String
        let selectedRange: NSRange
    }

    private enum PasteVerification {
        case unavailable
        case verified
        case unchanged
    }

    private static func insertWithClipboard(
        _ pasteText: String,
        target: CapturedTarget?
    ) {
        let pasteboard = NSPasteboard.general

        // 1. Save current clipboard contents (all types). If a prior restore is pending,
        // keep its original snapshot so quick back-to-back dictations do not capture our
        // generated paste text as the user's clipboard.
        let restore = pendingClipboardRestore ?? PendingClipboardRestore(
            savedItems: savePasteboard(pasteboard)
        )
        pendingClipboardRestore = restore
        clipboardRestoreTask?.cancel()
        clipboardRestoreTask = nil
        let verificationState = target.flatMap { focusedTextState(for: $0.element) }

        // 2. Set our text on the clipboard
        pasteboard.clearContents()
        guard pasteboard.setString(pasteText, forType: .string) else {
            restorePasteboard(pasteboard, savedItems: restore.savedItems)
            pendingClipboardRestore = nil
            RuntimeLog.write("paste clipboard set failed")
            return
        }
        let insertedChangeCount = pasteboard.changeCount

        // 3. Simulate Cmd+V
        guard simulatePaste(targetPID: target?.processIdentifier) else {
            restorePasteboard(pasteboard, savedItems: restore.savedItems)
            pendingClipboardRestore = nil
            RuntimeLog.write("paste hotkey failed")
            return
        }

        // 4. Restore clipboard after paste verification or a bounded timeout.
        clipboardRestoreTask = Task { @MainActor in
            let verification = await waitForPasteVerification(
                from: verificationState,
                target: target
            )
            guard !Task.isCancelled else { return }

            if verification == .verified {
                try? await Task.sleep(nanoseconds: clipboardVerifiedRestoreGraceNanoseconds)
                guard !Task.isCancelled else { return }
            }

            let clipboardStillLooksOurs =
                pasteboard.changeCount == insertedChangeCount
                || pasteboard.string(forType: .string) == pasteText
            guard clipboardStillLooksOurs else {
                pendingClipboardRestore = nil
                clipboardRestoreTask = nil
                RuntimeLog.write("paste clipboard restore skipped changedExternally=true")
                return
            }

            guard verification != .unchanged else {
                pendingClipboardRestore = nil
                clipboardRestoreTask = nil
                RuntimeLog.write("paste clipboard restore skipped reason=unverified")
                return
            }

            restorePasteboard(pasteboard, savedItems: restore.savedItems)
            pendingClipboardRestore = nil
            clipboardRestoreTask = nil
            RuntimeLog.write("paste clipboard restored verification=\(verification)")
        }
    }

    private static func focusedTextInsertionTarget() -> CapturedTarget? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        guard frontmostApp.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let focusedElement = focusedValue as! AXUIElement
        guard let snapshot = targetSnapshot(for: focusedElement) else {
            return nil
        }

        if snapshot.isPlaceholderValue {
            RuntimeLog.write("paste accessibility placeholder ignored")
        }

        return CapturedTarget(
            element: focusedElement,
            snapshot: snapshot,
            bundleIdentifier: frontmostApp.bundleIdentifier,
            processIdentifier: frontmostApp.processIdentifier
        )
    }

    private static func focusedTextInsertionContext() -> TextInsertionContext? {
        focusedTextInsertionTarget()?.context
    }

    private static func refreshedTarget(from target: CapturedTarget?) -> CapturedTarget? {
        guard let target,
            let snapshot = targetSnapshot(for: target.element)
        else {
            return nil
        }

        return CapturedTarget(
            element: target.element,
            snapshot: snapshot,
            bundleIdentifier: target.bundleIdentifier,
            processIdentifier: target.processIdentifier
        )
    }

    private static func targetSnapshot(for element: AXUIElement) -> TextInsertionTargetSnapshot? {
        var textValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &textValue
        ) == .success,
            let text = textValue as? String
        else {
            return nil
        }

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success,
            let rangeValue,
            CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let axRange = rangeValue as! AXValue
        var selectedRange = CFRange()
        guard AXValueGetType(axRange) == .cfRange,
            AXValueGetValue(axRange, .cfRange, &selectedRange)
        else {
            return nil
        }

        return TextInsertionTargetSnapshot(
            text: text,
            selectedUTF16Range: NSRange(
                location: selectedRange.location,
                length: selectedRange.length
            ),
            placeholder: copyFirstStringAttribute(
                element,
                [
                    "AXPlaceholderValue" as CFString,
                    "AXDescription" as CFString,
                    "AXHelp" as CFString,
                ]
            ),
            characterCount: copyIntAttribute(element, "AXNumberOfCharacters" as CFString)
        )
    }

    private static func insertWithAccessibility(
        _ insertion: String,
        target: CapturedTarget
    ) -> Bool {
        guard let replacement = replacingSelection(
            in: target.snapshot.editableText,
            selectedRange: target.snapshot.editableSelectedUTF16Range,
            with: insertion
        ) else {
            return false
        }

        var isSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            target.element,
            kAXValueAttribute as CFString,
            &isSettable
        ) == .success,
            isSettable.boolValue
        else {
            RuntimeLog.write("paste accessibility value skipped settable=false")
            return false
        }

        let valueStatus = AXUIElementSetAttributeValue(
            target.element,
            kAXValueAttribute as CFString,
            replacement.text as CFTypeRef
        )
        guard valueStatus == .success else {
            RuntimeLog.write("paste accessibility value failed status=\(valueStatus.rawValue)")
            return false
        }

        var cfRange = CFRange(
            location: replacement.selection.location,
            length: replacement.selection.length
        )
        if let axRange = AXValueCreate(.cfRange, &cfRange) {
            _ = AXUIElementSetAttributeValue(
                target.element,
                kAXSelectedTextRangeAttribute as CFString,
                axRange
            )
        }

        guard let verifiedSnapshot = targetSnapshot(for: target.element),
            verifiedSnapshot.editableText == replacement.text
        else {
            RuntimeLog.write("paste accessibility unverified; falling back to clipboard")
            return false
        }

        return true
    }

    private static func shouldUseAccessibilityInsertion(
        for target: CapturedTarget
    ) -> Bool {
        if target.snapshot.isPlaceholderValue {
            RuntimeLog.write("paste accessibility skipped reason=placeholder")
            return false
        }

        guard let bundleIdentifier = target.bundleIdentifier else {
            return true
        }

        if Self.prefersClipboardInsertion(bundleIdentifier: bundleIdentifier) {
            RuntimeLog.write("paste accessibility skipped reason=webShell bundle=\(bundleIdentifier)")
            return false
        }

        return true
    }

    private static func prefersClipboardInsertion(bundleIdentifier: String) -> Bool {
        if clipboardPreferredBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        return clipboardPreferredBundlePrefixes.contains { prefix in
            bundleIdentifier.hasPrefix(prefix)
        }
    }

    private static func focusedTextState(for element: AXUIElement) -> FocusedTextState? {
        guard let snapshot = targetSnapshot(for: element) else {
            return nil
        }

        return FocusedTextState(
            text: snapshot.editableText,
            selectedRange: snapshot.editableSelectedUTF16Range
        )
    }

    private static func waitForPasteVerification(
        from initialState: FocusedTextState?,
        target: CapturedTarget?
    ) async -> PasteVerification {
        guard let initialState, let target else {
            try? await Task.sleep(nanoseconds: clipboardRestoreTimeoutNanoseconds)
            return .unavailable
        }

        let deadline = Date().addingTimeInterval(
            Double(clipboardRestoreTimeoutNanoseconds) / 1_000_000_000
        )
        while !Task.isCancelled, Date() < deadline {
            if let currentState = focusedTextState(for: target.element),
                currentState != initialState
            {
                RuntimeLog.write("paste clipboard verified")
                return .verified
            }
            try? await Task.sleep(nanoseconds: pasteVerificationPollNanoseconds)
        }

        return .unchanged
    }

    private static let clipboardPreferredBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.brave.Browser",
        "com.google.Chrome",
        "com.linear",
        "com.microsoft.edgemac",
        "com.openai.chat",
        "com.openai.codex",
        "com.tinyspeck.slackmacgap",
        "com.todesktop.230313mzl4w4u92",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
    ]

    private static let clipboardPreferredBundlePrefixes = [
        "com.openai.",
    ]

    private static func copyStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func copyFirstStringAttribute(
        _ element: AXUIElement,
        _ attributes: [CFString]
    ) -> String? {
        for attribute in attributes {
            if let value = copyStringAttribute(element, attribute), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func copyIntAttribute(_ element: AXUIElement, _ attribute: CFString) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return value as? Int
    }

    private static func replacingSelection(
        in text: String,
        selectedRange: NSRange,
        with insertion: String
    ) -> (text: String, selection: NSRange)? {
        guard selectedRange.location >= 0, selectedRange.length >= 0 else {
            return nil
        }

        let utf16 = text.utf16
        guard
            let start16 = utf16.index(
                utf16.startIndex,
                offsetBy: selectedRange.location,
                limitedBy: utf16.endIndex
            ),
            let end16 = utf16.index(
                start16,
                offsetBy: selectedRange.length,
                limitedBy: utf16.endIndex
            ),
            let start = String.Index(start16, within: text),
            let end = String.Index(end16, within: text)
        else {
            return nil
        }

        var updatedText = text
        updatedText.replaceSubrange(start..<end, with: insertion)
        return (
            text: updatedText,
            selection: NSRange(location: selectedRange.location + insertion.utf16.count, length: 0)
        )
    }

    private static func savePasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }

        return items.compactMap { item in
            let newItem = NSPasteboardItem()
            var hasData = false
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                    hasData = true
                }
            }
            return hasData ? newItem : nil
        }
    }

    private static func restorePasteboard(
        _ pasteboard: NSPasteboard,
        savedItems: [NSPasteboardItem]
    ) {
        pasteboard.clearContents()
        if !savedItems.isEmpty {
            pasteboard.writeObjects(savedItems)
        }
    }

    private static func simulatePaste(targetPID: pid_t?) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)

        // V key = keyCode 0x09 (kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        guard let keyDown, let keyUp else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        if let targetPID, targetPID > 0 {
            keyDown.postToPid(targetPID)
            usleep(10_000)
            keyUp.postToPid(targetPID)
            RuntimeLog.write("paste hotkey posted targetPID=\(targetPID)")
        } else {
            keyDown.post(tap: .cghidEventTap)
            usleep(10_000)
            keyUp.post(tap: .cghidEventTap)
            RuntimeLog.write("paste hotkey posted")
        }
        return true
    }
}
