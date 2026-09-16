import Foundation
import MLX
import ShoutOutCore
@preconcurrency import WhisperKit

struct AudioFixture: Decodable {
  var name: String
  var path: String
  var reference: String
}

struct LanguageFixture: Decodable {
  var name: String
  var input: String
}

struct BenchmarkRow: Codable {
  var name: String
  var kind: String
  var repetition: Int
  var cacheMiB: Int
  var style: String
  var input: String
  var candidate: String?
  var final: String
  var accepted: Bool
  var fallback: String?
  var wallMs: Double
  var serviceWallMs: Int?
  var peakBytes: Int
  var activeBytes: Int
  var cachedBytes: Int
  var failure: String?
  var reference: String?
  var compute = "default"
  var model: String?
  var modelLoadMs: Double?
  var inferenceMs: Int?
  var audioDuration: Double?
  var firstFilePass: Bool?
  var asrRaw: String?
  var asrMs: Double?
  var lmMs: Double?
  var asrFallbacks: Int?
}

@main
struct DictationBenchmark {
  @MainActor
  static func main() async throws {
    let environment = ProcessInfo.processInfo.environment
    let outputURL = URL(fileURLWithPath: environment["BENCH_OUTPUT"]!)
    let repetitions = Int(environment["BENCH_REPETITIONS"] ?? "5")!
    let limits = environment["BENCH_CACHE_MIB", default: "0,2,8,32"].split(separator: ",").map {
      Int($0)!
    }
    precondition(repetitions > 0 && !limits.isEmpty && limits.allSatisfy { $0 >= 0 })

    // Argument-domain values are process-local: no app preferences/history are changed.
    UserDefaults.standard.setVolatileDomain(
      [
        Defaults.languagePassEnabled: true,
        Defaults.languagePassModel: BenchmarkLanguageConfiguration.modelID,
        Defaults.languagePassModelCleanupVersion: 1,
        Defaults.transcriptionBackend: environment["BENCH_ASR"] == "production-parakeet"
          ? TranscriptionBackend.parakeet.rawValue : TranscriptionBackend.whisperKit.rawValue,
        "selectedModel": environment["BENCH_MODEL_ID"] ?? TranscriptionModelOption.benchmarkTurboID,
        "removeFillerWords": true,
      ], forName: UserDefaults.argumentDomain)

    let languageService = LanguagePassService()
    var languageModelLoadMs: Double?
    if environment["BENCH_AUDIO_ONLY"] != "1" {
      let loadStart = ContinuousClock.now
      await languageService.prepareIfNeeded()
      languageModelLoadMs = milliseconds(since: loadStart)
      guard languageService.modelState == .ready else {
        fatalError("Language model did not load: \(languageService.modelState)")
      }
    }
    var rows: [BenchmarkRow] = []
    var inputs = SmokeCorpus.cases.map { ($0.name, $0.input, $0.style, Optional($0)) }
    if let path = environment["BENCH_LM_INPUTS"] {
      let fixtures = try JSONDecoder().decode([LanguageFixture].self,
        from: Data(contentsOf: URL(fileURLWithPath: path)))
      for fixture in fixtures {
        for style in [LanguagePassStyle.standard, .casual, .formal] {
          inputs.append((fixture.name, fixture.input, style, nil))
        }
      }
    }

    if let manifestPath = environment["BENCH_AUDIO_MANIFEST"] {
      let manifestURL = URL(fileURLWithPath: manifestPath)
      let fixtures = try JSONDecoder().decode(
        [AudioFixture].self, from: Data(contentsOf: manifestURL))
      let profiles = environment["BENCH_COMPUTE_PROFILES", default: "default"].split(separator: ",")
        .map(String.init)
      for profile in profiles {
        BenchmarkConfiguration.profile = profile
        let service = TranscriptionService()
        let loadStart = ContinuousClock.now
        await service.loadModel()
        let modelLoadMs = milliseconds(since: loadStart)
        guard service.modelState == .ready else { fatalError("Whisper model did not load") }
        for fixture in fixtures {
          let path = manifestURL.deletingLastPathComponent().appendingPathComponent(fixture.path)
            .path
          let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
          let trimmed = AudioSignalAnalysis.trimmingTrailingSilence(
            from: samples, sampleRate: AudioRecorder.sampleRate)
          let signal = AudioSignalAnalysis.analyze(samples: trimmed)
          guard signal.hasSustainedSpeechLikeAudio(sampleRate: AudioRecorder.sampleRate) else {
            if !fixture.reference.isEmpty {
              fatalError("Unexpected speech gate rejection: \(fixture.name)")
            }
            rows.append(
              BenchmarkRow(
                name: fixture.name, kind: "audio-gate", repetition: 0,
                cacheMiB: 0, style: "none", input: "", final: "", accepted: true, wallMs: 0,
                peakBytes: 0, activeBytes: 0, cachedBytes: 0, reference: fixture.reference))
            continue
          }
          let measureFirstPass = environment["BENCH_MEASURE_FIRST_PASS"] == "1"
          if !measureFirstPass {
            _ = try await service.transcribeWithTiming(audioSamples: trimmed)
          }
          for repetition in 0..<repetitions {
            let start = ContinuousClock.now
            let result = try await service.transcribeWithTiming(audioSamples: trimmed)
            let duration = Double(trimmed.count) / AudioRecorder.sampleRate
            let dropped = TranscriptHallucinationFilter.shouldDrop(
              text: result.result.finalText, recordingDuration: duration, signal: signal)
            let asrElapsed = milliseconds(since: start)
            rows.append(
              BenchmarkRow(
                name: fixture.name, kind: "asr", repetition: repetition,
                cacheMiB: 0, style: "none", input: result.result.rawText,
                final: dropped ? "" : result.result.finalText, accepted: !dropped,
                wallMs: asrElapsed, serviceWallMs: result.timing.engineWallMs,
                peakBytes: 0, activeBytes: 0, cachedBytes: 0, reference: fixture.reference,
                compute: profile, model: environment["BENCH_ASR"] == "parakeet"
                  ? "parakeet-tdt-0.6b-" + environment["BENCH_PARAKEET_VERSION", default: "v3"]
                    + "@" + environment["BENCH_PARAKEET_ENCODER", default: "int8"]
                  : environment["BENCH_ASR"] == "python" ? environment["BENCH_PYTHON_MODEL"]
                  : environment["BENCH_ASR"] == "swift-parakeet" ? "parakeet-1.1b-swift"
                  : environment["BENCH_ASR"] == "production-parakeet" ? ParakeetTranscriptionEngine.identifier
                  : environment["BENCH_MODEL_ID"],
                modelLoadMs: modelLoadMs, inferenceMs: result.timing.enginePipelineMs,
                audioDuration: duration, firstFilePass: measureFirstPass && repetition == 0,
                asrFallbacks: result.timing.fallbackCount))
            if let style = LanguagePassStyle(rawValue: environment["BENCH_PIPELINE_STYLE"] ?? "") {
              languageService.selectedStyle = style
              let lmStart = ContinuousClock.now
              let cleanup: LanguagePassRunResult
              let lmElapsed: Double
              if dropped || result.result.finalText.isEmpty {
                cleanup = .passthrough("", enabled: true, fallbackReason: "asr_empty")
                lmElapsed = 0
              } else {
                cleanup = await languageService.process(
                  rawText: result.result.rawText, baseText: result.result.finalText)
                lmElapsed = milliseconds(since: lmStart)
              }
              let memory = Memory.snapshot()
              rows.append(BenchmarkRow(
                name: fixture.name, kind: "pipeline", repetition: repetition,
                cacheMiB: 0, style: style.rawValue, input: result.result.finalText,
                candidate: cleanup.candidateText, final: cleanup.finalText,
                accepted: cleanup.accepted, fallback: cleanup.fallbackReason,
                wallMs: milliseconds(since: start), serviceWallMs: cleanup.wallMs,
                peakBytes: memory.peakMemory, activeBytes: memory.activeMemory,
                cachedBytes: memory.cacheMemory, reference: fixture.reference,
                model: service.activeModelIdentifier, modelLoadMs: modelLoadMs,
                audioDuration: duration, firstFilePass: measureFirstPass && repetition == 0,
                asrRaw: result.result.rawText, asrMs: asrElapsed, lmMs: lmElapsed,
                asrFallbacks: result.timing.fallbackCount))
            }
            if repetition == 0 && !dropped && profile == profiles[0] {
              for style in [LanguagePassStyle.standard, .casual, .formal] {
                inputs.append(("audio: " + fixture.name, result.result.finalText, style, nil))
              }
            }
          }
          print("Transcribed \(fixture.name)")
          try save(rows, to: outputURL)
        }
        try save(rows, to: outputURL)
      }
    }

    if environment["BENCH_AUDIO_ONLY"] == "1" || !(environment["BENCH_PIPELINE_STYLE"] ?? "").isEmpty {
      try save(rows, to: outputURL)
      return
    }

    // Warm each allocation policy before collecting interleaved measurements.
    for limit in limits {
      Memory.cacheLimit = limit * 1_024 * 1_024
      _ = await languageService.process(
        rawText: "", baseText: "Can you send this over when you get a chance?")
    }
    for repetition in 0..<repetitions {
      let orderedInputs = environment["BENCH_REVERSE_ODD_ROUNDS"] == "1" && repetition % 2 == 1
        ? Array(inputs.reversed()) : inputs
      for (index, item) in orderedInputs.enumerated() {
        let (name, input, style, smokeCase) = item
        languageService.selectedStyle = style
        // Rotate policy order to distribute warmup/thermal/order effects.
        for offset in limits.indices {
          let limit = limits[(offset + repetition + index) % limits.count]
          Memory.cacheLimit = limit * 1_024 * 1_024
          Memory.peakMemory = 0
          let start = ContinuousClock.now
          let result = await languageService.process(rawText: input, baseText: input)
          let elapsed = milliseconds(since: start)
          let memory = Memory.snapshot()
          rows.append(
            BenchmarkRow(
              name: name, kind: smokeCase == nil ? "audio-lm" : "smoke-lm",
              repetition: repetition, cacheMiB: limit, style: style.rawValue,
              input: input, candidate: result.candidateText, final: result.finalText,
              accepted: result.accepted, fallback: result.fallbackReason, wallMs: elapsed,
              serviceWallMs: result.wallMs, peakBytes: memory.peakMemory,
              activeBytes: memory.activeMemory, cachedBytes: memory.cacheMemory,
              failure: smokeCase.flatMap { failure(for: $0, result: result) },
              model: BenchmarkLanguageConfiguration.modelID, modelLoadMs: languageModelLoadMs))
        }
        if (index + 1) % 50 == 0 {
          try save(rows, to: outputURL)
          print("Completed \(index + 1)/\(orderedInputs.count) inputs in pass \(repetition + 1)")
        }
      }
      try save(rows, to: outputURL)
      print("Completed repetition \(repetition + 1)/\(repetitions), \(rows.count) rows")
    }
    print("Saved \(outputURL.path)")
  }

  static func milliseconds(since start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now).components
    return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
  }

  static func save(_ rows: [BenchmarkRow], to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(rows).write(to: url, options: .atomic)
  }

  static func failure(for smokeCase: SmokeCase, result: LanguagePassRunResult) -> String? {
    if !result.accepted {
      return smokeCase.expectation == .requiredRewrite ? "expected accepted rewrite" : nil
    }
    if let expected = smokeCase.expectedOutput, result.finalText != expected {
      return "expected output mismatch"
    }
    let lower = result.finalText.lowercased()
    for fragment in smokeCase.expectedFragments where !lower.contains(fragment.lowercased()) {
      return "missing expected fragment: \(fragment)"
    }
    for fragment in smokeCase.rejectedFragments where lower.contains(fragment.lowercased()) {
      return "retained rejected fragment: \(fragment)"
    }
    return nil
  }
}
