# English transcription replacement: expanded evaluation

## Decision

Make **native Parakeet TDT 1.1B (MLX, BF16)** the default English backend and Best preset. Keep WhisperKit selectable, preserve explicitly saved engine preferences, and retain Whisper Turbo as a resident verifier for terminal phrases that require word timings. The language model remains Llama 3.2 1B 4-bit with the same prompts and generation settings.

This meets the frozen aggregate quality and speed gate; it is **not a claim that every transcription improves**. Technical spelling remains a tradeoff, and the conversational holdout shows near-equal accuracy rather than a universal advantage. At evaluation time, the change was confined to the repository; the installed app, release, and user preferences were not modified.

[Search all outputs](2026-09-15-expanded-models.html) · [Summary and provenance](2026-09-15-expanded-models.json) · [All observations (gzip JSON)](2026-09-15-expanded-models-observations.json.gz) · [Frozen acceptance gate](2026-09-15-expanded-gate.md)

## Setup

- Apple M3 Max, 128 GB RAM. Models run serially on the same machine. Results do not establish performance or memory suitability on smaller Macs.
- Expanded set: **179 speech recordings plus silence**, 0.947–204.02 seconds, 45.47 minutes including the silence fixture. Includes 120 utterances from 40 LibriSpeech speakers, eight concatenated long recordings, 40 two-voice synthetic dictations, two continuous long synthetic dictations, six noise variants, and three trailing-silence variants.
- Separate conversational holdout: **50 seeded samples**, 2.77–16 seconds, from the publisher's frozen transcription benchmark. References are publisher-provided, not independently relabeled here.
- Retest of the prior 81 speech fixtures, plus a 14-speech/one-silence production integration set with deliberately spoken and unspoken terminal-phrase controls.
- Each ASR file runs three times: first-file measurement, then two repeats. Tables use the two repeats. These are resident-model measurements, **not cold process starts**. Repetitions are not independent speakers or new recordings.
- Natural long recordings concatenate utterances; this stresses duration but does not establish quality on spontaneous multi-minute conversation. Some stress recordings reuse source audio. WER ignores case and punctuation but still penalizes equivalent number spellings, acronym spacing, and contractions.
- Expanded ASR order: v2, Whisper, Python 1.1B, Canary; native and chunked variants followed. Conversational order: Canary, Python 1.1B, Whisper, v2, native. Fixed order and one machine limit timing generalization.

## Recognition quality and speed

Warm medians; lower word error rate (WER) is better. Expanded WER denominator is 13,948 reference words across two repeats (6,974 unique fixture words). Conversation denominator is 2,442 across two repeats.

| Configuration | Expanded ASR median / p95 | Expanded WER | Conversation ASR median | Conversation WER |
|---|---:|---:|---:|---:|
| Whisper Turbo 632 MB | 557 / 2,883 ms | 3.97% | 709 ms | 3.81% |
| Parakeet English v2 0.6B, Core ML | 81 / 243 ms | 3.63% | 89 ms | 3.03% |
| Parakeet 1.1B, Python + NeMo frontend | 113 / 621 ms | 2.14% | 143 ms | 3.69% |
| **Parakeet 1.1B, native Swift** | **57 / 362 ms** | **2.15%** | **82 ms** | **3.77%** |
| Canary 1B, whole-file adapter | 139 / 852 ms | 29.31% | 204 ms | 2.78% |
| Canary 1B, quiet-boundary chunks | 127 / 1,057 ms | 3.97% | Same short-audio path¹ | 2.78%¹ |

¹ Conversation clips are all below the 24-second chunking threshold; these are the measured unchunked short-audio results, not a separately repeated chunked holdout.

The Canary adapter originally sent entire files through a short-context decoder. It omitted/repeated substantial content on long audio. Splitting at the quietest 100 ms interval between 15 and 24 seconds, retaining all samples, fixed that failure: no chunk reached the 1,024-token cap. Thus the original long-file result was an adapter limitation, not a fair standalone measure of Canary's capability.

Native 1.1B reproduced 531/537 Python transcripts exactly on the expanded set. The two differing clips involve `million'd`/`millioned` and a rare name spelling. On the prior 81-fixture set, native raw WER was **1.91% versus the recorded Whisper control's 5.50%**; Whisper has two prior repeats, native three, so compare rates rather than raw error counts. Native returned no empty speech transcripts. Whisper returned empty output on both sub-second “Stop the recording” voices in the expanded set.

