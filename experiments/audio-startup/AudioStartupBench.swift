@preconcurrency import AVFoundation
import AppKit
import ApplicationServices
import CoreAudio
import Darwin
import Foundation

// A command-line hardware experiment. Samples are counted and discarded, never saved.
// Conversion and tap configuration mirror AudioRecorder.swift at f54f08958b03.
enum RuntimeLog {
    static func write(_ message: String) {}
}

// Use Core Audio's host clock for both request times and AVAudioTime timestamps.
func clockNanoseconds() -> UInt64 {
    UInt64(AVAudioTime.seconds(forHostTime: mach_absolute_time()) * 1_000_000_000)
}
func milliseconds(_ start: UInt64, _ end: UInt64) -> Double {
    Double(end - start) / 1_000_000
}

func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}

func defaultInputDevice() -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
    return device
}

func deviceRunning(_ device: AudioDeviceID) -> Int {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var running: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running)
    return status == noErr ? Int(running) : -1
}

func deviceName(_ device: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
    return name?.takeUnretainedValue() as String? ?? "Unknown"
}

enum BenchTrace {
    static var phases: [String: Double] = [:]
    static var probe: SampleProbe?

    static func measure<T>(_ name: String, _ work: () throws -> T) rethrows -> T {
        let start = clockNanoseconds()
        defer { phases[name] = milliseconds(start, clockNanoseconds()) }
        return try work()
    }
}

final class SampleProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var firstRaw: UInt64?
    private var firstConverted: UInt64?
    private var firstSampleHostSeconds: Double?
    private var bufferFrames = 0
    private var callbacks = 0
    private var convertedFrames = 0
    private var conversionErrors = 0

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        firstRaw = nil
        firstConverted = nil
        firstSampleHostSeconds = nil
        bufferFrames = 0
        callbacks = 0
        convertedFrames = 0
        conversionErrors = 0
    }

    func observeRaw(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        let at = clockNanoseconds()
        lock.lock()
        defer { lock.unlock() }
        if firstRaw == nil {
            firstRaw = at
            bufferFrames = Int(buffer.frameLength)
            if time.isHostTimeValid {
                firstSampleHostSeconds = AVAudioTime.seconds(forHostTime: time.hostTime)
            }
        }
        callbacks += 1
    }

    func observeConverted(_ frames: Int) {
        let at = clockNanoseconds()
        lock.lock()
        defer { lock.unlock() }
        if firstConverted == nil { firstConverted = at }
        convertedFrames += frames
    }

    func observeError() {
        lock.lock()
        conversionErrors += 1
        lock.unlock()
    }

    func snapshot(since start: UInt64) -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        var result: [String: Any] = [
            "callbacks": callbacks, "convertedFrames": convertedFrames,
            "firstBufferFrames": bufferFrames, "conversionErrors": conversionErrors,
        ]
        if let firstRaw { result["requestToFirstRawBufferMs"] = milliseconds(start, firstRaw) }
        if let firstConverted { result["requestToFirstConvertedBufferMs"] = milliseconds(start, firstConverted) }
        if let firstSampleHostSeconds {
            result["requestToFirstSampleTimestampMs"] =
                (firstSampleHostSeconds - Double(start) / 1_000_000_000) * 1000
        }
        return result
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return callbacks
    }
}

enum Variant: String, CaseIterable {
    case productionReference
    case fresh
    case retainedStopped
    case retainedPaused
    case preparedBeforePress
    case freshSmallTap
}

// These minimal types let the experiment compile the real scheduling queue without
// loading a model. Only its synchronous session-admission cost is measured.
struct EngineTranscriptionResult {
    var fallbackCount: Int?
}

@MainActor protocol StreamingTranscriptionEngine {
    func startStreaming(id: UUID) async throws
    func feedStreaming(id: UUID, samples: [Float]) async throws
    func finishStreaming(id: UUID, audioSamples: [Float]) async throws -> EngineTranscriptionResult
    func cancelStreaming(id: UUID) async
    func transcribe(audioSamples: [Float]) async throws -> EngineTranscriptionResult
}

@MainActor final class SchedulingOnlyEngine: StreamingTranscriptionEngine {
    func startStreaming(id: UUID) async throws {}
    func feedStreaming(id: UUID, samples: [Float]) async throws {}
    func finishStreaming(id: UUID, audioSamples: [Float]) async throws -> EngineTranscriptionResult {
        EngineTranscriptionResult()
    }
    func cancelStreaming(id: UUID) async {}
    func transcribe(audioSamples: [Float]) async throws -> EngineTranscriptionResult {
        EngineTranscriptionResult()
    }
}

final class CaptureGraph {
    let engine: AVAudioEngine
    let input: AVAudioInputNode
    let format: AVAudioFormat
    let converter: AVAudioConverter
    let probe = SampleProbe()
    var phases: [String: Double] = [:]

