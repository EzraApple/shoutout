import AppKit
import AVFoundation
import CoreGraphics

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var hasAccessibility: Bool = false
    @Published var hasInputMonitoring: Bool = false
    @Published var hasMicrophone: Bool = false

    private init() {
        refresh()
    }

    func refresh() {
        hasAccessibility = AXIsProcessTrusted()
        hasInputMonitoring = CGPreflightListenEventAccess()
        hasMicrophone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        RuntimeLog.write(
            "permissions refresh accessibility=\(hasAccessibility) inputMonitoring=\(hasInputMonitoring) microphone=\(hasMicrophone)"
        )
    }

    nonisolated func requestAccessibility() {
        RuntimeLog.write("permissions request accessibility")
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // User must grant in System Settings; we re-check on app activation
    }

    func requestMicrophone() async -> Bool {
        RuntimeLog.write("permissions request microphone")
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        hasMicrophone = granted
        RuntimeLog.write("permissions microphone result granted=\(granted)")
        return granted
    }

    func requestInputMonitoring() {
        RuntimeLog.write("permissions request inputMonitoring")
        hasInputMonitoring = CGRequestListenEventAccess()
        RuntimeLog.write("permissions inputMonitoring result granted=\(hasInputMonitoring)")
    }
}