### Short and long recordings

Each cell is median ASR time / raw WER. Counts are unique speech fixtures; two repeats contribute timing and WER.

| Audio duration | Clips | Whisper | v2 0.6B | Native 1.1B | Canary chunked |
|---|---:|---:|---:|---:|---:|
| <5 seconds | 85 | 465 ms / 12.67% | 73 ms / 11.72% | **40 ms / 6.95%** | 75 ms / 11.58% |
| 5–30 seconds | 77 | 760 ms / 3.14% | 92 ms / 3.07% | **79 ms / 1.87%** | 219 ms / 3.53% |
| 30–90 seconds | 12 | 1,920 ms / 3.36% | 176 ms / 3.13% | **216 ms / 1.33%** | 642 ms / 3.44% |
| 90–204 seconds | 5 | 9,171 ms / 2.44% | 577 ms / 1.88% | **1,256 ms / 1.36%** | 3,432 ms / 2.25% |

The 1.1B candidate clears the quality thresholds in every duration group. v2 is faster on long clips but consistently lost the final words of two natural utterances: “of an amphitheater” and “Montrose to escape him.” Native 1.1B retained both, including through the language pass. High v2 word confidence did not flag those omissions reliably.

### Reconstructed latency across the expanded set

Separate ASR and LM stage measurements, joined by exact transcript and repetition. Each row covers 358 warm ASR calls; Whisper's four empty calls retain their ASR time and have zero LM time. These are not consecutive pipeline measurements.

| Configuration | Standard | Casual | Formal |
|---|---:|---:|---:|
| Whisper | 822 ms | 915 ms | 830 ms |
| v2 0.6B | 358 ms | 418 ms | 358 ms |
| Python 1.1B | 374 ms | 427 ms | 383 ms |
| **Native 1.1B** | **323 ms** | **375 ms** | **329 ms** |
| Canary chunked | 409 ms | 463 ms | 399 ms |

## Actual ASR → language-pass integration

These measurements run production services consecutively with both models resident, using the user's casual style. They include 14 speech fixtures × two warm repeats, including the baseline's empty transcription, long recordings, and verification controls. They exclude microphone capture, file decoding, paste, and UI work.

| Stage | Whisper | Integrated native 1.1B |
|---|---:|---:|
| ASR median | 523 ms | 54 ms |
| Language-pass median | 199 ms | 195 ms |
| **Combined median** | **726 ms** | **254 ms (65% lower)** |
| Combined p95 | 8,690 ms | 3,637 ms |
| Cached model preparation, single observation | 6.19 s | 6.90 s |

Stage medians do not sum to the combined median. Whisper produced no text for the sub-second stop request; its near-zero pipeline time remains in the denominator. The candidate transcribed it successfully.

Selected first warm repeat:

| Recording | Whisper combined | Native combined |
|---|---:|---:|
| Short negation/instructions | 805 ms | 253 ms |
| Short ordinary request | 659 ms | 230 ms |
| 118-second continuous dictation | 7.91 s | 1.60 s |
| 204-second natural concatenation | 8.69 s | 3.66 s |
| Spoken terminal “thank you” | 616 ms | 649 ms |
| Paused but spoken terminal “thank you” | 635 ms | 679 ms |

The last two intentionally invoke Whisper verification and preserve the spoken words. The unspoken-ending control returned only the actual sentence. The native API does not expose word confidence; the integration does not fabricate it or bypass the existing terminal-silence filter.

**Latency explanation:** warm LM time is generation/validation, not loading weights for each request. The measured standalone LM preparation was about 0.7 seconds with cached files. Models remain resident. This change reduces ASR inference; it does not materially reduce LM latency or cold startup. Native-only prototype preparation (~315 ms) is not the integrated app startup because the final engine also loads Whisper.

Memory is a cost: the pipeline's maximum observed MLX allocation was **6.67 GiB**, versus 1.27 GiB for the Whisper+LM control's MLX portion. These counters exclude Core ML and other process memory. Native+LM active MLX memory reached 2.68 GiB. Model download is about 5 GB including the verifier. The smaller Whisper preset remains available and is now labeled “Smaller,” rather than implying it beats native inference speed on this machine.

