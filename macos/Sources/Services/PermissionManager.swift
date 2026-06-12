import AppKit
import AVFoundation
import CoreGraphics

extension Notification.Name {
    static let shoutOutPermissionsChanged = Notification.Name("ShoutOutPermissionsChanged")
}

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var hasAccessibility: Bool = false
    @Published var hasInputMonitoring: Bool = false
    @Published var hasMicrophone: Bool = false

    private var lastSnapshot: PermissionSnapshot?
    private var refreshPollTask: Task<Void, Never>?

    private init() {
        refresh()
    }

    var missingPermissionNames: [String] {
        var names: [String] = []
        if !hasAccessibility {
            names.append("Accessibility")
        }
        if !hasInputMonitoring {
            names.append("Input Monitoring")
        }
        if !hasMicrophone {
            names.append("Microphone")
        }
        return names
    }

    var missingHotkeyPermissionNames: [String] {
        var names: [String] = []
        if !hasAccessibility {
            names.append("Accessibility")
        }
        if !hasInputMonitoring {
            names.append("Input Monitoring")
        }
        return names
    }

    var statusText: String {
        let missing = missingPermissionNames
        if missing.isEmpty {
            return "Ready"
        }
        return "Missing \(missing.joined(separator: ", "))"
    }

    var hotkeyStatusText: String {
        let missing = missingHotkeyPermissionNames
        if missing.isEmpty {
            return "Ready"
        }
        return "Grant \(missing.joined(separator: " + "))"
    }

    func refresh() {
        let snapshot = PermissionSnapshot(
            hasAccessibility: AXIsProcessTrusted(),
            hasInputMonitoring: CGPreflightListenEventAccess(),
            hasMicrophone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        )

        hasAccessibility = snapshot.hasAccessibility
        hasInputMonitoring = snapshot.hasInputMonitoring
        hasMicrophone = snapshot.hasMicrophone
        RuntimeLog.write(
            "permissions refresh accessibility=\(hasAccessibility) inputMonitoring=\(hasInputMonitoring) microphone=\(hasMicrophone)"
        )

        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        NotificationCenter.default.post(name: .shoutOutPermissionsChanged, object: self)
    }

    func requestAccessibility() {
        RuntimeLog.write("permissions request accessibility")
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        openPrivacyPane(.accessibility)
        beginPollingForPermissionChanges()
    }

    func requestMicrophone() async -> Bool {
        RuntimeLog.write("permissions request microphone")
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        hasMicrophone = granted
        RuntimeLog.write("permissions microphone result granted=\(granted)")
        if !granted {
            openPrivacyPane(.microphone)
        }
        beginPollingForPermissionChanges()
        return granted
    }

    func requestInputMonitoring() {
        RuntimeLog.write("permissions request inputMonitoring")
        hasInputMonitoring = CGRequestListenEventAccess()
        RuntimeLog.write("permissions inputMonitoring result granted=\(hasInputMonitoring)")
        if !hasInputMonitoring {
            openPrivacyPane(.inputMonitoring)
        }
        beginPollingForPermissionChanges()
    }

    func openFirstMissingPermissionPane() {
        if !hasAccessibility {
            requestAccessibility()
            return
        }

        if !hasInputMonitoring {
            requestInputMonitoring()
            return
        }

        if !hasMicrophone {
            Task {
                _ = await requestMicrophone()
            }
            return
        }

        refresh()
    }

    func beginPollingForPermissionChanges() {
        refreshPollTask?.cancel()
        refreshPollTask = Task { @MainActor in
            for _ in 0..<120 {
                if Task.isCancelled {
                    return
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
                refresh()

                if missingPermissionNames.isEmpty {
                    return
                }
            }
        }
    }

    private func openPrivacyPane(_ pane: PrivacyPane) {
        guard let url = URL(string: pane.settingsURLString) else { return }
        NSWorkspace.shared.open(url)
        RuntimeLog.write("permissions opened pane=\(pane.rawValue)")
    }
}

private struct PermissionSnapshot: Equatable {
    let hasAccessibility: Bool
    let hasInputMonitoring: Bool
    let hasMicrophone: Bool
}

private enum PrivacyPane: String {
    case accessibility
    case inputMonitoring
    case microphone

    var settingsURLString: String {
        switch self {
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .microphone:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        }
    }
}
