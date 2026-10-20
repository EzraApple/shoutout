import AVFoundation
import Foundation
import ShoutOutCore

/// Local audio replay uses production capture collection, streaming order, ASR,
/// dictionary, and cleanup. Its result sink never writes to another application.
@MainActor
enum DictationReplay {
    private struct Fixture: Decodable {
        let name: String
        let path: String
        let reference: String
    }

    static func run(manifest: URL, profile: UserDefaults? = nil,
                    modelsDirectory: URL = TranscriptionService.modelsDirectory,
                    languageModelsDirectory: URL = LanguagePassService.modelsDirectory) async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["SHOUTOUT_REPLAY_OUTPUT"] else {
            throw TranscriptionError.engineUnavailable("Set SHOUTOUT_REPLAY_OUTPUT for local replay.")
        }
        let streaming = environment["SHOUTOUT_REPLAY_ENGINE"] == "hexStreaming"
        let paced = environment["SHOUTOUT_REPLAY_PACING"] != "0"
        let suite = "ShoutOut.Replay.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(streaming, forKey: "streamingTranscriptionEnabled")
        defaults.set("parakeet", forKey: Defaults.transcriptionBackend)
        defaults.set(TranscriptionModelOption.defaultID, forKey: "selectedModel")
        defaults.set(true, forKey: "removeFillerWords")
        defaults.set(profile?.object(forKey: Defaults.languagePassEnabled) == nil
            || profile?.bool(forKey: Defaults.languagePassEnabled) == true, forKey: Defaults.languagePassEnabled)
        defaults.set(LanguagePassModelOption.defaultID, forKey: Defaults.languagePassModel)
        defaults.set(1, forKey: Defaults.languagePassModelCleanupVersion)
        defaults.set(profile?.string(forKey: Defaults.languagePassStyle)
            ?? LanguagePassStyle.defaultStyle.rawValue, forKey: Defaults.languagePassStyle)
        let service = TranscriptionService(defaults: defaults, modelsDirectory: modelsDirectory)
        let cleanup = LanguagePassService(defaults: defaults, modelsDirectory: languageModelsDirectory)
        await service.loadModel()
        guard service.modelState.isReady else {
            throw TranscriptionError.modelLoadFailed("\(service.modelState)")
        }
        if cleanup.isEnabled {
            await cleanup.prepareIfNeeded()
            guard cleanup.modelState.isReady else {
                throw TranscriptionError.engineUnavailable("Replay requires the selected cleanup model to be ready.")
            }
        }
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: manifest))
        let recorder = AudioRecorder()
        var observations: [[String: Any]] = []
        let clock = ContinuousClock()
        for fixture in fixtures {
            let url = fixture.path.hasPrefix("/") ? URL(fileURLWithPath: fixture.path)
                : manifest.deletingLastPathComponent().appendingPathComponent(fixture.path)
            let audio = try loadAudio(url)
            let recording = service.beginRecording()
            recorder.onSamples = { service.appendRecordingSamples($0, recording: recording) }
            recorder.startReplay()
            let started = clock.now
            for offset in stride(from: 0, to: audio.count, by: 800) {
                let end = min(offset + 800, audio.count)
                if paced {
                    try await clock.sleep(until: started.advanced(by: .seconds(Double(end) / 16000)))
                }
                recorder.appendReplaySamples(Array(audio[offset..<end]))
            }
            let released = clock.now
            // The normal hold shortcut keeps capturing for 80 ms after release.
            if paced { try await Task.sleep(for: .milliseconds(80)) }
            recorder.appendReplaySamples([Float](repeating: 0, count: 1280))
            let recorded = recorder.stopRecording()
            recorder.onSamples = nil
            let samples = AudioSignalAnalysis.trimmingTrailingSilence(from: recorded, sampleRate: 16000)
            let samplesReady = clock.now
            let signal = AudioSignalAnalysis.analyze(samples: samples)
            var row: [String: Any] = [
                "name": fixture.name, "reference": fixture.reference,
                "engine": service.selectedBackend.rawValue, "paced": paced,
                "audioSeconds": Double(audio.count) / 16000,
                "stopToSamplesMs": milliseconds(released.duration(to: samplesReady)),
            ]
            if samples.count < AudioRecorder.minimumSamples || !signal.hasSustainedSpeechLikeAudio(sampleRate: 16000) {
                service.cancelRecording(recording)
                row["status"] = "silent"
                row["rawText"] = ""
                row["finalText"] = ""
            } else {
                service.finishRecording(recording, audioSamples: samples)
                let transcription = try await service.transcribeWithTiming(audioSamples: samples, recording: recording)
                row["stopToASRMs"] = milliseconds(released.duration(to: clock.now))
                row["rawText"] = transcription.result.rawText
                row["fallbacks"] = transcription.timing.fallbackCount ?? 0
                if TranscriptHallucinationFilter.shouldDrop(
                    text: transcription.result.finalText,
                    recordingDuration: Double(samples.count) / 16000, signal: signal
                ) {
                    row["status"] = "lowInformation"
                    row["finalText"] = ""
                } else {
                    let corrected = DictionaryReplacer.replace(transcription.result.finalText, entries: [])
                    let result = await cleanup.process(rawText: transcription.result.rawText, baseText: corrected)
                    row["status"] = "completed"
                    row["finalText"] = result.finalText
                    row["cleanupMs"] = result.wallMs
                    row["cleanupAccepted"] = result.accepted
                }
                row["stopToSinkMs"] = milliseconds(released.duration(to: clock.now))
            }
            observations.append(row)
            try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: output), options: .atomic)
            FileHandle.standardError.write(Data("Replay \(fixture.name): \(row["status"] ?? "unknown")\n".utf8))
        }
        cleanup.unload()
    }

    private static func loadAudio(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1,
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { throw TranscriptionError.audioConversionFailed("Replay audio must be mono 16 kHz WAV.") }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else {
            throw TranscriptionError.audioConversionFailed("Replay audio has no PCM channel.")
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}
