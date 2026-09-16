# Replacement-model benchmark — September 15, 2026

## Conclusion

Parakeet v3 is a substantial transcription speedup on this Mac and improves
aggregate English word error rate. It still introduces individual transcription
regressions, so this experiment does not establish a quality-preserving universal
replacement for Whisper. Neither Qwen3.5 0.8B nor LFM2.5 1.2B passes the existing
cleanup quality gate with the current prompt, validator, and runtime budgets.

Production sources, tests, dependency pins, installed-app model selection, and app settings
remain unchanged. Candidate downloads and executable adapters are benchmark-only.

## Setup

- Apple M3 Max, macOS 26.6.2 (25G83), AC power; release Swift builds.
- Existing production dependency versions: WhisperKit 0.17.0, MLX Swift 0.31.4,
  MLX Swift LM 3.31.3, Swift Transformers 1.1.9. Benchmark dependency pins match
  the original package pins; FluidAudio is an additional isolated local dependency.
- FluidAudio commit `b68f484789d81fda21efbf81e2ca9fcfd9dc22aa`.
- 82 audio fixtures, 557.70 seconds total: the previous nine fixtures plus 73
  LibriSpeech dummy clips. 81 contain speech; one silence control is rejected
  by the existing signal gate before either engine runs. LibriSpeech has one
  speaker; the original corpus includes two synthetic voices and JFK.
- ASR: two rounds, reversed engine order, two measured runs per speech file per
  round, plus one warmup per file per round. 324 measured runs per engine.
- LM: unchanged 23 smoke cases, eight frozen Whisper transcripts × three styles,
  and six stress inputs × three styles = 65 cases. Three rounds rotate model
  order (Llama/Qwen/LFM, Qwen/LFM/Llama, LFM/Llama/Qwen): 195 runs per model,
  585 measured LM calls total.
- No concurrent benchmark inference or builds during timed sweeps. This is a
  shared desktop, not a controlled performance lab.

Model downloading, loading, audio-file decoding, input silence trimming, and
speech gating are outside the timed ASR call. Timed ASR includes the engine and
production text postprocessing/hallucination filtering. LM timing includes prompt
processing, generation, retries, validation, fallback, and cache clearing. Neither
measurement includes microphone capture, visible paste, or startup latency.

## Transcription: Whisper vs Parakeet

| Model | Median | p95 | Raw WER, all speech | Raw WER, original eight clips | Raw WER, LibriSpeech |
| --- | ---: | ---: | ---: | ---: | ---: |
| Whisper Turbo 632 MB | 546.24 ms | 871.78 ms | 5.50% | 2.34% | 6.09% |
| Parakeet TDT 0.6B v3, default encoder | 83.25 ms | 170.16 ms | 3.67% | 3.74% | 3.65% |
| Parakeet TDT 0.6B v3, newer encoder | 83.92 ms | 163.89 ms | 3.74% | 2.80% | 3.91% |

Median paired latency reduction: **84.78%**. The ratio of aggregate medians is
6.56×. Parakeet has fewer normalized word errors on 20 clips, the same count on
55, and more on six. Some metric differences are harmless spelling/contraction
variants; others are real recognition regressions:

- Technical fixture: Whisper recognizes `localhost`; Parakeet returns `local list`.
- `librispeech-1272-141231-0006`: Whisper recognizes “The buzzer's whirr”; Parakeet
  returns “The buzzer of swirr”.
- Both engines retain the short request correctly with noise and trailing silence.

WER lowercases and ignores punctuation, but does not normalize number spellings,
contractions, or regional spelling. The raw metric precedes deliberate filler
removal. References have 1,364 words per pass; four passes give 5,456 reference
words. Whisper makes 300 raw word edits versus Parakeet's 200 across those passes.
Final postprocessed text has 308 versus 208 edits; intentional filler removal can
increase that metric against verbatim references.

The FluidAudio API calls the default encoder option `.int8`, but the downloaded
model metadata identifies `Encoder.mlmodelc` as mixed 6-bit LUT palettization/FP16.
An additional 324-call follow-up tested the opt-in `.int8V2` export,
`Encoder_v2.mlmodelc`, with genuine per-channel int8 quantization. This is still
the multilingual **v3 model**, not the English-only v2 model. It ran after the
primary reversed-order sweep, so its timing comparison is not counterbalanced.
Its median paired latency reduction against the saved Whisper runs is 84.64%.
It has fewer word errors on 18 clips, the same count on 56, and more on seven.
It retains the `localhost` → `local list` error and makes 204 raw edits overall,
versus the default encoder's 200. It does not satisfy the no-regression condition.
There are **972 measured ASR calls** across Whisper and the two Parakeet exports,
plus six silence-gate records; warmups are excluded from these counts.

