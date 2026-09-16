# English ASR follow-up and LM latency profile

## Findings

English-only Parakeet TDT 0.6B v2 is the strongest measured English candidate.
It fixes the v3 `localhost` error, roughly halves Whisper's aggregate word errors,
and retains the large speed advantage. It still has individual regressions, so
this does not establish the requested zero-quality-loss replacement.

Warm LM latency is dominated by prompt processing, not loading model weights.
No production sources, settings, dependencies, or model selections changed.

## English-only ASR

Same M3 Max, release harness, 82 audio files, production signal gate and
postprocessing as the [earlier comparison](2026-09-15-model-comparison.md).
Two sequential rounds with two measured passes per speech file per round,
plus an untimed per-file warmup: 324 speech calls and two silence-gate records.
All four measured transcripts matched for every file.

| Engine | Warm median | p95 | Raw WER, all | Raw WER, original 8 | Raw WER, 73 LibriSpeech |
| --- | ---: | ---: | ---: | ---: | ---: |
| Whisper Turbo 632 MB | 546.24 ms | 871.78 ms | 5.50% | 2.34% | 6.09% |
| Parakeet 0.6B v3, default export | 83.25 ms | 170.16 ms | 3.67% | 3.74% | 3.65% |
| Parakeet 0.6B v2, English | **82.09 ms** | **123.16 ms** | **2.71%** | **2.34%** | **2.78%** |

Whisper and v3 numbers are from the earlier sweep. The v2 follow-up was not
counterbalanced with fresh baselines; small timing differences are not evidence
that v2 is faster than v3. The ratio of Whisper/v2 medians is 6.65x, and median
matched-call latency reduction against the earlier Whisper runs is 84.91%.

The four passes contain 5,456 reference words: Whisper 300 raw edit errors,
v3 200, English v2 148. These are repeated measurements of 81 distinct speech
clips, not 324 independent quality examples. Most natural speech is one
LibriSpeech speaker; this is not broad dictation accuracy proof.

English v2 has fewer raw word errors than Whisper on 22 clips, the same on 54,
and more on five. Remaining worse examples include:

- `were sleeping` becomes `are sleeping`.
- `sat in the throne` becomes `sat on the throne` (also regional spelling differences).
- `mantel` becomes `mantle`.
- `M A` becomes `MA`, and `I'm` becomes `I am`: metric penalties with little or no meaning loss.

The technical clip now preserves `localhost`. It still says `version 2.0 in
the database column` where the reference has `version two point zero and the
database column`; fixing one technical term is not perfect transcription.

WER is lowercased word edit distance and does not normalize numbers,
contractions, regional spelling, or abbreviations. Punctuation/casing are
retained in the exact outputs but excluded from WER. Production filler removal
adds eight edits across four passes for each engine; final-transcript WER is
5.65% Whisper, 3.81% v3, and 2.86% English v2. This expected cleanup difference
is why raw ASR WER is the primary recognition metric here.

Model: [NVIDIA English v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2),
using [FluidInference's Core ML conversion](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml)
at revision `ee09c569f73759e6d44c9bd16766f477b2b36d39`, verified before and after
the runs. FluidAudio revision remains
`b68f484789d81fda21efbf81e2ca9fcfd9dc22aa`.
This is a different model from the earlier v3 `Encoder_v2` experiment. The raw
row's `@int8` suffix is the harness's encoder selector; FluidAudio ignores that
selector for model v2. It is not a verified quantization description of v2.

## Where LM time goes

Instrumented the staged Llama 3.2 1B service using MLX's native generation timing
events. Same 23 existing smoke cases, three passes: 69 initial streams, six retry
streams, 75 complete timing reports. No missing or failed generation reports.

| Component | Total across 69 calls | Share of service wall time |
| --- | ---: | ---: |
| Prompt processing through first token | 9,044 ms | **62.36%** |
| Subsequent output generation | 4,401 ms | **30.34%** |
| Other work | 1,059 ms | **7.30%** |

Total service wall time: 14,505 ms. Median per call: 160.75 ms. Median generation
stream: 610 input tokens, 11 output tokens. This shorter smoke-only corpus and
separate run must not be compared as a speedup against the earlier 65-case,
324.54 ms LM median.

The six retries consumed 2,212 ms, or 15.25% of total time. This overlaps prompt
and decoding time; it is not a fourth additive category. Retries occurred for
the false-start PR sentence and the long auto-appended-thank-you sentence.

The model container stays resident between requests (663 MiB active MLX memory
in this run). Loading and warmup are outside the timing. Reading weights during
GPU inference is distinct from loading the model from disk. This profile does
not distinguish GPU memory stalls from arithmetic execution.

MLX's prompt time includes prefill and first-token work. Other time includes
chat template/tokenization, scheduling, validation, cache management, and the
profiler's file writes. File writes occur outside the reported generation
session time but inside outer service time. There is no claim of separately
measuring pure tokenization or validation cost.

All 69 outputs, candidates, acceptance decisions, fallback reasons and smoke
failures matched the prior first-round baseline. Each repetition passed 22/23
existing checks; `normal style preserves meaningful like` remains the known
failure. Production source/package diff is empty. Both new harness variants
built and ran successfully. Prior full repo checks are recorded in the earlier
report; they were not rerun for these benchmark-only changes.

## Optimization implications and larger candidates

- Prompt shortening is the main LM experiment to try: instructions and examples
  dominate short requests. It needs repeated behavioral evaluation; no prompt
  was shortened here. Removing retry safeguards is not a quality-preserving fix.
- Earlier allocation caches produced no useful gain. The tested 512-token
  prefix-cache prototype was 4.35% slower; caching is not an established win.
- Current ASR remains the larger latency target. After fast ASR, the LM becomes
  the larger stage. Adding the separate earlier medians gives roughly 871 ms
  for Whisper+Llama versus 407 ms for English v2+Llama; this is an illustration,
  not measured end-to-end stop-to-paste latency.
- [Canary 1B v2 Core ML](https://huggingface.co/FluidInference/canary-1b-v2-coreml)
  is a practical larger Mac candidate. The pinned FluidAudio implementation is
  beta, decodes autoregressively without a KV cache, and returns text without
  the word timing/confidence contract used by ShoutOut's filter. It needs runtime
  and functional validation; a larger parameter count does not ensure a win.
- [Qwen3-ASR 1.7B](https://huggingface.co/Qwen/Qwen3-ASR-1.7B) supports English and
  has an [MLX conversion](https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-bf16).
  It needs an ASR adapter; this is unrelated to the Qwen3.5 cleanup model tested
  earlier. [Canary-Qwen 2.5B](https://huggingface.co/nvidia/canary-qwen-2.5b) is
  another English specialist, with a larger runtime/integration burden.
- [Parakeet TDT 1.1B](https://huggingface.co/nvidia/parakeet-tdt-1.1b) is the
  literal larger family member, but it outputs lowercase English and is not a
  direct functional replacement for the newer punctuated models.

These larger candidates were researched, not locally benchmarked in this
follow-up. No claim is made about their latency or quality on this corpus.

Full per-case results, LM phase events, model/file hashes and source provenance:
[results JSON](2026-09-15-english-latency-results.json). Reproduction commands:
[benchmark README](../../apps/macos/Tools/DictationBenchmark/README.md).
