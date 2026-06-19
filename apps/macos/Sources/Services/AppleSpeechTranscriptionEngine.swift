@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

@MainActor
final class AppleSpeechTranscriptionEngine: TranscriptionEngine {
    let backend: TranscriptionBackend = .appleSpeech

    private var recognizer: SFSpeechRecognizer?

    var modelIdentifier: String {
        let localeIdentifier = recognizer?.locale.identifier ?? Locale.current.identifier
        return "apple-speech-\(localeIdentifier)"
    }

    func load(updateState: @escaping @MainActor (ModelState) -> Void) async throws {
        RuntimeLog.write("model load start backend=\(backend.rawValue)")
        updateState(.loading)
        try await Self.requestSpeechAuthorization()
        recognizer = try Self.makeRecognizer()
        updateState(.ready)
        RuntimeLog.write("model ready backend=\(backend.rawValue) selected=\(modelIdentifier)")
    }

    func transcribe(audioSamples: [Float]) async throws -> EngineTranscriptionResult {
        if recognizer == nil {
            recognizer = try Self.makeRecognizer()
        }
        try await Self.requestSpeechAuthorization()

        guard let recognizer else {
            throw TranscriptionError.modelNotReady
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.taskHint = .dictation
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }

        let nativeBuffer = try Self.makeNativeBuffer(
            from: audioSamples,
            targetFormat: request.nativeAudioFormat
        )
        let output = try await Self.recognize(
            recognizer: recognizer,
            request: request,
            buffer: nativeBuffer,
            audioDuration: Double(audioSamples.count) / AudioRecorder.sampleRate
        )

        return EngineTranscriptionResult(
            rawText: output.text,
            firstTokenMs: output.firstPartialMs,
            pipelineMs: nil,
            realTimeFactor: nil,
            speedFactor: nil,
            tokensPerSecond: nil,
            fallbackCount: nil
        )
    }

    func unload() {
        recognizer = nil
    }

    private static func makeRecognizer() throws -> SFSpeechRecognizer {
        if let recognizer = SFSpeechRecognizer(locale: Locale.current) {
            return recognizer
        }

        if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) {
            return recognizer
        }

        throw TranscriptionError.engineUnavailable("Apple Speech is not available for this locale.")
    }

    static func requestSpeechAuthorization() async throws {
        let currentStatus = SpeechAuthorization.currentStatus()
        if currentStatus == .authorized {
            return
        }

        let status = await SpeechAuthorization.requestStatus()

        guard status == .authorized else {
            throw TranscriptionError.speechRecognitionNotAuthorized(status.description)
        }
    }

    private static func makeNativeBuffer(
        from audioSamples: [Float],
        targetFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        guard !audioSamples.isEmpty else {
            throw TranscriptionError.audioConversionFailed("No audio samples to convert.")
        }

        guard
            let sourceFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: AudioRecorder.sampleRate,
                channels: 1,
                interleaved: false
            ),
            let sourceBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: AVAudioFrameCount(audioSamples.count)
            ),
            let sourceChannel = sourceBuffer.floatChannelData?[0]
        else {
            throw TranscriptionError.audioConversionFailed("Could not create source audio buffer.")
        }

        sourceBuffer.frameLength = AVAudioFrameCount(audioSamples.count)
        audioSamples.withUnsafeBufferPointer { samples in
            if let baseAddress = samples.baseAddress {
                sourceChannel.update(from: baseAddress, count: samples.count)
            }
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw TranscriptionError.audioConversionFailed("Could not create native audio converter.")
        }

        let targetFrames = AVAudioFrameCount(
            ceil(Double(audioSamples.count) * targetFormat.sampleRate / sourceFormat.sampleRate)
        ) + 1024
        guard let targetBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: max(targetFrames, 1)
        ) else {
            throw TranscriptionError.audioConversionFailed("Could not create native audio buffer.")
        }

        var conversionError: NSError?
        let inputProvider = AudioConverterInputProvider(buffer: sourceBuffer)
        let status = converter.convert(to: targetBuffer, error: &conversionError) {
            _, outStatus in
            inputProvider.provideInput(outStatus: outStatus)
        }

        guard status != .error, conversionError == nil, targetBuffer.frameLength > 0 else {
            let message = conversionError?.localizedDescription ?? "Native audio conversion failed."
            throw TranscriptionError.audioConversionFailed(message)
        }

        return targetBuffer
    }

    private static func recognize(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        buffer: AVAudioPCMBuffer,
        audioDuration: TimeInterval
    ) async throws -> AppleSpeechRecognitionOutput {
        try await withCheckedThrowingContinuation { continuation in
            let completion = AppleSpeechRecognitionCompletion(continuation: continuation)
            completion.task = recognizer.recognitionTask(with: request) { result, error in
                completion.handle(result: result, error: error)
            }
            completion.startTimeout(after: recognitionTimeout(forAudioDuration: audioDuration))
            request.append(buffer)
            request.endAudio()
        }
    }

    private static func recognitionTimeout(forAudioDuration duration: TimeInterval) -> TimeInterval {
        min(max(4.0, duration * 0.75), 12.0)
    }
}

