# Transcription and cleanup benchmark — September 15, 2026

## Result

None of the tested changes produced a reliable speedup. All production experiments
were reverted. App sources, prompts, model choices, decoding options, generation
budgets, validators, and existing tests remain identical to commit `7f77346`.
The retained changes are the repeatable benchmark tools and this report.

| Experiment | Paired latency change | Output comparison | Decision |
| --- | ---: | --- | --- |
| MLX allocation cache: 2 / 8 / 32 MiB | 0.11% / 0.07% / 0.33% slower | Exact match | Reject; no benefit |
| MLX allocation cache: 64 / 128 / 256 MiB | 0.40% faster / 0.07% slower / 0.27% faster | Exact match | Reject; within noise |
| Cache first 512 system-prompt tokens | 4.35% slower | Exact match | Reject |
| Whisper encoder on GPU | 34.83% slower | Exact match | Reject |
| Whisper decoder on GPU | 24.11% slower | Exact match | Reject |

Percentages are the median of matched per-case, per-repetition latency ratios.
Absolute medians across different experiments are not directly comparable: workloads
and system conditions differ. ASR profiles ran sequentially, rather than interleaved.

In the encoder trial, median ASR time rose from **592 ms to 803 ms**. In the decoder
trial it rose from **593 ms to 757 ms**. The long synthetic recording rose from
approximately **2.23 s to 2.67 s** with GPU encoding. The existing CPU/Neural Engine
placement was better on this machine.

## Setup

- Apple M3 Max, 128 GiB unified memory; macOS 26.6.2; Swift 6.3.2; release builds.
- WhisperKit 0.17.0, `large-v3-v20240930_turbo_632MB`, matching the motivating runtime logs.
- MLX Swift 0.31.4 / MLX Swift LM 3.31.3, `Llama-3.2-1B-Instruct-4bit`.
- Nine audio fixtures: five synthesized requests with two voices, one natural JFK
  recording, noisy and trailing-silence variants, and a silence control.
- The same 23 existing smoke cases, plus eight ASR transcripts in all three styles:
  **47 cleanup inputs** for the small-cache and prefix-cache comparisons.
- Small allocation sweep: three repetitions, 141 runs per policy.
- Large allocation sweep: five repetitions of the 23 smoke cases, 115 runs per policy.
- Prefix-cache pilot: two repetitions, 94 runs per policy. This prototype preserved
  the original 512-token prefill boundary, cached only system tokens, and copied
  cache state per request. It was removed after the slower result.
- Compute placement: eight speech clips × three repetitions = 24 timed ASR runs per
  profile, with an untimed warmup for each clip. The silence control was rejected
  before transcription, as expected.

The benchmark builds production service sources in an isolated command-line package.
Tokenizer storage is redirected from Documents to `.build/benchmark-tokenizers`;
Documents reads hung during the initial setup. Core ML's initial model preparation,
tokenizer/model loading, and audio file loading are outside warm timings. Runtime
diagnostics are isolated from the installed app log. The benchmark does not launch
the GUI, record a microphone, insert text, or write app history.

## Quality and validation

- **PASS:** 309 repository checks.
- **PASS:** 139 XCTest cases and 20 Swift Testing cases.
- **Existing failure:** the standalone LM smoke suite passes 22/23 cases. The
  `normal style preserves meaningful like` case expects `I like this direction.`
  and receives `i like this direction.` This was present before experiments; neither
  the prompt nor the expectation was changed.
- **PASS:** all 862 paired cleanup comparisons in the allocation and prefix-cache
  experiments matched candidate text, final text, acceptance, fallback reason,
  and smoke outcome exactly. The existing capitalization failure was unchanged.
- **PASS:** all 48 paired ASR comparisons across the GPU encoder/decoder experiments
  matched raw text, postprocessed text, and the accept/drop decision exactly.
- Aggregate normalized raw word-error rate on these speech clips was **2.34%** for
  both the original placement and each GPU variant. Number formatting in the
  technical fixture contributes to this metric; it is not a semantic accuracy score.
- MLX's idle allocation cache returned to zero after each cleanup. Peak active MLX
  memory excludes cached buffers and Core ML, so it is not total process memory.

The decoder experiment's subsequent LM-only tail is excluded from LM conclusions:
it briefly overlapped the startup of a discarded run and included one baseline
timeout. Its ASR measurements had already completed. The paired cache sweeps used
for the table ran in isolation.

This is a limited English corpus on one Mac. It does not prove accuracy across
languages, accents, microphones, or hardware. It measures ASR and cleanup separately,
not stop-key-to-visible-paste latency. No runtime improvement is claimed or shipped.

## Reproduce and inspect

See [benchmark instructions](../../apps/macos/Tools/DictationBenchmark/README.md).
The fixture generator records audio SHA-256 hashes and provenance, including the
[Whisper JFK sample](https://github.com/openai/whisper/blob/main/tests/jfk.flac).
Use a custom audio manifest for additional recordings.

- [Machine-readable aggregate results](2026-09-15-inference-results.json)
- [Small-cache raw measurements](../../apps/macos/.build/benchmark-cache-sweep.json)
- [Large-cache raw measurements](../../apps/macos/.build/benchmark-large-cache.json)
- [Prefix-cache pilot measurements](../../apps/macos/.build/benchmark-prefix-pilot.json)
- [GPU encoder measurements](../../apps/macos/.build/benchmark-encoder-pilot.json)
- [GPU decoder measurements](../../apps/macos/.build/benchmark-decoder-pilot.json)
- [Audio manifest and hashes](../../apps/macos/.build/dictation-audio/manifest.json)

Raw measurements and generated audio remain local under ignored `.build`; aggregate
results and the runner are retained in the repository. Each completed run also writes
a `.sources.json` sidecar identifying the service sources used.
