# Local streaming trial, 2026-10-19

The streaming trial reduced release-to-cleaned-text latency on this generated
audio set. Quality was mixed, so current Parakeet remains the default. The local
flag supports a live comparison before making a replacement decision.

The later 231-clip app replay, below, supports trying the 0.6B model live before
spending time on a new 1.1B runtime. Its average error gap is small on this corpus.
Known-term dictionary aliases can help specific spellings; unchanged cleanup
does not reliably repair recognition mistakes.

| Metric | Current Parakeet | Hex streaming |
| --- | ---: | ---: |
| Median release to final ASR | 165 ms | 143 ms |
| Median release to cleaned-text sink | 491 ms | 351 ms |
| p95 release to cleaned-text sink | 1,915 ms | 860 ms |
| 46-second paragraph, median release to cleaned-text sink | 1,915 ms | 734 ms |
| Normalized raw-ASR WER | 2.86% (19/665) | 6.17% (41/665) |

The later [same-model batch/streaming audit](HEX_MODES.md) found Hex batch at
5.71% standard WER. Much of the apparent gap is formatting. With four explicit
format equivalences, diagnostic WER is 2.86% current, 2.56% Hex batch, and 3.61%
Hex streaming. Use that audit when interpreting the quality row above.

There are 23 quality fixtures: 22 speech clips and one silence control. Both
engines completed every speech clip and rejected silence. The paced panel has
seven speech clips and silence repeated three times, with an unscored warmup
per run. Timed transcripts matched the corresponding unpaced transcripts.

The short negation case was slower with streaming: 353 vs 332 ms to the sink.
The “thank you” case invoked the existing Whisper verifier in both paths and
took about 0.8–0.9 seconds. Improvements on the long paragraph include cleanup
costs on different ASR outputs; the whole saving cannot be assigned to streaming.

WER uses the pinned standard Whisper English normalizer. Date/time, filename,
and URL formatting still create some equivalent-word penalties. There are also
real name errors: Hex rendered “Maya Chen” as “Mayochen” in a paragraph. Hex did
better on “Siobhan” and “sapphire”. Both retained the main negations and
self-corrections. Quiet/noisy versions reuse two paragraphs, so those errors
repeat in the aggregate. References are intended TTS text, not human-verified
phonetic transcripts. These are screening results, not a broad quality claim.

The replay includes production sample collection, stream ordering, shared
trim/speech gates, ASR filtering, and the existing standard cleanup policy. It
simulates the 80 ms capture tail and saves text locally. It excludes a physical
microphone, resampling, hotkey events, accessibility insertion, and energy use.

Provenance:

- App base: `25cdef226359` plus the local streaming/replay implementation.
- Current ASR: MLX Parakeet TDT 1.1B BF16, revision
  `a48da3b2e1aa436c4077acb978bb3a2b65fd1b45`.
- Hex reference: `083179900e85c1e23bb3a13591957eade092d79e`.
- Candidate: Parakeet Unified English 0.6B Q8_0, revision
  `7e948f21b7bdbac698d3318db9d350f1096f3b6c`, `transcribe-cpp=0.2.4`, Metal.
- Cleanup: existing `mlx-community/Llama-3.2-1B-Instruct-4bit`, standard style.
- Frozen fixture manifest SHA-256:
  `3e9cdf3cda34c5c17dd8e963ba37ffd989509fc67ceefd0dae2210995b8ca58b`.
- Benchmark executable SHA-256:
  `e0d05d28835fb63a4e981856d4ecb59465d0ff6c4cd4fc578fa865c26c0d80a2`.

The subsequent CLI and preference-isolation changes did not change ASR or
cleanup inference. Their packaged smoke checks are separate from the frozen
latency run. Raw results, logs, and `comparison.html` are local ignored files.

## Larger replay with the existing cleanup pipeline

Both packaged app paths replayed the same 231 frozen speech clips: 50 public
conversational utterances, 120 LibriSpeech utterances, and 61 generated or derived
dictation, long-form, noise, trailing-silence, and quiet controls. The audio totals
53.1 minutes. Long/noise/quiet variants reuse source speech, so the clips are not
231 independent speakers or utterances. Each run also used an unscored warmup
and rejected the silence control.

