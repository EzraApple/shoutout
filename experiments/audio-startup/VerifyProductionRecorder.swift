@preconcurrency import AVFoundation
import AppKit
import CoreAudio
import Foundation

final class RecorderEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }
    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

enum RuntimeLog {
    static let events = RecorderEvents()
    static func write(_ message: String) { events.append(message) }
}

func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data([10]))
}

func defaultInput() -> AudioDeviceID {
    var address = inputAddress()
    var device: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    precondition(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                          0, nil, &size, &device) == noErr)
    return device
}

func inputAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}

func setDefaultInput(_ device: AudioDeviceID) throws {
    var address = inputAddress()
    var device = device
    let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                           0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device)
    guard status == noErr else { throw NSError(domain: "InputSwitch", code: Int(status)) }
}

func running(_ device: AudioDeviceID) -> Int {
    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                            mScope: kAudioObjectPropertyScopeGlobal,
                                            mElement: kAudioObjectPropertyElementMain)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
    return status == noErr ? Int(value) : -1
}

func namedDevices() -> [(AudioDeviceID, String)] {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                            mScope: kAudioObjectPropertyScopeGlobal,
                                            mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
    var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)
    return devices.map { device in
        var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        _ = AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name)
        return (device, name?.takeUnretainedValue() as String? ?? "unknown")
    }
}

@MainActor func pump(_ seconds: TimeInterval) {
    let until = Date().addingTimeInterval(seconds)
    while Date() < until {
        RunLoop.main.run(mode: .default, before: min(until, Date().addingTimeInterval(0.02)))
    }
}