    init(bufferSize: AVAudioFrameCount) throws {
        var at = clockNanoseconds()
        engine = AVAudioEngine()
        phases["engineCreateMs"] = milliseconds(at, clockNanoseconds())
        at = clockNanoseconds()
        input = engine.inputNode
        phases["inputNodeMs"] = milliseconds(at, clockNanoseconds())
        at = clockNanoseconds()
        format = input.outputFormat(forBus: 0)
        phases["inputFormatMs"] = milliseconds(at, clockNanoseconds())
        at = clockNanoseconds()
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                   channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: format, to: target) else {
            throw NSError(domain: "AudioStartupBench", code: 1)
        }
        self.converter = converter
        phases["converterCreateMs"] = milliseconds(at, clockNanoseconds())
        at = clockNanoseconds()
        let probe = self.probe
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, time in
            probe.observeRaw(buffer, time: time)
            let frameCount = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate))
            guard frameCount > 0,
                let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: frameCount)
            else { probe.observeError(); return }
            var error: NSError?
            let provider = AudioConverterInputProvider(buffer: buffer)
            let status = converter.convert(to: converted, error: &error) { _, outStatus in
                provider.provideInput(outStatus: outStatus)
            }
            guard status != .error, error == nil, let data = converted.floatChannelData else {
                probe.observeError(); return
            }
            let samples = Array(UnsafeBufferPointer(start: data[0], count: Int(converted.frameLength)))
            // Match the production RMS work; do not retain the samples.
            _ = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / max(Float(samples.count), 1))
            probe.observeConverted(samples.count)
        }
        phases["tapInstallMs"] = milliseconds(at, clockNanoseconds())
    }

    func prepare() -> Double {
        let at = clockNanoseconds()
        engine.prepare()
        return milliseconds(at, clockNanoseconds())
    }

    func teardown() {
        engine.stop()
        input.removeTap(onBus: 0)
    }
}

