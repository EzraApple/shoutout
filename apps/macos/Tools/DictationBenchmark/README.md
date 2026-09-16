# Dictation benchmark

Runs release builds of the production transcription and language-pass services on
fixed inputs. It does not launch the app, record the microphone, paste text, or
write app history. Its standalone executable has its own preferences domain;
model files are reused from ShoutOut's Application Support directory.

## Run

From the repository root:

```sh
# Builds MLX's Metal runtime and runs the existing 23-case cleanup smoke suite.
bash apps/macos/scripts/run-language-pass-smoke.sh

python3 apps/macos/Tools/DictationBenchmark/prepare-fixtures.py \
  apps/macos/.build/dictation-audio

python3 apps/macos/Tools/DictationBenchmark/run.py \
  --output apps/macos/.build/benchmark.json \
  --audio-manifest apps/macos/.build/dictation-audio/manifest.json \
  --repetitions 5 --cache-mib 0,2,8,32

python3 apps/macos/Tools/DictationBenchmark/summarize.py \
  apps/macos/.build/benchmark.json

# Compare Whisper compute placement without running the cleanup corpus again.
python3 apps/macos/Tools/DictationBenchmark/run.py \
  --output apps/macos/.build/compute-benchmark.json \
  --audio-manifest apps/macos/.build/dictation-audio/manifest.json \
  --repetitions 3 --audio-only \
  --compute-profiles default,encoder-gpu,decoder-gpu
```

The first command may report existing smoke failures while still successfully
building the Metal runtime. Keep those failures as the baseline; do not change
expectations to make an optimization pass.

`run.py` stages production service sources, the core library, and the existing
smoke corpus into an isolated SwiftPM package under `.build`. It reuses the
checkout's pinned dependencies and build cache. Run builds sequentially. The
generated source-hash sidecar identifies the production service versions used.
The storage override gives Whisper a tokenizer cache under `.build` instead of
the library's default Documents location, avoiding cloud-backed file reads. This
does not change tokenization or decoding, and model loading is outside timing.
The compute profile explicitly chooses the encoder/decoder device for the ASR
experiment. `default` preserves the existing CPU/Neural Engine placement.

## What is measured

- Whisper Turbo 632 MB by default, matching the motivating runtime logs. `--model`
  can select another existing ShoutOut Whisper model.
- Five synthesized speech clips with two voices, short/long instructions,
  technical language, fillers, and corrections; one natural JFK speech sample
  from OpenAI Whisper; noisy and trailing-silence variants; a silence control.
- The same audio files and references are reused for every repetition. The
  manifest includes provenance and SHA-256 hashes. A custom manifest can point
  to other audio files with `name`, `path`, and `reference` fields.
- Audio loading happens before timing. Production silence trimming, speech gating,
  transcription, postprocessing, and hallucination filtering run on those files.
- Each speech transcript also runs through production cleanup in all three styles,
  alongside the unchanged smoke inputs and expectations.
- Cleanup timings include the production timeout, retry, validation, fallback,
  and cache-clear paths. Policy order rotates between cases and repetitions.
- Candidate text, final text, acceptance, fallback reason, and smoke failures are
  compared against the matched zero-cache run. No quality threshold is weakened.
- Each policy gets an untimed warmup. Peak active MLX memory and idle allocation
  cache are recorded. MLX peak active memory excludes cached buffers and other
  runtimes such as Core ML; it is not total process memory.
- ASR compute profiles run sequentially, with a warmup for each fixture. Compare
  transcript differences and WER as well as latency; device changes can affect
  numerical results even with identical model weights.

ASR and cleanup are timed separately. This is not a microphone-to-visible-paste
benchmark. Synthesized speech and one natural sample do not establish accuracy
across speakers, accents, languages, or real-world recording conditions. The
word-error metric ignores case and punctuation; exact output comparisons retain
both. Run without other GPU-heavy workloads for useful latency comparisons.

## Compare replacement models

The replacement-model experiment keeps production sources and app settings
unchanged. Candidate weights live under `.build/model-candidates`. The default
Llama model must already be downloaded by ShoutOut. MLX snapshots are pinned in
`prepare-models.py`; its provenance JSON records hashes for every downloaded file.

After preparing and running the original audio benchmark above:

```sh
python3 apps/macos/Tools/DictationBenchmark/prepare-models.py \
  apps/macos/.build/model-candidates

# Requires pyarrow in the Python environment.
python3 apps/macos/Tools/DictationBenchmark/prepare-model-fixtures.py \
  apps/macos/.build/dictation-audio apps/macos/.build/benchmark.json

git clone https://github.com/FluidInference/FluidAudio.git \
  apps/macos/.build/FluidAudio-model-benchmark
git -C apps/macos/.build/FluidAudio-model-benchmark checkout \
  b68f484789d81fda21efbf81e2ca9fcfd9dc22aa

python3 apps/macos/Tools/DictationBenchmark/run.py \
  --fluid-audio apps/macos/.build/FluidAudio-model-benchmark \
  --output apps/macos/.build/model-build-check.json --cache-mib 0 --repetitions 1

python3 apps/macos/Tools/DictationBenchmark/model-sweep.py \
  --kind lm --output-directory apps/macos/.build/model-comparison
python3 apps/macos/Tools/DictationBenchmark/model-sweep.py \
  --kind asr --output-directory apps/macos/.build/model-comparison
# Follow up with the newer encoder export of the same Parakeet v3 model.
python3 apps/macos/Tools/DictationBenchmark/model-sweep.py \
  --kind asr-v2 --output-directory apps/macos/.build/model-comparison
python3 apps/macos/Tools/DictationBenchmark/summarize-models.py \
  apps/macos/.build/model-comparison
python3 apps/macos/Tools/DictationBenchmark/export-model-results.py \
  apps/macos/.build/model-comparison \
  docs/benchmarks/model-comparison-results.json
```

