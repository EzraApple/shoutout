# Larger English ASR models and the cleanup pass

## Scope and method

All runs use the same M3 Max and the unchanged 82-file audio manifest from the
earlier comparisons: 81 speech clips plus a silence control. Most natural speech
is one LibriSpeech speaker; eight speech fixtures cover the original dictation,
technical, correction, noise, long-input and trailing-silence cases. This is a
narrow benchmark, not broad real-world dictation accuracy proof.

Full results: [searchable output comparison](2026-09-15-larger-models-outputs.html)
and [timings, both output passes, controls and provenance](2026-09-15-larger-models-results.json).

Seven configurations were measured: six ASR models plus a frontend comparison
for Parakeet 1.1B. Each configuration has 162 measured speech calls (two per
clip), 81 untimed per-file warmups and one native silence-gate result. Main sweep:
**1,134 measured ASR calls, 567 warmups, seven silence-gate records**. The initial
frontend pilot adds 162 measured calls and 81 warmups, excluded from the main
timing comparison. All corrected-frontend transcripts matched that pilot exactly.

Each model runs serially in its own process. Fresh Whisper, Parakeet v2 and
Parakeet v3 controls follow the larger models. Model order is not counterbalanced;
small timing differences should not be treated as statistically established.
The same-file warmups also make these optimistic warm timings, not first-use
latency on every novel audio shape.

The benchmark-only native adapter passes the exact same trimmed float samples
to a resident Python MLX worker. App postprocessing and signal gates remain in
Swift. ASR wall time includes transfer and postprocessing; the worker separately
measures its inference time. The app itself and its selected models are unchanged.

## Recognition results

Lower word error rate (WER) is better. Case and punctuation are ignored; numbers,
contractions, abbreviations and regional spelling are not canonicalized.

| Model / runtime | ASR median | ASR p95 | Raw WER, all | Raw WER, original 8 |
| --- | ---: | ---: | ---: | ---: |
| Whisper Turbo 632 MB / Core ML | 606.26 ms | 973.32 ms | 5.50% | 2.34% |
| Parakeet 0.6B v3 / Core ML | 86.22 ms | 133.62 ms | 3.67% | 3.74% |
| Parakeet 0.6B v2 English / Core ML | 85.62 ms | 109.49 ms | 2.71% | 2.34% |
| Parakeet 1.1B / parakeet-mlx frontend | 104.49 ms | 201.60 ms | 2.71% | 2.34% |
| **Parakeet 1.1B / NeMo-style frontend** | **111.29 ms** | **207.30 ms** | **1.83%** | **1.87%** |
| Canary 1B v2 / MLX | 137.93 ms | 303.50 ms | 3.15% | 1.87% |
| Qwen3-ASR 1.7B / MLX | 447.45 ms | 914.62 ms | 3.52% | 2.80% |

The larger Parakeet with the NeMo-style frontend has fewer raw word errors than
Whisper on 31 clips, the same on 45, and more on five. It still does not meet a
strict no-individual-regressions requirement. The English v2 control wins 22,
ties 54 and loses five against Whisper, with a different set of errors.

The principal technical example is `localhost`:

- Whisper and English Parakeet v2 preserve it.
- Parakeet v3 says `local list`.
- Parakeet 1.1B says `localhust`, including with the improved frontend.
- Canary says `localhist`.
- Qwen3-ASR says `local history`.

These are recognition errors distinct from lowercase formatting. Numerical
formatting also affects WER: `two point zero` versus `2.0` is penalized despite
representing the same version. Review the exact outputs alongside aggregate WER.

Whisper returned empty text for one 17-word LibriSpeech clip in both passes
(`librispeech-1272-141231-0030`). Those errors remain in its WER denominator and
numerator; they were not excluded. The app skips the LM for that empty output.

## Why the Parakeet frontend mattered

The same pinned 1.1B weights and decoder were evaluated with two audio frontends.
The installed `parakeet-mlx` frontend differs from MLX Audio's NeMo-style frontend
in FFT magnitude handling, window placement, padding, logarithm guard and
normalization. The latter computes squared complex magnitude, centers the window
and uses sample-variance normalization. No weights were fine-tuned or replaced.

Changing only the frontend reduced raw edits from 74 to 50 across 2,728 repeated
reference words: **2.71% → 1.83% WER**. The first corrected-frontend pilot measured
104.29 ms median; the clean repeat measured 111.29 ms. All four passes produced
identical transcripts. This is an accuracy improvement with broadly similar
latency, not evidence of a precise zero-cost change.

