# App-path replay trial

`generate_fixtures.py` creates a fresh local speech set with macOS `say`, then
converts it to mono 16 kHz signed PCM with `ffmpeg`. It writes fixed references,
voice and environment metadata, per-file sample counts, durations, and SHA-256
hashes to `fixtures/manifest.json`. It uses no network service and runs no ASR.

Regenerate on this Mac with:

```sh
python3 experiments/streaming-comparison/app-trial/generate_fixtures.py
```

The manifest records the macOS version because voice assets and `say` output can
change across OS releases. The random seed fixes the synthetic 15 dB SNR noise
copies for a given Python runtime. `say` itself is deterministic only within the
recorded voice/runtime environment; these files are frozen by their hashes for
any one comparison run.

The set has 16 short/medium phrases and two longer paragraphs. It covers names,
negation, a self-correction, a final-word test, dates, numbers, an amount,
versions, a port, spoken URLs, a filename, acronyms, and a terminal “thank you”.
There are two -20 dB quiet copies, two reproducible 15 dB SNR noisy copies, and a
two-second silence control. The references are the exact text submitted to TTS.
They describe intended words, not a human-verified phonetic transcript. In
particular, `say` may pronounce punctuation, abbreviations, names, and numeric
spellings differently from a person. Treat errors on those cases as prompts for
audio review, not conclusive model errors.

## Implemented replay

The packaged app has an early headless entry point, before `NSApplication` is
created. `DictationReplay` feeds WAV samples through the production
`AudioRecorder` collector, `RecordingTranscriptionQueue`, trim/speech gates,
`TranscriptionService` filters, dictionary replacement with no custom entries,
and the unchanged `LanguagePassService` cleanup policy. It writes final text
and timings to JSON. It never starts a microphone tap, installs hotkeys,
inserts text, or writes dictation history.

Paced replay feeds 50 ms sample blocks against a monotonic clock and simulates
the normal 80 ms hold-release tail. Streaming groups these into 160 ms feeds.
Stop-to-ASR measures release to final filtered ASR. Stop-to-sink adds cleanup.
Unpaced runs score quality only. Loading and unscored warmups are excluded from
the latency panel. Physical microphone input, resampling, key events, paste,
and energy remain outside this test.

[Hex batch versus streaming](HEX_MODES.md) isolates the pinned Hex model on
identical audio and audits the formatting bias in the original WER score.
The larger replay with the unchanged cleanup pipeline is recorded in
[RESULTS.md](RESULTS.md#larger-replay-with-the-existing-cleanup-pipeline).

Run the complete comparison after building the local trial:

```sh
python3 experiments/streaming-comparison/setup_scoring.py
python3 experiments/streaming-comparison/app-trial/run_comparison.py
python3 experiments/streaming-comparison/app-trial/summarize.py
```

The runner verifies every WAV hash, records the binary hash, runs both engines
on all 23 fixtures, then repeats a fixed eight-fixture paced subset three times.
Each run has an unscored warmup. Engine order alternates and the second round
reverses fixture order. Results and the HTML report stay under ignored
`results/`. [RESULTS.md](RESULTS.md) records the completed run and its limits.

The local Settings switch and CLI can select either engine. Current Parakeet
remains the default. See [headless commands](../../../apps/macos/HEADLESS.md)
for settings, model preparation, transcription, replay, and isolated CLI tests.
Live microphone timing and insertion still need a user-run trial.