The adapter supplies word timings and averaged token confidence to ShoutOut's
existing filter. Cross-engine confidence calibration remains unverified.
[Parakeet v3 supports 25 European languages](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3),
so it cannot preserve Whisper's broader language coverage as a blanket replacement.

## Cleanup: current Llama vs Qwen and LFM

| Model, all 4-bit | Median | p95 | Median paired latency change | Existing smoke passes by round |
| --- | ---: | ---: | ---: | --- |
| Llama 3.2 1B | 324.54 ms | 1,051.75 ms | baseline | 22/23, 22/23, 21/23 |
| Qwen3.5 0.8B | 334.81 ms | 1,239.85 ms | 5.07% slower | 18/23, 18/23, 18/23 |
| LFM2.5 1.2B Instruct | 334.34 ms | 923.52 ms | 7.11% slower | 9/23, 9/23, 9/23 |

Latency drift was material: Llama's per-round medians were 247, 340, and 386 ms.
The small aggregate latency differences are not convincing evidence of a stable
speed difference. The repeated quality failures are decisive for the current setup.

- Qwen has five persistent new smoke failures. It leaves lowercase/unpunctuated
  text in standard style and retains filler `like` in casual/formal cleanup.
  One failure is a strict existing expectation requiring an accepted rewrite of
  an already-clean command; it does not demonstrate meaning loss.
- LFM has 14 failing smoke cases, including the case Llama already fails. It
  sometimes answers the speaker, drops details, or leaks few-shot example text.
  Input `please have a sub agent do the localhost thing` produced candidate
  `The diff is ready.`; the validator rejected it and preserved the input.
- Llama's persistent existing failure is standard-style capitalization in
  “normal style preserves meaningful like”. Round three also has a
  `generation_failed` result for “actually false start removes abandoned article”.
  The harness did not retain the underlying exception, so timeout vs another
  generation error is not conclusively distinguished.
- Direct results with no fallback reason: Llama 110/195, Qwen 87/195, LFM 6/195.
  Mechanical fallbacks: 18/195, 21/195, 57/195 respectively. These are runtime
  categories, not independent quality grades; unchanged input can be correct.

All models use native chat templates and temperature zero. Qwen thinking is
explicitly disabled. Candidate prompts remove only the Llama identity sentence;
cleanup instructions, few-shot examples, generation budgets, retries, validator,
and mechanical fallbacks remain unchanged. These results evaluate compatibility
with this cleanup pipeline, not each model's best performance after prompt tuning.

## Additional quality findings

Manual inspection of the stress outputs found problems beyond the unchanged
smoke assertions. These are post-run observations, not a retrospectively claimed
pre-registered test score:

- **Current Llama, formal:** `Do not merge the pull request or delete the old
  database.` becomes `Do not merge the pull request. Delete the old database.`
  The validator accepts this reversal in all three rounds.
- **Current Llama, standard/formal:** the accepted output drops `REPL-31937`.
- **Qwen, standard:** the accepted output changes `REPL-31937` to `REPORT-31937`
  in all three rounds.
- **Shared casual fallback:** `$1,250.50` becomes `$125050`, and `config.json`
  becomes `configjson`. Changing the model does not remove these fallback defects.

Consequently, neither passing the existing smoke suite nor a high validator
acceptance rate alone establishes preserved meaning, identifiers, and numbers.
The new inputs and complete distinct outputs are retained for future regression
coverage. This benchmark does not modify production cleanup behavior.

## Reproduce and inspect

See [benchmark instructions](../../apps/macos/Tools/DictationBenchmark/README.md).
Local raw runs, per-run logs, and source-hash sidecars are under
`apps/macos/.build/model-comparison/`. The initial incomplete-download preflight
and build-check runs are excluded from all reported denominators. Timed LM runs
were restarted after both candidate snapshots finished downloading.

Pinned candidate snapshots:

- `mlx-community/Qwen3.5-0.8B-4bit`: `da28692b5f139cb0ec58a356b437486b7dac7462`
- `mlx-community/LFM2.5-1.2B-Instruct-4bit`: `dee2f8a2786e6648bb644a7ca40652842490034b`
- `FluidInference/parakeet-tdt-0.6b-v3-coreml`: `7dd20fe6b1797d35f5e3307e8b1732d9a178edfe`

Model-file SHA-256s, input manifests, source hashes, distributions, and distinct
outputs are retained in the [companion results JSON](2026-09-15-model-comparison-results.json). The audio corpus and model
weights remain under `.build`, outside source control.

## Validation

- `swift test`: 139 XCTest tests and 20 Swift Testing tests pass.
- `SKIP_SWIFTPM=true bash scripts/test.sh`: 309 checks pass.
- Python benchmark sources parse; the compiled release harness completes all
  candidate runs. Both build-check runs reproduce the known 22/23 LM smoke result.
- `git diff --check` passes. Production `Sources`, `Tests`, `Package.swift`, and
  `Package.resolved` have no diff. No model was switched in the installed app.