The alternate frontend is retained explicitly as a benchmark configuration.
It is not a change to the installed `parakeet-mlx` package or production app.

## Loading and inference overhead

| Configuration | One process-start load-to-ready observation |
| --- | ---: |
| Whisper | 12,982 ms |
| Parakeet v2 | 242 ms |
| Parakeet v3 | 200 ms |
| Parakeet 1.1B, original frontend | 639 ms |
| Parakeet 1.1B, NeMo-style frontend | 5,413 ms |
| Canary 1B | 2,105 ms |
| Qwen3-ASR 1.7B | 2,718 ms |

These are single startup observations, not repeated cold-disk benchmarks. Files
were already downloaded and cached. Values include runtime/import initialization,
model loading and whatever prewarming the backend performs; they do not isolate
disk I/O. Models remain resident for the subsequent warm calls.

Median wall time outside Python inference is 3.16 ms for original Parakeet 1.1B,
3.35 ms with the alternate frontend, 3.41 ms for Canary and 7.44 ms for Qwen.
These include IPC, serialization, native processing and the worker's small
diagnostic writes. The larger-model speed differences are predominantly inside
inference, not transfer. No larger-model call hit its generation-token limit.

## Full cleanup timing

The unchanged Llama 3.2 1B pass processed all 331 distinct nonempty ASR outputs in
standard, casual and formal styles, twice: 1,986 calls plus 46 unchanged smoke
calls, **2,032 total**. Identical transcripts share the same LM observations.
The 3,402 joined model/clip/style/pass rows are therefore not independent LM calls.
Llama load-to-ready was 761 ms, outside warm timings.

| ASR configuration | LM median: standard / casual / formal | Reconstructed ASR+LM median: standard / casual / formal |
| --- | ---: | ---: |
| Whisper | 303 / 397 / 309 ms | 911 / 1,000 / 915 ms |
| Parakeet v3 | 307 / 386 / 307 ms | 387 / 470 / 388 ms |
| Parakeet v2 English | 309 / 393 / 307 ms | 388 / 476 / 389 ms |
| Parakeet 1.1B, original frontend | 304 / 373 / 317 ms | 414 / 491 / 415 ms |
| **Parakeet 1.1B, NeMo-style frontend** | **304 / 369 / 317 ms** | **422 / 488 / 417 ms** |
| Canary 1B | 310 / 390 / 307 ms | 450 / 525 / 445 ms |
| Qwen3-ASR 1.7B | 311 / 385 / 308 ms | 753 / 836 / 762 ms |

| ASR configuration | Reconstructed ASR+LM p95: standard / casual / formal |
| --- | ---: |
| Whisper | 1,404 / 1,598 / 1,383 ms |
| Parakeet v3 | 597 / 908 / 600 ms |
| Parakeet v2 English | 563 / 892 / 575 ms |
| Parakeet 1.1B, original frontend | 671 / 743 / 682 ms |
| Parakeet 1.1B, NeMo-style frontend | 663 / 748 / 673 ms |
| Canary 1B | 748 / 1,002 / 761 ms |
| Qwen3-ASR 1.7B | 1,393 / 1,660 / 1,399 ms |

Totals add separately measured ASR and LM time for matching clip/output/pass,
then take the distribution. They are not sums of global medians, and are not
live microphone-to-paste timings. Empty Whisper output has zero LM time.
The broad LM corpus uses fixed lexical input order; small cross-model timing
differences are vulnerable to clock/thermal/order drift. A smaller shuffled,
order-reversed control below addresses the specific casing behavior.

The fast ASR models make the LM the larger remaining processing stage. The
earlier [native LM phase profile](2026-09-15-english-latency.md) measured prompt
processing as the dominant component on the shorter smoke corpus. No prompt,
generation budget, validator, retry policy, or model choice was changed here.

## What the LM actually repaired

Lowercase was not penalized in recognition WER. Standard cleanup delivered an
initial capital on 54/81 corrected-frontend Parakeet transcripts; formal did so
on 60/81, in both passes. Lowercase output alone does not establish meaning loss,
but the current pass does not guarantee restoring formatting on every transcript.

The technical errors survived: standard Parakeet 1.1B retained `localhust`, Canary
retained `localhist`, and Qwen retained `local history`. Parakeet and Canary
candidates formatted `two point zero` as `2.0`; the current `new_numbers` validator
rejected those candidates, preserving the original text. English v2 and Whisper
kept the correct `localhost` throughout standard cleanup.

