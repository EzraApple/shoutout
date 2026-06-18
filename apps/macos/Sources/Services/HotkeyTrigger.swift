import AppKit
import Carbon.HIToolbox

enum HotkeyTrigger: String, CaseIterable, Identifiable, Sendable {
    case function
    case optionSpace
    case commandShiftSpace
    case controlSpace

    static let defaultTrigger: HotkeyTrigger = .function

    var id: String { rawValue }

    static var stored: HotkeyTrigger {
        let rawValue = UserDefaults.standard.string(forKey: Defaults.hotkeyTrigger)
        return HotkeyTrigger(rawValue: rawValue ?? "") ?? defaultTrigger
    }

    var displayName: String {
        switch self {
        case .function:
            return "Fn / Globe"
        case .optionSpace:
            return "Option Space"
        case .commandShiftSpace:
            return "Command Shift Space"
        case .controlSpace:
            return "Control Space"
        }
    }

    var detailText: String {
        switch self {
        case .function:
            return "Default. Uses the Mac Globe key behavior override while ShoutOut runs."
        case .optionSpace:
            return "A simple combo that avoids the Globe key."
        case .commandShiftSpace:
            return "Good if Option Space conflicts with your editor."
        case .controlSpace:
            return "Familiar, but may conflict with input source switching on some Macs."
        }
    }

    var usesFunctionKey: Bool {
        self == .function
    }

    var keyCode: Int64? {
        switch self {
        case .function:
            return nil
        case .optionSpace, .commandShiftSpace, .controlSpace:
            return Int64(kVK_Space)
        }
    }

    private var requiredModifierFlags: CGEventFlags {
        switch self {
        case .function:
            return []
        case .optionSpace:
            return [.maskAlternate]
        case .commandShiftSpace:
            return [.maskCommand, .maskShift]
        case .controlSpace:
            return [.maskControl]
        }
    }

    func modifiersMatch(_ flags: CGEventFlags) -> Bool {
        let trackedModifiers: CGEventFlags = [
            .maskCommand,
            .maskAlternate,
            .maskShift,
            .maskControl,
        ]
        return flags.intersection(trackedModifiers) == requiredModifierFlags
    }
}
