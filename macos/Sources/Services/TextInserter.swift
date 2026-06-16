import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ShoutOutCore

@MainActor
enum TextInserter {
    private static let clipboardRestoreDelayNanoseconds: UInt64 = 600_000_000

    /// Insert text into the currently focused text field by simulating Cmd+V.
    /// Saves and restores the clipboard content around the paste.
    static func insertText(
        _ text: String,
        options: TextInsertionFormattingOptions = .default
    ) {
        let target = focusedTextInsertionTarget()
        let formatted = TextInsertionFormatter.prepare(text, context: target?.context, options: options)
        let pasteText = formatted.text
        RuntimeLog.write(
            "paste start length=\(pasteText.count) spacing=\(formatted.strategy) smartSpacing=\(options.useSmartSpacing) appendTrailingSpace=\(options.appendTrailingSpace)"
        )

        if let target, insertWithAccessibility(pasteText, target: target) {
            RuntimeLog.write("paste accessibility inserted")
            return
        }

        insertWithClipboard(pasteText)
    }

    // MARK: - Private

    private struct FocusedTextInsertionTarget {
        let element: AXUIElement
        let snapshot: TextInsertionTargetSnapshot

        var context: TextInsertionContext? {
            snapshot.context
        }
    }

    private static func insertWithClipboard(_ pasteText: String) {
        let pasteboard = NSPasteboard.general

        // 1. Save current clipboard contents (all types)
        let savedItems = savePasteboard(pasteboard)

        // 2. Set our text on the clipboard
        pasteboard.clearContents()
        guard pasteboard.setString(pasteText, forType: .string) else {
            restorePasteboard(pasteboard, savedItems: savedItems)
            RuntimeLog.write("paste clipboard set failed")
            return
        }
        let insertedChangeCount = pasteboard.changeCount

        // 3. Simulate Cmd+V
        guard simulatePaste() else {
            restorePasteboard(pasteboard, savedItems: savedItems)
            RuntimeLog.write("paste hotkey failed")
            return
        }

        // 4. Restore clipboard after a delay to let the paste complete
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: clipboardRestoreDelayNanoseconds)
            guard pasteboard.changeCount == insertedChangeCount else {
                RuntimeLog.write("paste clipboard restore skipped changedExternally=true")
                return
            }
            restorePasteboard(pasteboard, savedItems: savedItems)
            RuntimeLog.write("paste clipboard restored")
        }
    }

    private static func focusedTextInsertionTarget() -> FocusedTextInsertionTarget? {
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
        var textValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &textValue
        ) == .success,
            let text = textValue as? String
        else {
            return nil
        }

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
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

        let snapshot = TextInsertionTargetSnapshot(
            text: text,
            selectedUTF16Range: NSRange(
                location: selectedRange.location,
                length: selectedRange.length
            ),
            placeholder: copyStringAttribute(focusedElement, "AXPlaceholderValue" as CFString),
            characterCount: copyIntAttribute(focusedElement, "AXNumberOfCharacters" as CFString)
        )
        if snapshot.isPlaceholderValue {
            RuntimeLog.write("paste accessibility placeholder ignored")
        }

        return FocusedTextInsertionTarget(element: focusedElement, snapshot: snapshot)
    }

    private static func focusedTextInsertionContext() -> TextInsertionContext? {
        focusedTextInsertionTarget()?.context
    }

    private static func insertWithAccessibility(
        _ insertion: String,
        target: FocusedTextInsertionTarget
    ) -> Bool {
        guard let replacement = replacingSelection(
            in: target.snapshot.editableText,
            selectedRange: target.snapshot.editableSelectedUTF16Range,
            with: insertion
        ) else {
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

        return true
    }

    private static func copyStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
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

    private static func simulatePaste() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)

        // V key = keyCode 0x09 (kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        guard let keyDown, let keyUp else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        RuntimeLog.write("paste hotkey posted")
        return true
    }
}
