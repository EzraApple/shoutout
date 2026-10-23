@preconcurrency import AVFoundation
import AppKit
import CoreAudio
import Darwin
import Foundation

/// Thread-safe audio sample collector used by the real-time audio tap.
/// The tap callback writes samples from the audio thread; the main thread reads on stop.
private final class AudioSampleCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: ContiguousArray<Float> = []
    private var level: Float = 0

    var latestLevel: Float {
        lock.lock()
        defer { lock.unlock() }
        return level
    }

    func append(_ newSamples: [Float], level: Float) {
        lock.lock()
        samples.append(contentsOf: newSamples)
        self.level = level
        lock.unlock()
    }

    func read(from offset: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return Array(samples.dropFirst(offset))
    }

    func drain() -> [Float] {
        lock.lock()
        let result = Array(samples)
        samples.removeAll(keepingCapacity: true)
        level = 0
        lock.unlock()
        return result
    }

    func reset() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        level = 0
        lock.unlock()
    }
}

/// Serializes conversion with take boundaries. A callback already in progress
/// finishes before the converter and samples are reset for the next take.
final class AudioCaptureGate: @unchecked Sendable {
    private let lock = NSLock()
    private var accepting = false
    private var minimumHostTime: UInt64 = 0
    private let resetTake: () -> Void

    init(resetTake: @escaping () -> Void) {
        self.resetTake = resetTake
    }

    func beginTake(after hostTime: UInt64) {
        lock.lock()
        resetTake()
        minimumHostTime = hostTime
        accepting = true
        lock.unlock()
    }

    func endTake() {
        lock.lock()
        accepting = false
        lock.unlock()
    }

    func process(hostTime: UInt64?, _ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard accepting else { return }
        if let hostTime, hostTime < minimumHostTime { return }
        body()
    }
}