## Output quality and LM checks

- All three language styles are evaluated on every distinct transcript, reusing identical inputs explicitly. The expanded, followup, and chunked sweeps total **4,404 measured LM calls**, including their smoke controls; integration calls are separate. Full outputs, fallbacks, sources, and repetitions are in the compressed observations JSON.
- The existing **meaningful “like” smoke case still fails**. Other smoke cases pass in both repeats; this is the same pre-existing failure, not a clean 23/23 result.
- Long transcripts sometimes hit the existing LM generation budget and use the existing safe fallback. The main expanded sweep recorded 62 no-candidate calls across both repeats. Lowercasing itself is not scored as an ASR error.
- A narrow validator change rejects unsupported suffixes appended to an otherwise verbatim transcript. Actual Swift replay of **5,405 recorded candidates** changed 13 results, all manually reviewed as improvements; 5,392 stayed identical. Original-validator replay reproduced every recorded candidate decision. The 63 no-candidate cases were excluded from that replay denominator. Revalidation is not presented as additional model generation.
- Examples prevented: `can you send this over when you get a chance enjoy you`, and adding `a decision` or `a move` after “strongly but slimly made.” Existing politeness allowances remain tested.

### Remaining individual tradeoffs

- Whisper correctly spelled `localhost` in clean technical dictation; native produced `localhust`/`localhurst`. The LM did not repair it. Identifier spellings can remain spoken out (`user underscore id`, `config json`). No speculative dictionary correction was added.
- Conversational native errors include “new departure time” → “noob departure time” and “the teenagers” → “a teenager.” Conversely, it preserved “can't figure out” where Whisper returned “can figure out.” Aggregate equivalence is not per-sentence equivalence.
- The existing casual mechanical fallback removes punctuation inside numeric strings: e.g. `2.0` → `2`, and `$1,250.50` → `$125050`. This behavior predates the replacement and its existing test explicitly expects version punctuation removal. It was not changed here. Native's spelled-out numbers avoid those specific examples, but that does not fix the general normalizer issue.
- Canary retained a raw amount/cents error in an authored dictation case; chunking addresses context length, not that short-clip recognition error.

## Implementation and validation

- Pinned `mlx-audio-swift` to `3e978558404df4ad1bbb0a5634a03df2b0f9dfa5`; `mlx-community/parakeet-tdt-1.1b` to `a48da3b2e1aa436c4077acb978bb3a2b65fd1b45`. Runtime casts weights to BF16, matching the tested native path. Swift 6.2+ is required; macOS target remains 15.
- Shared default backend, Best preset, permission policy, and backend selection use Parakeet. Saved explicit backend choices remain intact. The native engine runs outside the main actor and checks cancellation before/after generation.
- Existing signal gating, trailing-silence trimming, filler removal, terminal filtering, LM validation, and fallback paths remain. Narrow terminal candidates re-run through resident Whisper to supply its real word timing/confidence.
- **Validation: PASS — 143 XCTest tests, 20 Swift Testing tests, 312 script checks, debug app build, and final release app build.** The isolated production-engine release build and consecutive pipeline measurements also passed. Artifact checks verified 3,972 expanded/holdout ASR observations, 7,944 joined style outputs, and no missing LM inputs. GUI installation, microphone-to-paste behavior, and release deployment were not performed.

## Reproduction and provenance

Harnesses live in `apps/macos/Tools/DictationBenchmark/`: expanded/holdout fixture preparation, sweeps, Python and Swift adapters, validator replay, and final export. Raw local artifacts are under `apps/macos/.build/expanded-eval/`; the portable summary retains source hashes, dependency locks where captured, and fixture references/hashes; the compressed JSON retains every measured output. Model binaries and audio are not added to Git.

Sources: [LibriSpeech dataset](https://huggingface.co/datasets/openslr/librispeech_asr), [Pipecat transcription benchmark data](https://huggingface.co/datasets/pipecat-ai/stt-benchmark-data), [native Parakeet implementation](https://github.com/Blaizzy/mlx-audio-swift/blob/main/Sources/MLXAudioSTT/Models/Parakeet/README.md). Dataset revisions and verified parquet SHA-256 values are embedded in provenance. Pipecat sample IDs were sorted and selected with seed 20260916 before candidate inference.