The actual production collector, stream queue, speech gates, ASR filters,
mechanical processing, and unchanged Llama 3.2 1B cleanup in standard style were
used. Both sides had no custom dictionary entries. User preferences, microphone,
history, and text insertion were not used. These were unpaced quality runs;
their timing fields are not measurements of release latency.

| Score | Current Parakeet 1.1B | Hex streaming 0.6B |
| --- | ---: | ---: |
| Raw normalized WER, all 231 | 2.19% (181/8,249) | 2.33% (192/8,249) |
| Final lexical WER, all 231 | 2.57% (212/8,249) | 2.84% (234/8,249) |
| Raw WER, conversational subset | 2.81% | 1.69% |
| Final lexical WER, conversational subset | 3.86% | 3.05% |

Final lexical WER counts valid cleanup rewrites, removal of repetitions, spoken
command expansion, and remaining numeric-format differences. It is a diagnostic
alongside paired text review, not a count of required user corrections. There
were 22 more scored edits in streaming's final text across 8,249 reference words.
Streaming had fewer final scored edits on 25 clips, the same count on 167, and
more on 39. Those counts do not assign semantic severity to the edits.

Review of all 40 dictation, six noise, and three trailing controls found the
tested negations, number values, final corrections, and short yes/no/stop commands
retained. One noisy tail changed “final words” to “final word”. Familiar hostname
and identifier errors remain in both paths. Numeric formatting often explains
the larger WER deltas on the controls.

Concrete paired cases:

- `conversation-d16d08e1-0335-db1e-8604-bbb416aac8bf`: streaming hears “precisely”
  as “Presley”. The time remains correct. Cleanup rejects its candidate and
  leaves the misheard word unchanged.
- `dictation-samantha-request`: streaming ASR and mechanical text correctly say
  “Can you send this over…”. Accepted cleanup drops “Can you”. Current cleanup
  also changes the request slightly, from “this” to “it”.
- `conversation-f948d20f-d3e2-4b18-ab5e-241588700b69`: streaming ASR omits the
  initial “to”; accepted cleanup adds an unsupported repeated phrase, “actually
  I was really excited”. Current output does not add that phrase.
- The largest reviewed literary regressions are word/name substitutions such
  as “another purse” to “another person”, and “rank and grades” to “ranking
  grates”. The reviewed worst cases did not show broad truncation or lost
  negations. Archaic wording and names create reference uncertainty.

The dictionary core was tested separately with configured aliases. It correctly
replaces `Mayochen` with `Maya Chen`, `post-GurSQL` with `PostgreSQL`, and `Siobhan
Mackenzie` with `Siobhan McKenzie`. This demonstrates literal replacement only;
the aliases were excluded from corpus scores and their full cleanup interaction
was not evaluated. They do not recover omitted words, add a missing currency
unit, or resolve arbitrary contextual mishearings.

This evidence supports a local opt-in live trial of 0.6B. A 1.1B backend rewrite
is not justified before measuring the frequency and importance of live
corrections. The speed benefit is largest on longer dictations; the earlier
paced panel's median saving was about 140 ms and the 46-second passage saved
about 1.18 seconds. Physical microphone and insertion behavior remain for the
user-run trial.

Reproduce after building the local app and preparing the frozen larger corpus:

```sh
python3 experiments/streaming-comparison/app-trial/run_broader.py
swiftc -O -parse-as-library \
  apps/macos/Sources/Core/TextPostProcessor.swift \
  apps/macos/Sources/Core/DictionaryEntry.swift \
  apps/macos/Sources/Core/DictionaryReplacer.swift \
  experiments/streaming-comparison/app-trial/pipeline_probe.swift \
  -o experiments/streaming-comparison/app-trial/results/broader/pipeline-probe
python3 experiments/streaming-comparison/app-trial/summarize_broader.py
```

Raw output, exact intermediate mechanical text, per-case errors, narrow authored
phrase checks, source hashes, and binary provenance are local ignored files in
`results/broader/`. Phrase checks are diagnostic; equivalent paraphrases require
manual review. References are publisher-provided or intended TTS text, not
independently retranscribed here.