Finish model downloads before timing. Run the two sweeps sequentially. The LM
sweep rotates model order across three rounds; the ASR sweep reverses engine
order across two rounds, each with two measured runs and a warmup per file.

`ModelConfiguration.swift` removes only the Llama identity sentence for candidate
models, loads their own tokenizer/chat template, and explicitly disables Qwen
thinking. Cleanup rules, examples, generation budgets, temperature, retries,
validator, and fallback behavior stay fixed. Additional audio-derived LM inputs
are frozen from the same Whisper baseline for all models. Six stress inputs run
in all three styles. These have reviewable outputs, not added smoke assertions.

`ParakeetEngine.swift` is an isolated adapter to the existing transcription service.
It uses FluidAudio v3 defaults and a fresh decoder state per request. The default
`.int8` option actually loads the historical mixed 6-bit LUT/FP16 encoder export;
`--parakeet-encoder int8-v2` selects the newer per-channel int8 export. The follow-up
sweep runs after the counterbalanced baseline sweep and is reported separately.
It supplies word timings and averaged token confidence to the existing terminal
hallucination filter. Confidence calibration across engines remains unverified.
The added LibriSpeech dummy corpus contains 73 clips from one speaker; this is an
English screening benchmark, not proof of multilingual or broad-speaker parity.

Model comparisons intentionally retain different outputs for review rather than
requiring byte equality. Inspect existing smoke failures, useful cleanup vs.
fallback rates, and individual ASR regressions alongside median/p95 latency and
aggregate WER. Faster fallback is not a successful cleanup improvement.

## English-only Parakeet and LM phase profiling

`--parakeet-version v2` selects the English-only model; the default `v3` is
multilingual. This is independent of `--parakeet-encoder int8-v2`, which chooses
a newer encoder export for v3. Encoder precision selection is ignored by v2.

```sh
python3 apps/macos/Tools/DictationBenchmark/run.py \
  --output apps/macos/.build/model-comparison/parakeet-english-v2-0.json \
  --fluid-audio apps/macos/.build/FluidAudio-model-benchmark \
  --asr parakeet --parakeet-version v2 --audio-only \
  --audio-manifest apps/macos/.build/dictation-audio/model-manifest.json \
  --cache-mib 0 --repetitions 2

# Run separately: rebuilds the staged package without FluidAudio.
python3 apps/macos/Tools/DictationBenchmark/profile-lm.py
```

The LM profiler replaces only the staged `ChatSession.respond` calls with the
same chunk concatenation through `streamDetails`, retaining MLX's native timing
report. It runs the unchanged 23 smoke cases three times. Model load and warmup
are excluded. `promptMs` includes prefill through the first token; `decodeMs`
covers subsequent generation. The remainder includes template/tokenization,
scheduling, validation and instrumentation. Retry time overlaps these stages.
The sidecar `.phases.json` includes only completed streams; verify 69 initial
entries and account for any missing timing reports before computing shares.
File writes add small instrumentation overhead outside the recorded session
time but inside service time. This diagnostic is not a direct speed comparison
against a different corpus or an earlier machine temperature state.

## Larger ASR models through the full cleanup pass

```sh
uv venv --python 3.12 apps/macos/.build/asr-python-env
uv pip install --python apps/macos/.build/asr-python-env/bin/python \
  -r apps/macos/Tools/DictationBenchmark/large-asr-requirements.txt
python3 apps/macos/Tools/DictationBenchmark/prepare-large-models.py
python3 apps/macos/Tools/DictationBenchmark/large-model-sweep.py
python3 apps/macos/Tools/DictationBenchmark/case-control.py
python3 apps/macos/Tools/DictationBenchmark/summarize-large-models.py \
  apps/macos/.build/large-model-comparison
```

Preparation downloads about 12 GB of pinned Parakeet 1.1B, Canary 1B v2 and
Qwen3-ASR 1.7B checkpoints. It resumes partial downloads and verifies published
SHA-256 checksums. All dependencies/models remain inside the benchmark workspace.

