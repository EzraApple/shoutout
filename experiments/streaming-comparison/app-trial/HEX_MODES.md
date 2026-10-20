# Hex batch versus streaming, 2026-10-19

The first WER comparison mixed a different model with a different inference mode.
Current ShoutOut uses Parakeet TDT 1.1B BF16 through MLX. Hex uses Parakeet Unified
English 0.6B Q8_0 through transcribe.cpp/Metal. These are different checkpoints
within the Parakeet family.

## Same-model comparison

| Path | Standard WER | Errors / reference words |
| --- | ---: | ---: |
| Current Parakeet | 2.86% | 19 / 665 |
| Hex batch | 5.71% | 38 / 665 |
| Hex streaming | 6.17% | 41 / 665 |

Both Hex modes used the same pinned weights, packaged worker, Metal device,
runtime, and 22 frozen speech WAVs. The silence control was tested through the
application's normal gate and rejected. The native control used byte-identical
float32 input waveforms: batch adds 200 ms of silence internally, so the matched
stream was fed that same padded waveform. All speech files were run twice with
mode and fixture order reversed. Every repeated transcript was stable, and all
stream results came from streaming, with no batch fallback.

The app's batch result used the same production trimming, speech gates, ASR
filters, and verifier as the app streaming comparison. Cleanup was disabled for
this raw-ASR audit. The normalized app outputs matched the corresponding direct
native batch/stream outputs for every speech fixture. The app's 80 ms capture
tail and the matched 200 ms tail produced the same normalized stream text; one
final period changed. No capture-feed or filter discrepancy was observed here.

18 of 22 batch/stream transcripts were identical after the standard normalizer.
Differences were confined to the two long passages and their quiet/noisy copies.
Streaming added three **net scored errors** under standard WER. Most of the
original numerical gap was already present in Hex batch.

## Why standard WER overstates the gap

The scorer does not treat all written and spoken representations as equivalent.
For example, it penalizes `config.json` versus “config dot json”, `example.com`
versus “example dot com”, October 19 versus October nineteenth, and 3:45 p.m.
versus three forty-five p.m. These cases recur in the long paragraph variants.

An explicit diagnostic rescore applies the same four equivalence rules to every
reference and every hypothesis. It leaves names, missing currency markers,
word fusions, articles, and other word changes intact:

| Path | WER after format equivalence | Errors / reference words |
| --- | ---: | ---: |
| Current Parakeet | 2.86% | 19 / 665 |
| Hex batch | 2.56% | 17 / 665 |
| Hex streaming | 3.61% | 24 / 665 |

This is a post-hoc diagnostic audit on a small synthetic set. It is not a new
independent benchmark. The base scorer still ignores punctuation in URLs, so
this metric does not establish correct rendered URLs. Inspect those outputs too.

## Remaining mode differences

Relative to Hex batch, streaming adds seven scored errors after that format
audit, all in long passages or their reused variants:

- “status page is” becomes “status pages”: two edits in the planning passage
  and two in its quiet copy.
- The dollar marker disappears from the total: one edit in each travel copy.
- “That is the complete request” becomes “That is a complete request”: one edit
  in the noisy travel copy.

Some names are wrong in both Hex modes. Both render “Maya Chen” as “MayoChen”
in the planning passage, and “Maya Chen or” as “Maya Chenner” in the travel
passage. Batch transcription does not fix those shared errors. Hex does better
on some other controls, including sapphire, Siobhan, and changelog.

The results isolate a modest streaming cost on these inputs. They do not show a
twofold increase in meaning errors, or prove that the 0.6B model is generally
worse than the current model. The shared checkpoint, quantization, and native
runtime are not separately isolated by this experiment. TTS intended-text
references are not human phonetic ground truth, and the repeated long passages
are correlated observations. The current opt-in trial remains the right scope.

## Reproduce headlessly

```sh
python3 experiments/streaming-comparison/app-trial/compare_hex_modes.py
python3 experiments/streaming-comparison/app-trial/audit_hex_formats.py
```

The normalizer cache is prepared by `setup_scoring.py` in the parent experiment.
The pinned model must already be in the local app cache and the trial bundle
must be built. Results, per-clip text, input hashes, and binary/model provenance
are saved in ignored `results/hex-modes/`. The batch app run uses a temporary
preference suite and private socket. No GUI or microphone is opened. These are
unpaced quality runs; the earlier paced latency results remain separate.
