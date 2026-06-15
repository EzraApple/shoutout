#if swift(>=6.2)
import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import Speech

@available(macOS 26.0, *)
@MainActor
final class AppleDictationTranscriptionEngine: TranscriptionEngine {
    let backend: TranscriptionBackend = .appleDictation

    private var selectedLocale: Locale?

    var modelIdentifier: String {
        if let selectedLocale {
            return "apple-dictation-\(selectedLocale.identifier)"
        }
        return "apple-dictation"
    }

    func load(updateState: @escaping @MainActor (ModelState) -> Void) async throws {
        RuntimeLog.write("model load start backend=\(backend.rawValue)")
        updateState(.loading)
        try await AppleSpeechTranscriptionEngine.requestSpeechAuthorization()

        let locale = try await Self.supportedLocale()
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        try await Self.prepareAssets(for: transcriber, updateState: updateState)

        selectedLocale = locale
        updateState(.ready)
        RuntimeLog.write("model ready backend=\(backend.rawValue) selected=\(modelIdentifier)")
    }

    func transcribe(audioSamples: [Float]) async throws -> EngineTranscriptionResult {
        if selectedLocale == nil {
            try await load { _ in }
        }
        try await AppleSpeechTranscriptionEngine.requestSpeechAuthorization()

        let audioDuration = Double(audioSamples.count) / AudioRecorder.sampleRate
        let locale: Locale
        if let selectedLocale {
            locale = selectedLocale
        } else {
            locale = try await Self.supportedLocale()
            selectedLocale = locale
        }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        try await Self.prepareAssets(for: transcriber) { _ in }

        let sourceFormat = try Self.makeSourceFormat()
        let sourceBuffer = try Self.makeBuffer(from: audioSamples, format: sourceFormat)
        let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber],
            considering: sourceFormat
        ) ?? sourceFormat
        let analysisBuffer = try Self.buffer(sourceBuffer, convertedTo: targetFormat)

        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse)
        )
        try await analyzer.prepareToAnalyze(in: analysisBuffer.format)

        let startedAt = Date()
        async let output = Self.collectResults(from: transcriber, startedAt: startedAt)
        let inputSequence = AsyncStream<AnalyzerInput> { continuation in
            continuation.yield(AnalyzerInput(buffer: analysisBuffer))
            continuation.finish()
        }

        let analyzedUntil = try await analyzer.analyzeSequence(inputSequence)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let recognitionOutput = try await output

        RuntimeLog.write(
            "appleDictation complete textLength=\(recognitionOutput.text.count) duration=\(String(format: "%.2f", audioDuration)) analyzedUntil=\(analyzedUntil?.seconds ?? -1)"
        )

        return EngineTranscriptionResult(
            rawText: recognitionOutput.text,
            firstTokenMs: recognitionOutput.firstPartialMs,
            pipelineMs: nil,
            realTimeFactor: nil,
            speedFactor: nil,
            tokensPerSecond: nil,
            fallbackCount: nil
        )
    }

    func unload() {
        selectedLocale = nil
        Task {
            await SpeechModels.endRetention()
        }
    }

    private static func supportedLocale() async throws -> Locale {
        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale.current) {
            return locale
        }

        let englishUS = Locale(identifier: "en-US")
        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: englishUS) {
            return locale
        }

        throw TranscriptionError.engineUnavailable("Apple Dictation is not available for this locale.")
    }

    private static func prepareAssets(
        for transcriber: DictationTranscriber,
        updateState: @escaping @MainActor (ModelState) -> Void
    ) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        RuntimeLog.write("appleDictation asset status=\(status)")

        guard status != .unsupported else {
            throw TranscriptionError.engineUnavailable("Apple Dictation assets are not supported on this Mac.")
        }

        guard status != .installed else { return }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return
        }

        let progress = request.progress
        let progressTask = Task { @MainActor in
            while !Task.isCancelled, !progress.isFinished {
                updateState(.downloading(progress: progress.fractionCompleted))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        updateState(.downloading(progress: progress.fractionCompleted))
        do {
            try await request.downloadAndInstall()
            progressTask.cancel()
            updateState(.downloading(progress: 1))
        } catch {
            progressTask.cancel()
            throw error
        }
    }

    private static func collectResults(
        from transcriber: DictationTranscriber,
        startedAt: Date
    ) async throws -> AppleDictationRecognitionOutput {
        var transcript = TimeRangeTranscript()
        var firstPartialMs: Int?
        var bestSingleResultText = ""

        for try await result in transcriber.results {
            let text = String(result.text.characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if text.count >= bestSingleResultText.count {
                bestSingleResultText = text
            }

            if firstPartialMs == nil {
                firstPartialMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            }

            transcript.apply(text: text, range: result.range, isFinal: result.isFinal)
            RuntimeLog.write(
                "appleDictation result final=\(result.isFinal) textLength=\(text.count) fragments=\(transcript.fragmentCount) rangeStart=\(String(format: "%.2f", result.range.start.seconds)) rangeDuration=\(String(format: "%.2f", result.range.duration.seconds)) firstPartialMs=\(firstPartialMs ?? -1)"
            )
        }

        let mergedText = transcript.text
        let finalText = mergedText.count >= bestSingleResultText.count
            ? mergedText
            : bestSingleResultText

        return AppleDictationRecognitionOutput(
            text: finalText,
            firstPartialMs: firstPartialMs
        )
    }

    private static func makeSourceFormat() throws -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioRecorder.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw TranscriptionError.audioConversionFailed("Could not create source audio format.")
        }
        return format
    }

    private static func makeBuffer(
        from audioSamples: [Float],
        format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        guard !audioSamples.isEmpty else {
            throw TranscriptionError.audioConversionFailed("No audio samples to convert.")
        }

        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(audioSamples.count)
            ),
            let channel = buffer.floatChannelData?[0]
        else {
            throw TranscriptionError.audioConversionFailed("Could not create audio buffer.")
        }

        buffer.frameLength = AVAudioFrameCount(audioSamples.count)
        audioSamples.withUnsafeBufferPointer { samples in
            if let baseAddress = samples.baseAddress {
                channel.update(from: baseAddress, count: samples.count)
            }
        }
        return buffer
    }

    private static func buffer(
        _ sourceBuffer: AVAudioPCMBuffer,
        convertedTo targetFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let sourceFormat = sourceBuffer.format
        guard !formatsMatch(sourceFormat, targetFormat) else {
            return sourceBuffer
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw TranscriptionError.audioConversionFailed("Could not create analyzer audio converter.")
        }

        let targetFrames = AVAudioFrameCount(
            ceil(Double(sourceBuffer.frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate)
        ) + 1024
        guard let targetBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: max(targetFrames, 1)
        ) else {
            throw TranscriptionError.audioConversionFailed("Could not create analyzer audio buffer.")
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: targetBuffer, error: &conversionError) {
            _, outStatus in
            guard !didProvideInput else {
                outStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        guard status != .error, conversionError == nil, targetBuffer.frameLength > 0 else {
            let message = conversionError?.localizedDescription ?? "Analyzer audio conversion failed."
            throw TranscriptionError.audioConversionFailed(message)
        }

        return targetBuffer
    }

    private static func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.commonFormat == rhs.commonFormat
            && lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.isInterleaved == rhs.isInterleaved
    }
}