private struct AppleSpeechRecognitionOutput: Sendable {
    var text: String
    var firstPartialMs: Int?
}

private final class AppleSpeechRecognitionCompletion: @unchecked Sendable {
    private let continuation: CheckedContinuation<AppleSpeechRecognitionOutput, Error>
    private let startedAt = Date()
    private let lock = NSLock()
    private var didFinish = false
    private var latestText = ""
    private var firstPartialMs: Int?
    private var timeoutTask: Task<Void, Never>?

    var task: SFSpeechRecognitionTask?

    init(continuation: CheckedContinuation<AppleSpeechRecognitionOutput, Error>) {
        self.continuation = continuation
    }

    func startTimeout(after timeout: TimeInterval) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            let nanoseconds = UInt64(timeout * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.finishWithLatestTextOrTimeout()
        }
    }

    func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                lock.lock()
                latestText = text
                if firstPartialMs == nil {
                    firstPartialMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                }
                let firstPartialMs = firstPartialMs
                let output = AppleSpeechRecognitionOutput(
                    text: latestText,
                    firstPartialMs: firstPartialMs
                )
                lock.unlock()

                RuntimeLog.write(
                    "appleSpeech result final=\(result.isFinal) textLength=\(text.count) firstPartialMs=\(firstPartialMs ?? -1)"
                )
                if result.isFinal {
                    finish(.success(output))
                }
            }
        }

        if let error {
            lock.lock()
            let fallbackOutput = latestText.isEmpty
                ? nil
                : AppleSpeechRecognitionOutput(text: latestText, firstPartialMs: firstPartialMs)
            lock.unlock()

            if let fallbackOutput {
                finish(.success(fallbackOutput))
            } else {
                finish(.failure(error))
            }
        }
    }

    private func finishWithLatestTextOrTimeout() {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        let fallbackOutput = latestText.isEmpty
            ? nil
            : AppleSpeechRecognitionOutput(text: latestText, firstPartialMs: firstPartialMs)
        let textLength = latestText.count
        lock.unlock()

        RuntimeLog.write("appleSpeech timeout textLength=\(textLength)")
        if let fallbackOutput {
            finish(.success(fallbackOutput))
        } else {
            finish(.failure(TranscriptionError.engineUnavailable("Apple Speech timed out.")))
        }
    }

    private func finish(_ result: Result<AppleSpeechRecognitionOutput, Error>) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()

        timeoutTask?.cancel()
        timeoutTask = nil
        task?.finish()
        let continuation = continuation
        switch result {
        case .success(let output):
            Task { @MainActor in
                continuation.resume(returning: output)
            }
        case .failure(let error):
            Task { @MainActor in
                continuation.resume(throwing: error)
            }
        }
    }
}

private extension SFSpeechRecognizerAuthorizationStatus {
    var description: String {
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