@MainActor
class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0

    static let sampleRate: Double = 16000

    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var captureGate: AudioCaptureGate?
    private var configurationObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var inputDeviceID: AudioDeviceID?
    private var graphGeneration = 0
    private var isInvalidatingGraph = false
    private var isAwaitingConfigurationChange = false
    private var pendingInputDeviceID: AudioDeviceID?
    private var recoveryWasRetargeted = false
    private var routeRecoveryTask: Task<Void, Never>?
    private let collector = AudioSampleCollector()
    private var levelPollTimer: Timer?
    private var takeNumber = 0
    private var publishedSamples = 0
    var onSamples: (([Float]) -> Void)?
    var onInterruption: ((String) -> Void)?

    private func observeHardwareChanges(generation: Int) {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil
        ) { [weak self] notification in
            guard let changedEngine = notification.object as? AVAudioEngine else { return }
            let changedEngineID = ObjectIdentifier(changedEngine)
            Task { @MainActor [weak self] in
                guard let self, self.graphGeneration == generation,
                    let engine = self.audioEngine,
                    ObjectIdentifier(engine) == changedEngineID else { return }
                if self.isAwaitingConfigurationChange {
                    if self.pendingInputDeviceID != Self.currentDefaultInputID() {
                        self.beginRouteRecovery(reason: "defaultInputChangedDuringRecovery")
                    } else if !self.recoveryWasRetargeted {
                        self.completeRouteRecovery(reason: "engineConfigurationChanged")
                    }
                } else {
                    self.invalidateGraph(reason: "engineConfigurationChanged")
                }
            }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, self.graphGeneration == generation else { return }
                self.invalidateGraph(reason: "systemSleep")
            }
        }

        var address = Self.defaultInputAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.graphGeneration == generation else { return }
                self.beginRouteRecovery(reason: "defaultInputChanged")
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
        )
        if status == noErr {
            defaultInputListener = listener
        } else {
            RuntimeLog.write("record default input listener failed status=\(status)")
        }
    }

    private static var defaultInputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func currentDefaultInputID() -> AudioDeviceID? {
        var address = defaultInputAddress
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    func startRecording() throws {
        guard !isRecording else { return }
        guard !isAwaitingConfigurationChange else {
            throw AudioRecorderError.inputDeviceChanging
        }

        if audioEngine != nil, inputDeviceID != Self.currentDefaultInputID() {
            beginRouteRecovery(reason: "defaultInputChangedBeforeStart")
            throw AudioRecorderError.inputDeviceChanging
        }
        let reused = audioEngine != nil
        if audioEngine == nil {
            try buildGraph()
        }
        if inputDeviceID != Self.currentDefaultInputID() {
            beginRouteRecovery(reason: "defaultInputChangedDuringStart")
            throw AudioRecorderError.inputDeviceChanging
        }
        guard let engine = audioEngine, let captureGate else {
            throw AudioRecorderError.converterError
        }

        captureGate.beginTake(after: mach_absolute_time())
        publishedSamples = 0
        do {
            try engine.start()
        } catch {
            captureGate.endTake()
            tearDownGraph()
            collector.reset()
            throw error
        }
        isRecording = true
        takeNumber += 1
        let currentTake = takeNumber
        RuntimeLog.write("record engine started reused=\(reused)")

        levelPollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isRecording, self.takeNumber == currentTake else { return }
                self.audioLevel = self.collector.latestLevel
                self.publishSamples()
            }
        }
    }

    private func buildGraph() throws {
        let deviceID = Self.currentDefaultInputID()
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        RuntimeLog.write("record input format=\(inputFormat)")

        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Self.sampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            throw AudioRecorderError.formatError
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.converterError
        }

        let collector = self.collector
        let gate = AudioCaptureGate {
            converter.reset()
            collector.reset()
        }

        Self.installAudioTap(
            on: inputNode,
            inputFormat: inputFormat,
            targetFormat: targetFormat,
            converter: converter,
            sampleRate: Self.sampleRate,
            collector: collector,
            gate: gate
        )

        engine.prepare()
        audioEngine = engine
        inputDeviceID = deviceID
        self.converter = converter
        captureGate = gate
        graphGeneration += 1
        observeHardwareChanges(generation: graphGeneration)
        RuntimeLog.write("record engine prepared")
    }

    func stopRecording() -> [Float] {
        guard isRecording else { return [] }

        levelPollTimer?.invalidate()
        levelPollTimer = nil
        takeNumber += 1

        // pause() stops hardware I/O but keeps the prepared graph and tap.
        if !isAwaitingConfigurationChange, audioEngine?.isRunning == true {
            audioEngine?.pause()
        }
        captureGate?.endTake()
        publishSamples()
        isRecording = false
        audioLevel = 0

        return collector.drain()
    }

    func startReplay() {
        precondition(!isRecording)
        tearDownGraph()
        collector.reset()
        publishedSamples = 0
        isRecording = true
    }

    func appendReplaySamples(_ samples: [Float]) {
        precondition(isRecording && audioEngine == nil)
        collector.append(samples, level: 0)
        publishSamples()
    }

    func tearDown() {
        if isRecording { _ = stopRecording() }
        tearDownGraph()
        onSamples = nil
    }

    private func invalidateGraph(reason: String) {
        guard audioEngine != nil, !isInvalidatingGraph else { return }
        isInvalidatingGraph = true
        defer { isInvalidatingGraph = false }
        RuntimeLog.write("record graph invalidated reason=\(reason) active=\(isRecording)")
        if isRecording {
            onInterruption?(reason)
            if isRecording { _ = stopRecording() }
        }
        tearDownGraph()
    }

    private func beginRouteRecovery(reason: String) {
        guard audioEngine != nil else { return }
        let requestedInputID = Self.currentDefaultInputID()
        if isAwaitingConfigurationChange {
            guard pendingInputDeviceID != requestedInputID else { return }
            pendingInputDeviceID = requestedInputID
            recoveryWasRetargeted = true
            RuntimeLog.write("record route recovery retarget reason=\(reason)")
            scheduleRouteRecoveryFallback()
            return
        }
        isAwaitingConfigurationChange = true
        pendingInputDeviceID = requestedInputID
        recoveryWasRetargeted = false
        captureGate?.endTake()
        RuntimeLog.write("record route recovery begin reason=\(reason) active=\(isRecording)")
        // A same-format input switch may not issue an engine configuration
        // notification, so stop hardware now while retaining the old graph.
        if audioEngine?.isRunning == true {
            audioEngine?.pause()
            RuntimeLog.write("record route recovery hardware paused")
        }
        if isRecording {
            onInterruption?(reason)
            if isRecording { _ = stopRecording() }
        }
        scheduleRouteRecoveryFallback()
    }

    private func scheduleRouteRecoveryFallback() {
        routeRecoveryTask?.cancel()
        let generation = graphGeneration
        let requestedInputID = pendingInputDeviceID
        routeRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self,
                self.graphGeneration == generation,
                self.isAwaitingConfigurationChange,
                self.pendingInputDeviceID == requestedInputID else { return }
            if Self.currentDefaultInputID() == requestedInputID {
                self.completeRouteRecovery(reason: "configurationTimeout")
            } else {
                self.beginRouteRecovery(reason: "defaultInputChangedDuringRecovery")
            }
        }
    }

    private func completeRouteRecovery(reason: String) {
        guard isAwaitingConfigurationChange else { return }
        RuntimeLog.write("record route recovery complete reason=\(reason)")
        tearDownGraph()
    }

    private func tearDownGraph() {
        routeRecoveryTask?.cancel()
        routeRecoveryTask = nil
        captureGate?.endTake()
        if let audioEngine {
            stopAudioEngine(audioEngine)
        }
        audioEngine = nil
        inputDeviceID = nil
        converter = nil
        captureGate = nil
        isAwaitingConfigurationChange = false
        pendingInputDeviceID = nil
        recoveryWasRetargeted = false
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let defaultInputListener {
            var address = Self.defaultInputAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main,
                defaultInputListener
            )
            self.defaultInputListener = nil
        }
    }

    private func publishSamples() {
        guard let onSamples else { return }
        let samples = collector.read(from: publishedSamples)
        guard !samples.isEmpty else { return }
        publishedSamples += samples.count
        onSamples(samples)
    }

    /// Minimum number of samples for a valid recording (0.2s at 16kHz).
    static let minimumSamples = 3200

    /// Installs the audio tap in a nonisolated context so the closure
    /// does not inherit @MainActor isolation (which would crash on the audio thread).
    nonisolated private static func installAudioTap(
        on inputNode: AVAudioInputNode,
        inputFormat: AVAudioFormat,
        targetFormat: AVAudioFormat,
        converter: AVAudioConverter,
        sampleRate: Double,
        collector: AudioSampleCollector,
        gate: AudioCaptureGate
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) {
            buffer, time in
            gate.process(hostTime: time.isHostTimeValid ? time.hostTime : nil) {
                let frameCount = AVAudioFrameCount(
                    ceil(Double(buffer.frameLength) * sampleRate / inputFormat.sampleRate)
                )
                guard frameCount > 0 else { return }

                guard
                    let convertedBuffer = AVAudioPCMBuffer(
                        pcmFormat: targetFormat, frameCapacity: frameCount)
                else { return }

                var error: NSError?
                let inputProvider = AudioConverterInputProvider(buffer: buffer)
                let status = converter.convert(to: convertedBuffer, error: &error) {
                    _, outStatus in
                    inputProvider.provideInput(outStatus: outStatus)
                }

                guard status != .error, error == nil,
                    let channelData = convertedBuffer.floatChannelData
                else { return }

                let samples = Array(
                    UnsafeBufferPointer(
                        start: channelData[0],
                        count: Int(convertedBuffer.frameLength)
                    ))

                let rms = samples.reduce(Float(0)) { $0 + $1 * $1 }
                let level = sqrt(rms / max(Float(samples.count), 1))

                collector.append(samples, level: min(level * 5, 1.0))
            }
        }
    }
}

private func stopAudioEngine(_ engine: AVAudioEngine) {
    // Keep the tap and its converter alive until hardware I/O has stopped.
    RuntimeLog.write("record engine stop begin running=\(engine.isRunning)")
    engine.stop()
    RuntimeLog.write("record engine stop complete")
    engine.inputNode.removeTap(onBus: 0)
    RuntimeLog.write("record tap removed")
}

enum AudioRecorderError: LocalizedError {
    case formatError
    case converterError
    case inputDeviceChanging

    var errorDescription: String? {
        switch self {
        case .formatError: return "Failed to create audio format"
        case .converterError: return "Failed to create audio converter"
        case .inputDeviceChanging: return "Input microphone is changing"
        }
    }
}
