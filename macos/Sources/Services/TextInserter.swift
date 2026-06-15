import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ShoutOutCore

@MainActor
enum TextInserter {

    /// Insert text into the currently focused text field by simulating Cmd+V.
    /// Saves and restores the clipboard content around the paste.
    static func insertText(
        _ text: String,
        options: TextInsertionFormattingOptions = .default
    ) {
        let context = focusedTextInsertionContext()
        let formatted = TextInsertionFormatter.prepare(text, context: context, options: options)
        let pasteText = formatted.text
        RuntimeLog.write(
            "paste start length=\(pasteText.count) spacing=\(formatted.strategy) smartSpacing=\(options.useSmartSpacing) appendTrailingSpace=\(options.appendTrailingSpace)"
        )
        let pasteboard = NSPasteboard.general

        // 1. Save current clipboard contents (all types)
        let savedItems = savePasteboard(pasteboard)

        // 2. Set our text on the clipboard
        pasteboard.clearContents()
        pasteboard.setString(pasteText, forType: .string)

        // 3. Simulate Cmd+V
        simulatePaste()

        // 4. Restore clipboard after a delay to let the paste complete
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                pasteboard.writeObjects(savedItems)
            }
            RuntimeLog.write("paste clipboard restored")
        }
    }

    // MARK: - Private

    private static func focusedTextInsertionContext() -> TextInsertionContext? {
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

        return TextInsertionContext(
            text: text,
            selectedUTF16Range: NSRange(
                location: selectedRange.location,
                length: selectedRange.length
            )
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

    private static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // V key = keyCode 0x09 (kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        RuntimeLog.write("paste hotkey posted")
    }
}