@available(macOS 26.0, *)
private struct AppleDictationRecognitionOutput: Sendable {
    var text: String
    var firstPartialMs: Int?
}

@available(macOS 26.0, *)
private struct TimeRangeTranscript {
    private var fragments: [Fragment] = []

    var fragmentCount: Int {
        fragments.count
    }

    var text: String {
        fragments
            .sorted { CMTimeCompare($0.range.start, $1.range.start) < 0 }
            .map(\.text)
            .joined(separator: " ")
    }

    mutating func apply(text: String, range: CMTimeRange, isFinal: Bool) {
        fragments.removeAll { existing in
            Self.rangesOverlap(existing.range, range)
                || CMTimeCompare(existing.range.start, range.start) == 0
        }
        fragments.append(Fragment(text: text, range: range, isFinal: isFinal))
    }

    private static func rangesOverlap(_ lhs: CMTimeRange, _ rhs: CMTimeRange) -> Bool {
        let lhsEnd = CMTimeRangeGetEnd(lhs)
        let rhsEnd = CMTimeRangeGetEnd(rhs)
        return CMTimeCompare(lhs.start, rhsEnd) < 0
            && CMTimeCompare(rhs.start, lhsEnd) < 0
    }

    private struct Fragment {
        var text: String
        var range: CMTimeRange
        var isFinal: Bool
    }
}
#endif
