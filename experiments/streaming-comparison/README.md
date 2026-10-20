# Streaming transcription comparison

This experiment compares the current production Parakeet TDT 1.1B path with
Hex's Parakeet Unified English 0.6B Q8_0 in batch and buffered streaming modes.
The original standalone benchmark does not change the app or its preferences.
All intermediate transcripts stay in local result files. The later app-integrated
local trial and headless CLI live in [app-trial](app-trial/README.md).

## Fixed inputs and controls

- ShoutOut source: `0800a3e698b9e799ffff0a08525e353464690b6e`.
- Hex source: `083179900e85c1e23bb3a13591957eade092d79e`.
- Hex runtime/model pins and native build instructions: `native-hex/README.md`.
- Current engine: the existing optimized `DictationBenchmark` executable. Its
  recorded original and staged source hashes are checked against current source
  on every run, including all Core files and `Package.resolved`. The binary hash
  is recorded beside each result. Its only Whisper adapter changes are an
  isolated tokenizer cache and explicit default Core ML compute placement.
- Corpus: 180 existing expanded evaluation recordings and 50 conversational
  recordings. One silence recording is rejected by the common production gate.
  Two additional recordings use 20 dB attenuation. There are 231 speech inputs.
- The corpus contains synthesized dictation controls, public natural speech,
  concatenated long speech, noise, late corrections, names, numbers, negation,
  technical terms, and quiet controls. It is an English screening corpus.
- `prepare.py` verifies original hashes and produces shared mono 16 kHz PCM.
  `verify_audio.swift`, compiled with the production `AudioSignalAnalysis`,
  checks exact sample equality, trimming and gate acceptance for all inputs.
- The full corpus measures recognition quality. A fixed 14-clip subset (166.8
  seconds) measures latency across three rounds with engine order reversed in
  the second round. The same 160 ms feed size is used for quality and latency.
  Each latency path gets a common speech warmup, then each clip is measured on
  its first pass. The quality-only current run uses per-file warmup.
- Loading, common capture tails, cleanup, and paste are excluded. Current batch
  timings include its production Whisper verification when triggered, output
  filters and mechanical postprocessing. Hex stream timing includes feed backlog
  and finalization, and stops when text is available. Session rotation is recorded
  separately. These are production path endpoints with a small processing
  difference, rather than identical decoder-only timers.
- The native inference thread uses Hex's user-interactive pthread QoS setting.
  Earlier runs without that setting are retained in `pre-qos-diagnostic/` and
  excluded from the reported latency results. Quality inference is unchanged.
- Unpaced streaming is only a quality test. Its output deliberately has no
  release latency. Paced streaming uses a separate producer so slow inference
  cannot move the release timestamp later and hide work queued at release.

## Decision rule

Prefer the current engine unless a candidate provides a useful reduction in
release-to-final-ASR time while retaining transcription quality. Compare natural
and conversational WER separately, inspect names/numbers/negations/corrections
and final words, and review regressions rather than trusting aggregate WER.
A faster first partial is not a release-latency improvement. A complete batch
rerun on release must be counted in full if used as fallback.

This is a model-and-runtime comparison. Hex batch versus Hex stream compares the
two runtime paths, including Hex's batch-only minimum-length padding and extra
200 ms silence. It is not an isolated algorithm comparison on identical padded
input. Neither establishes the benefit of converting a checkpoint
to another framework. MLX is not required to run the Hex GGUF on Metal.

## Commands

Run from the repository root. Replace the two existing-cache paths with the
matching local corpus and source-verified optimized benchmark build.

```sh
python3 experiments/streaming-comparison/prepare.py \
  --source /path/to/expanded-eval \
  --output experiments/streaming-comparison/.build/fixtures

swiftc -O -parse-as-library \
  apps/macos/Sources/Core/AudioSignalAnalysis.swift \
  experiments/streaming-comparison/verify_audio.swift \
  -o experiments/streaming-comparison/.build/verify-audio

experiments/streaming-comparison/.build/verify-audio \
  experiments/streaming-comparison/.build/fixtures/quality-manifest.json

python3 experiments/streaming-comparison/run_current.py \
  --cached-macos /path/to/source-matched/apps/macos \
  --manifest experiments/streaming-comparison/.build/fixtures/quality-manifest.json \
  --output experiments/streaming-comparison/.build/results/current-quality.json

python3 experiments/streaming-comparison/setup_scoring.py

python3 experiments/streaming-comparison/run_latency.py \
  --cached-macos /path/to/source-matched/apps/macos

python3 experiments/streaming-comparison/summarize.py \
  --fixtures experiments/streaming-comparison/.build/fixtures \
  --results experiments/streaming-comparison/.build/results
```

The summary requires `current-quality.json`, `hex-batch-quality.jsonl`, and
`hex-stream-quality.jsonl`. Latency files use `current-latency-N.json`,
`hex-batch-latency-N.jsonl`, and `hex-stream-latency-N.jsonl`. Results include
machine-readable observations and an HTML table with references and all three
transcripts for review. Scratch data, model weights, binaries and transcripts
are ignored by Git.

Word error rate ignores case and punctuation. Numeric formatting and equivalent
word forms can still count as errors. A secondary score uses the standard OpenAI
Whisper English normalizer, pinned by `setup_scoring.py`, on both reference and
model text. Both scores are retained; no transcript is edited for scoring.
Long concatenated recordings reuse source
speech, so their category is reported separately. Phrase-preservation checks
are narrow diagnostics and require human review of equivalent wording.
