import AppKit
import AVFoundation
import CoreGraphics
@preconcurrency import Speech

extension Notification.Name {
    static let shoutOutPermissionsChanged = Notification.Name("ShoutOutPermissionsChanged")
}

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var hasAccessibility: Bool = false
    @Published var hasInputMonitoring: Bool = false
    @Published var hasMicrophone: Bool = false
    @Published var hasSpeechRecognition: Bool = false

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
        if speechRecognitionIsRequired && !hasSpeechRecognition {
            names.append("Speech Recognition")
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
            hasMicrophone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            hasSpeechRecognition: SpeechAuthorization.currentStatus() == .authorized
        )

        hasAccessibility = snapshot.hasAccessibility
        hasInputMonitoring = snapshot.hasInputMonitoring
        hasMicrophone = snapshot.hasMicrophone
        hasSpeechRecognition = snapshot.hasSpeechRecognition
        RuntimeLog.write(
            "permissions refresh accessibility=\(hasAccessibility) inputMonitoring=\(hasInputMonitoring) microphone=\(hasMicrophone) speechRecognition=\(hasSpeechRecognition)"
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

    func requestSpeechRecognition() async -> Bool {
        RuntimeLog.write("permissions request speechRecognition")
        let status = await SpeechAuthorization.requestStatus()
        let granted = status == .authorized
        hasSpeechRecognition = granted
        RuntimeLog.write(
            "permissions speechRecognition result granted=\(granted) status=\(status.permissionDescription)"
        )
        if !granted {
            openPrivacyPane(.speechRecognition)
        }
        beginPollingForPermissionChanges()
        return granted
    }

    func requestInputMonitoring() {
        RuntimeLog.write("permissions request inputMonitoring")
        hasInputMonitoring = CGRequestListenEventAccess()
        RuntimeLog.write("permissions inputMonitoring result granted=\(hasInputMonitoring)")
        beginPollingForPermissionChanges()
    }

    func openFirstMissingPermissionPane() {
        if !hasAccessibility {
            openAccessibilitySettings()
            return
        }

        if !hasInputMonitoring {
            openInputMonitoringSettings()
            return
        }

        if !hasMicrophone {
            openMicrophoneSettings()
            return
        }

        if speechRecognitionIsRequired && !hasSpeechRecognition {
            openSpeechRecognitionSettings()
            return
        }

        refresh()
    }

    func openAccessibilitySettings() {
        openPrivacyPane(.accessibility)
        beginPollingForPermissionChanges()
    }

    func openInputMonitoringSettings() {
        openPrivacyPane(.inputMonitoring)
        beginPollingForPermissionChanges()
    }

    func openMicrophoneSettings() {
        openPrivacyPane(.microphone)
        beginPollingForPermissionChanges()
    }

    func openSpeechRecognitionSettings() {
        openPrivacyPane(.speechRecognition)
        beginPollingForPermissionChanges()
    }

    private var speechRecognitionIsRequired: Bool {
        let backendRaw = UserDefaults.standard.string(forKey: Defaults.transcriptionBackend)
        let backend = TranscriptionBackend(rawValue: backendRaw ?? "") ?? .appleSpeech
        return backend.requiresSpeechRecognitionPermission
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
    let hasSpeechRecognition: Bool
}

private enum PrivacyPane: String {
    case accessibility
    case inputMonitoring
    case microphone
    case speechRecognition

    var settingsURLString: String {
        switch self {
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .microphone:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        }
    }
}

private extension SFSpeechRecognizerAuthorizationStatus {
    var permissionDescription: String {
        switch self {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }
}