The benchmark-only Swift adapter starts one resident Python worker per ASR run.
The worker receives the same native trimmed float samples used by Whisper and
Core ML Parakeet. Loading is timed separately; warm ASR wall time includes IPC
and native processing, while `inferenceMs` excludes the transfer. Worker JSONL
sidecars record token counts, token-limit hits and Python MLX memory. They include
one warmup followed by two measured requests per speech fixture, in manifest
order. Missing timing/confidence for Canary and Qwen is retained as an integration
limitation, not replaced with invented confidence values. Parakeet token timing
is grouped into words with mean token confidence for the native terminal filter.

The serial sweep repeats all 81 speech clips twice for each larger candidate and
fresh Whisper/Parakeet v2/v3 controls. Silence is checked by the native gate.
Every distinct resulting transcript then runs twice through the unchanged Llama
pass in all three styles, alongside the existing smoke suite. Shared transcripts
share cleanup measurements. The HTML report shows the first measured pass; JSON
retains both. Reconstructed ASR+LM totals add matched separate stage measurements
and do not include microphone capture, app scheduling, or paste. Final WER after
cleanup is diagnostic: expected filler removal and paraphrases can increase it.

Parakeet's Python runtime loads its FP32 checkpoint as BF16 by default. Qwen's
checkpoint is BF16. Canary uses its full FP32 checkpoint and the MLX runtime's
default preprocessing. These are model-and-runtime comparisons, not isolated
parameter-count experiments. Python MLX and the app's Swift MLX versions differ;
see the saved requirements and source-hash sidecars.

The sweep includes `parakeet-1.1b-nemo-mel`, which uses the same weights and
decoder with MLX Audio's NeMo-style audio frontend. The original frontend remains
a separate control; neither configuration patches the installed package.

The casing control reuses distinct original dictation transcripts, adds isolated
capitalization/punctuation variants, and runs all three cleanup styles three
times. A fixed shuffle and reversed odd rounds reduce order confounding. Its
results are separate from the broad sweep and included in the exported JSON.

## Expanded replacement evaluation

`prepare-expanded-fixtures.py` uses the pinned LibriSpeech test-clean parquet in
`.build/expanded-eval/test-clean.parquet`. It freezes three duration-ranked clips
per speaker, concatenated long recordings, and new deterministic dictation/noise
fixtures. `expanded-sweep.py` measures the three leading candidates plus Whisper,
then every distinct transcript through all cleanup styles. The acceptance criteria
are recorded in `docs/benchmarks/2026-09-15-expanded-gate.md` before inference.

`--measure-first-pass` includes each file's first transcription rather than
performing an untimed per-file warmup; repetitions 1 and 2 are immediate warm
repeats. This does not measure repeated cold starts. `--pipeline-style casual`
keeps ASR and LM resident and runs them consecutively per recording, measuring
processing through cleanup with the app's real cache behavior. It excludes
microphone capture and paste.

`prepare-conversation-holdout.py` freezes 50 seeded samples from Pipecat's published
benchmark parquet in `.build/expanded-eval/pipecat.parquet`. Publisher references
are retained; they are not newly human-transcribed here. `expanded-followup.py`
tests the native Swift 1.1B runtime, records v2 confidence diagnostics, runs this
holdout in a different model order, and processes additional distinct LM inputs.

For diagnostics, `BENCH_PARAKEET_METRICS` writes word confidence/timing JSONL.
`BENCH_PARAKEET_NO_MEL_CONTEXT=1` and `BENCH_PARAKEET_PADDING_SAMPLES` expose
separately labeled frontend/chunk-boundary experiments; neither changes the app.
`ValidatorReplay.swift` reapplies the actual validator and fallback policy to
recorded candidates, so a validator-only change can be checked without changing
model generations. Compile against both original and proposed Core sources;
the unchanged control must exactly reproduce recorded results.

The final native backend can be measured directly, including its resident Whisper
verification path:

```sh
python3 apps/macos/Tools/DictationBenchmark/run.py \
  --asr production-parakeet --pipeline-style casual \
  --audio-manifest apps/macos/.build/expanded-eval/audio/pipeline-manifest.json \
  --output apps/macos/.build/expanded-eval/pipeline-native.json \
  --cache-mib 0 --repetitions 3 --measure-first-pass

python3 apps/macos/Tools/DictationBenchmark/run.py \
  --skip-build --asr python --python-model canary-1b-chunked --audio-only \
  --audio-manifest apps/macos/.build/expanded-eval/audio/manifest.json \
  --output apps/macos/.build/expanded-eval/canary-1b-chunked.json \
  --cache-mib 0 --repetitions 3 --measure-first-pass

PYTHONDONTWRITEBYTECODE=1 python3 \
  apps/macos/Tools/DictationBenchmark/summarize-final-evaluation.py
```

`--model-root` can isolate transcription storage for production-engine benchmarks.
The production pipeline loads the pinned Parakeet checkpoint and Whisper verifier;
its preparation time must not be confused with the prototype's native-only load.
Canary chunking retains every sample and splits at quiet boundaries between 15
and 24 seconds. It is a benchmark adapter, not a selectable production backend.
The final exporter expects the complete expanded, conversational, prior-corpus,
validator replay, and pipeline artifacts. It writes a standalone searchable HTML,
a summary JSON, and lossless gzip JSON containing all observations.