@main
struct AudioStartupBench {
    @MainActor static func main() async {
        if ProcessInfo.processInfo.environment["BENCH_SESSION_ONLY"] == "1" {
            let queue = RecordingTranscriptionQueue()
            let engine = SchedulingOnlyEngine()
            for round in 0..<100 {
                let at = clockNanoseconds()
                let recording = queue.begin(engine: engine)
                let elapsed = milliseconds(at, clockNanoseconds())
                emit(["type": "sessionScheduling", "round": round, "milliseconds": elapsed])
                queue.cancel(recording)
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            emit(["type": "error", "message": "Microphone permission is not already granted to the command host."])
            return
        }
        let rounds = Int(ProcessInfo.processInfo.environment["BENCH_ROUNDS"] ?? "8") ?? 8
        let idleMs = UInt64(ProcessInfo.processInfo.environment["BENCH_IDLE_MS"] ?? "1000") ?? 1000
        let device = defaultInputDevice()
        emit(["type": "metadata", "device": deviceName(device), "deviceID": device,
              "initialDeviceRunning": deviceRunning(device), "accessibilityTrusted": AXIsProcessTrusted(),
              "rounds": rounds, "idleMs": idleMs, "sourceCommit": "f54f08958b03",
              "os": ProcessInfo.processInfo.operatingSystemVersionString])
        guard deviceRunning(device) == 0 else {
            emit(["type": "error", "message": "Input device is already running; close other microphone consumers first."])
            return
        }
        var retained: [Variant: CaptureGraph] = [:]
        let requested = ProcessInfo.processInfo.environment["BENCH_VARIANTS"]?
            .split(separator: ",").compactMap { Variant(rawValue: String($0)) }
        let included = requested ?? Variant.allCases
        for round in 0..<rounds {
            // Rotate order to avoid assigning all first-run or device-warm effects to one variant.
            let variants = Array(included.dropFirst(round % included.count))
                + Array(included.prefix(round % included.count))
            for variant in variants {
                do {
                    if variant == .productionReference {
                        try await measureProductionReference(round: round, idleMs: idleMs, device: device)
                        continue
                    }
                    var outsidePressMs = 0.0
                    var graph: CaptureGraph?
                    if variant == .preparedBeforePress {
                        let before = clockNanoseconds()
                        graph = try CaptureGraph(bufferSize: 1024)
                        _ = graph!.prepare()
                        outsidePressMs = milliseconds(before, clockNanoseconds())
                    } else {
                        graph = retained[variant]
                    }
                    let idleCallbacksBefore = graph?.probe.count ?? 0
                    try await Task.sleep(nanoseconds: idleMs * 1_000_000)
                    let idleCallbacks = (graph?.probe.count ?? 0) - idleCallbacksBefore
                    let runningBefore = deviceRunning(device)
                    let defaultDeviceBefore = defaultInputDevice()
                    let start = clockNanoseconds()
                    var phases: [String: Double] = [:]
                    let focusAt = clockNanoseconds()
                    let target = TextInserter.captureFocusedTarget()
                    phases["targetCaptureMs"] = milliseconds(focusAt, clockNanoseconds())
                    let isNew = graph == nil
                    if graph == nil {
                        graph = try CaptureGraph(bufferSize: variant == .freshSmallTap ? 256 : 1024)
                        phases.merge(graph!.phases) { _, rhs in rhs }
                    }
                    let active = graph!
                    active.probe.reset()
                    let resetAt = clockNanoseconds()
                    if !isNew { active.converter.reset() }
                    phases["converterResetMs"] = milliseconds(resetAt, clockNanoseconds())
                    if variant != .preparedBeforePress && (variant != .retainedPaused || isNew) {
                        phases["prepareMs"] = active.prepare()
                    }
                    let engineStart = clockNanoseconds()
                    try active.engine.start()
                    phases["engineStartMs"] = milliseconds(engineStart, clockNanoseconds())
                    phases["requestToEngineReadyMs"] = milliseconds(start, clockNanoseconds())
                    let runningDuring = deviceRunning(device)
                    // Wait for actual data, with a bound for faulty streams.
                    let deadline = clockNanoseconds() + 2_000_000_000
                    while active.probe.count < 3 && clockNanoseconds() < deadline {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                    var result = active.probe.snapshot(since: start)
                    let stopAt = clockNanoseconds()
                    if variant == .retainedPaused {
                        active.engine.pause()
                    } else {
                        active.engine.stop()
                    }
                    phases["stopOrPauseMs"] = milliseconds(stopAt, clockNanoseconds())
                    let countAfterStop = active.probe.count
                    try await Task.sleep(nanoseconds: 150_000_000)
                    result.merge([
                        "type": "take", "variant": variant.rawValue, "round": round,
                        "firstGraphUse": isNew, "phases": phases, "outsidePressSetupMs": outsidePressMs,
                        "sampleRate": active.format.sampleRate, "inputChannels": active.format.channelCount,
                        "idleDeviceRunningBefore": runningBefore, "deviceRunningDuring": runningDuring,
                        "idleDeviceRunningAfter": deviceRunning(device), "idleCallbacksBefore": idleCallbacks,
                        "defaultDeviceBefore": defaultDeviceBefore, "defaultDeviceAfter": defaultInputDevice(),
                        "callbacksAfterStop": active.probe.count - countAfterStop,
                        "engineRunningAfter": active.engine.isRunning,
                        "targetCaptured": target != nil,
                        "targetBundleID": target?.bundleIdentifier ?? "none",
                    ]) { _, rhs in rhs }
                    emit(result)
                    if variant == .retainedStopped || variant == .retainedPaused {
                        retained[variant] = active
                    } else {
                        active.teardown()
                    }
                } catch {
                    emit(["type": "error", "variant": variant.rawValue, "round": round,
                          "message": String(describing: error)])
                    for graph in retained.values { graph.teardown() }
                    return
                }
            }
        }
        for graph in retained.values { graph.teardown() }
        try? await Task.sleep(nanoseconds: 300_000_000)
        emit(["type": "complete", "finalDeviceRunning": deviceRunning(device)])
    }

    @MainActor static func measureProductionReference(round: Int, idleMs: UInt64, device: AudioDeviceID) async throws {
        let recorder = AudioRecorder()
        let probe = SampleProbe()
        BenchTrace.probe = probe
        BenchTrace.phases = [:]
        try await Task.sleep(nanoseconds: idleMs * 1_000_000)
        let runningBefore = deviceRunning(device)
        let defaultDeviceBefore = defaultInputDevice()
        let start = clockNanoseconds()
        let target = BenchTrace.measure("targetCaptureMs") { TextInserter.captureFocusedTarget() }
        try recorder.startRecording()
        BenchTrace.phases["requestToEngineReadyMs"] = milliseconds(start, clockNanoseconds())
        let runningDuring = deviceRunning(device)
        let deadline = clockNanoseconds() + 2_000_000_000
        while probe.count < 3 && clockNanoseconds() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        var result = probe.snapshot(since: start)
        let stopAt = clockNanoseconds()
        let samples = recorder.stopRecording()
        BenchTrace.phases["stopOrPauseMs"] = milliseconds(stopAt, clockNanoseconds())
        let countAfterStop = probe.count
        try await Task.sleep(nanoseconds: 150_000_000)
        result.merge([
            "type": "take", "variant": Variant.productionReference.rawValue, "round": round,
            "firstGraphUse": true, "phases": BenchTrace.phases,
            "idleDeviceRunningBefore": runningBefore, "deviceRunningDuring": runningDuring,
            "idleDeviceRunningAfter": deviceRunning(device), "idleCallbacksBefore": 0,
            "defaultDeviceBefore": defaultDeviceBefore, "defaultDeviceAfter": defaultInputDevice(),
            "callbacksAfterStop": probe.count - countAfterStop, "drainedSamples": samples.count,
            "targetCaptured": target != nil, "targetBundleID": target?.bundleIdentifier ?? "none",
        ]) { _, rhs in rhs }
        emit(result)
        BenchTrace.probe = nil
    }
}