func require(_ condition: Bool, _ message: String = "Verification failed") throws {
    guard condition else { throw NSError(domain: "RecorderVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@MainActor final class Verification {
    let recorder = AudioRecorder()
    var interruptions: [String] = []
    var deliveredSamples = 0
    var firstDelivery: UInt64?

    func startWhenReady() throws -> Int {
        var retries = 0
        let deadline = Date().addingTimeInterval(3)
        while true {
            do {
                try recorder.startRecording()
                return retries
            } catch {
#if !COLD_RECORDER_BASELINE
                guard case AudioRecorderError.inputDeviceChanging = error, Date() < deadline else { throw error }
                retries += 1
                pump(0.05)
#else
                throw error
#endif
            }
        }
    }

    init() {
        recorder.onSamples = { [weak self] samples in
            guard let self else { return }
            if firstDelivery == nil { firstDelivery = DispatchTime.now().uptimeNanoseconds }
            deliveredSamples += samples.count
        }
        recorder.onInterruption = { [weak self] reason in self?.interruptions.append(reason) }
    }

    func take(_ label: String, hold: TimeInterval = 0.55) throws {
        deliveredSamples = 0
        firstDelivery = nil
        let before = DispatchTime.now().uptimeNanoseconds
        let recoveryRetries = try startWhenReady()
        let readyMs = Double(DispatchTime.now().uptimeNanoseconds - before) / 1_000_000
        let device = defaultInput()
        let active = running(device)
        pump(hold)
        let samples = recorder.stopRecording()
        let delivered = deliveredSamples
        pump(0.35)
        let idle = running(device)
        try require(active == 1 && idle == 0 && !recorder.isRecording, "hardware must stop between takes")
        try require(samples.count >= AudioRecorder.minimumSamples && delivered == samples.count,
                     "samples must stream exactly once and drain completely")
        try require(deliveredSamples == delivered, "no samples may stream while idle")
        emit(["type": "take", "label": label, "device": device, "readyMs": readyMs,
              "firstDeliveryMs": firstDelivery.map { Double($0 - before) / 1_000_000 } ?? -1,
              "samples": samples.count, "streamedSamples": delivered,
              "recoveryRetries": recoveryRetries,
              "activeDeviceRunning": active, "idleDeviceRunning": idle])
    }

    func activeInputChange(to device: AudioDeviceID) throws {
        let count = interruptions.count
        _ = try startWhenReady()
        pump(0.35)
        let previousDevice = defaultInput()
        try setDefaultInput(device)
        var timeline: [[String: Any]] = []
        for (delta, elapsed) in [(0.05, 0.05), (0.15, 0.2), (0.3, 0.5), (0.5, 1.0)] {
            pump(delta)
            timeline.append(["elapsedSeconds": elapsed, "recorderActive": recorder.isRecording,
                             "previousDeviceRunning": running(previousDevice), "newDeviceRunning": running(device)])
        }
        emit(["type": "routeTransitionTimeline", "samples": timeline])
        if ProcessInfo.processInfo.environment["VERIFY_COLD_BASELINE"] == "1" {
            // f54 did not observe route changes. Stop after the same settle
            // window, then test its unchanged cold construction on the new input.
            _ = recorder.stopRecording()
            emit(["type": "baselineStopAfterRouteChange", "passed": true])
            return
        }
        try require(!recorder.isRecording && interruptions.count == count + 1,
                     "an active microphone change must interrupt exactly once")
        try require(running(device) == 0)
        emit(["type": "activeInputChange", "interruption": interruptions.last!, "passed": true])
    }

    func rapidInputChanges(original: AudioDeviceID, alternate: AudioDeviceID) throws {
        for cycle in 0..<4 {
            let count = interruptions.count
            _ = try startWhenReady()
            pump(0.3)
            try setDefaultInput(alternate)
            pump(0.05)
            try setDefaultInput(original)
            pump(0.05)
            try require(!recorder.isRecording && interruptions.count == count + 1,
                        "Rapid changes must interrupt the active take exactly once")
            try take("after-rapid-switch-\(cycle)")
        }
    }

    func simulateSleep(active: Bool) throws {
        let count = interruptions.count
        if active { _ = try startWhenReady(); pump(0.3) }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        pump(0.2)
        try require(!recorder.isRecording && running(defaultInput()) == 0)
        try require(interruptions.count == count + (active ? 1 : 0))
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        pump(0.1)
        emit(["type": "simulatedSleepWake", "wasRecording": active, "passed": true])
    }

    func checkPrivacyIndicator(directory: String) throws {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func capture(_ name: String) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // Main display is 1728x1117 points (3456x2234 pixels). Capture the
            // menu-bar strip only, so no app or document content is retained.
            process.arguments = ["-x", "-R", "0,0,1728,45", root.appendingPathComponent(name + ".png").path]
            try process.run()
            process.waitUntilExit()
            try require(process.terminationStatus == 0, "Screenshot command failed")
            emit(["type": "privacyScreenshot", "name": name,
                  "recorderActive": recorder.isRecording, "deviceRunning": running(defaultInput())])
        }
        try capture("before")
        _ = try startWhenReady()
        pump(2)
        try capture("recording")
        _ = recorder.stopRecording()
        pump(1)
        try capture("paused-1s")
        pump(5)
        try capture("paused-6s")
        pump(10)
        try capture("paused-16s")
        try require(running(defaultInput()) == 0 && !recorder.isRecording)
        _ = try startWhenReady()
        pump(2)
        try capture("recording-reused")
        _ = recorder.stopRecording()
        pump(16)
        try capture("paused-reused-16s")
        try require(running(defaultInput()) == 0 && !recorder.isRecording)
    }
}

@main struct VerifyProductionRecorder {
    @MainActor static func main() {
        let original = defaultInput()
        let devices = namedDevices()
        emit(["type": "metadata", "originalInput": original,
              "devices": devices.map { ["id": $0.0, "name": $0.1] as [String: Any] }])
        let alternateName = ProcessInfo.processInfo.environment["VERIFY_ALTERNATE_NAME"] ?? "BlackHole 2ch"
        let originalName = devices.first(where: { $0.0 == original })?.1 ?? ""
        guard originalName != "Apple Device Microphone",
              !originalName.localizedCaseInsensitiveContains("iPhone") else {
            emit(["type": "blocked", "reason": "The current input is a Continuity/iPhone microphone. Select the Mac microphone before testing."])
            return
        }
        guard alternateName == "BlackHole 2ch" || alternateName == "Steam Streaming Microphone" else {
            emit(["type": "blocked", "reason": "Route tests accept only the local virtual microphones; never use Continuity/iPhone input."])
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              running(original) == 0,
              let alternate = devices.first(where: { $0.1 == alternateName })?.0 else {
            emit(["type": "blocked", "reason": "Need existing mic permission, idle default input, and the requested alternate."])
            return
        }
        let verification = Verification()
        defer {
            verification.recorder.tearDown()
            if defaultInput() != original { try? setDefaultInput(original) }
            pump(0.5)
            emit(["type": "final", "inputRestored": defaultInput() == original,
                  "idleDeviceRunning": running(original), "events": RuntimeLog.events.snapshot()])
        }
        do {
            if let directory = ProcessInfo.processInfo.environment["PRIVACY_SCREENSHOT_DIRECTORY"] {
                try verification.checkPrivacyIndicator(directory: directory)
                emit(["type": "complete", "passed": true])
                return
            }
            if ProcessInfo.processInfo.environment["VERIFY_ROUTE_STRESS"] == "1" {
                try verification.take("stress-cold")
                for cycle in 0..<12 {
                    let next = defaultInput() == original ? alternate : original
                    try verification.activeInputChange(to: next)
                    try verification.take("stress-after-active-change-\(cycle)")
                }
                emit(["type": "complete", "passed": true])
                return
            }
            if ProcessInfo.processInfo.environment["VERIFY_RAPID_SWITCH"] == "1" {
                try verification.rapidInputChanges(original: original, alternate: alternate)
                emit(["type": "complete", "passed": true])
                return
            }
            try verification.take("cold")
            for i in 1...5 { try verification.take("reused-\(i)") }
            try setDefaultInput(alternate)
            pump(1)
            try verification.take("alternate-after-idle-change")
            try setDefaultInput(original)
            pump(1)
            try verification.take("original-after-idle-change")
            try verification.activeInputChange(to: alternate)
            try verification.take("alternate-after-active-change")
            try setDefaultInput(original)
            pump(1)
            try verification.take("original-after-active-change")
            try verification.simulateSleep(active: false)
            try verification.take("after-idle-sleep-notification")
            try verification.simulateSleep(active: true)
            try verification.take("after-active-sleep-notification")
            verification.recorder.startReplay()
            verification.recorder.appendReplaySamples([1, 2, 3])
            try require(verification.recorder.stopRecording() == [1, 2, 3])
            try require(running(original) == 0)
            emit(["type": "replayAfterHardware", "passed": true])
            try verification.take("after-replay")
            emit(["type": "complete", "passed": true])
        } catch {
            emit(["type": "error", "message": String(describing: error)])
        }
    }
}