A more serious cleanup failure appeared on the shared lowercase, unpunctuated
short request. Casual mode appended `enjoy you`, and the validator accepted it.
This happened in both broad-sweep observations of that unique input. It affects
multiple audio/model rows because they share that transcript; those duplicate
rows are not independent reproductions.

### Controlled casing and punctuation test

All original dictation outputs plus two added formatting variants produced 27
distinct inputs. They ran in all three styles, three times, with a fixed shuffle
seed and odd rounds reversed. Together with the unchanged smoke suite this is
312 additional calls. The controlled casual-mode results were:

| Input | Delivered output, all three control passes |
| --- | --- |
| `can you send this over when you get a chance` | `can you send this over when you get a chance enjoy you` |
| `Can you send this over when you get a chance` | `can you send this over when you get a chance` |
| `can you send this over when you get a chance?` | `can you send this over when you get a chance` |
| `Can you send this over when you get a chance?` | `can you send this over when you get a chance` |

Thus the unwanted addition reproduced **5/5 actual LM calls** across the two
broad passes and three shuffled controls. A capital initial or question mark
avoided it in all three controlled repetitions. This proves sensitivity on this
input; it does not establish a globally safe capitalization workaround.

Another delivered-output issue affects existing Whisper/v2 as well: casual
fallback changed `version 2.0` to `version 2`. Final WER after cleanup is retained
as a diagnostic in JSON, not a standalone quality grade, because intended filler
removal, contractions and paraphrases also change reference words.

## Validation and decision

- All seven ASR configurations completed both measured passes with stable exact
  outputs. The larger models did not hit generation limits. All pinned downloaded
  weights passed published-checksum verification.
- The main LM smoke passes were 22/23 and 21/23. Both retain the known
  `normal style preserves meaningful like` failure. The second also recorded a
  `generation_failed` fallback on `actually false start removes abandoned article`,
  an intermittent failure also seen in the earlier model sweep; its underlying
  error was not captured by the production result type.
- The shuffled control passed 22/23 existing smoke checks in each repetition,
  retaining only the known meaningful-like mismatch. The new accepted-content
  addition is outside that existing smoke oracle and is explicitly reported here.
- Production sources, tests, package manifests/resolution and model selections
  remain unchanged. Full app unit checks from the earlier report were not rerun
  for benchmark-only changes. New harness builds and the actual model runs
  completed successfully after resolving adapter/dependency setup errors.

Parakeet 1.1B with the NeMo-style frontend is the most promising larger candidate
on this corpus: improved aggregate recognition for roughly 25 ms more ASR time
than English v2. English v2 remains faster and preserves the important `localhost`
example. Neither the recognition results nor the current cleanup behavior prove
a zero-quality-loss replacement. No production default was switched.

## Runtime and integration boundaries

- Parakeet 1.1B uses `parakeet-mlx 0.5.2`, with BF16 model weights loaded from
  the pinned FP32 checkpoint. Audio preprocessing receives FP32 samples, matching
  the runtime's actual file-loading behavior.
- Canary uses `mlx-audio 0.5.4` with the full FP32 `qfuxa/canary-mlx` checkpoint.
  Qwen uses the same runtime with the BF16 MLX community checkpoint. Python MLX
  is 0.32.2; the app's pinned Swift MLX is 0.31.4.
- Canary and Qwen return no word-level confidence in these adapters. The native
  terminal hallucination filter receives an empty timing list. That integration
  gap must be resolved or explicitly accepted before replacing the existing
  engine; a good WER result does not validate that feature.
- Python workers keep ASR allocation caches separate from the Swift LM runtime.
  A native integration may change cache behavior and latency. These are practical
  model/runtime candidates, not completed app integrations.
- All checkpoints are revision-pinned and their downloaded weight hashes match
  the publisher's SHA-256 values. The dependency snapshot and per-run source
  sidecars identify the actual code used.

## Reproduction

See [benchmark README](../../apps/macos/Tools/DictationBenchmark/README.md),
[worker](../../apps/macos/Tools/DictationBenchmark/python-asr-worker.py),
[serial sweep](../../apps/macos/Tools/DictationBenchmark/large-model-sweep.py), and
[comparison generator](../../apps/macos/Tools/DictationBenchmark/summarize-large-models.py).
