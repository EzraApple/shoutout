# Local trial and headless testing

The local build keeps current Parakeet as the default. Settings has a **Streaming
dictation (trial)** switch. Streaming uses Hex's pinned Parakeet Unified model
and native Metal worker. Recordings are limited to ten minutes in this trial.
Text cleanup uses the existing model and policy. Local trial builds disable
automatic updates so a normal release cannot replace the trial during evaluation.

Build and run the headless service from the repository root:

```sh
./script/build_and_run.sh
```

This is also the Codex Run action. It opens no window and does not install a
hotkey or microphone tap. The optional `--gui` flag explicitly opens the GUI.
Use the headless service while the GUI app is closed; both use the same private
control socket. If the GUI is already running, the CLI can use its services.

In another terminal:

```sh
./script/shoutout status
./script/shoutout settings get
./script/shoutout settings set streaming on
./script/shoutout models prepare
./script/shoutout transcribe /absolute/path/to/mono-16k.wav
./script/shoutout settings set streaming off
```

Settings include `streaming`, `cleanup`, `style`, `shortcut`, `indicator`, and
`color`. Boolean values accept `on/off` or `true/false`. Styles are `normal`,
`casual`, and `formal`. Indicators are `crab`, `classic`, and `glass`; shortcut and color
values use the IDs returned by `settings get`. A setting change cannot unload
an engine during dictation. Model preparation waits for loading to finish.

Commands return JSON. Logs go to stderr. When no app is running, settings still
persist for the next launch and file transcription runs in a temporary headless
process. File transcription uses the selected model, shared speech gates,
dictionary, and cleanup, but does not write history or insert text into an app.
It is a complete-file operation. Use paced replay to measure streaming latency.

Replay a JSON array of `{name, path, reference}` WAV fixtures:

```sh
./script/shoutout replay /absolute/manifest.json --output /absolute/results.json --paced
```

Replay uses the production sample collector, stream queue, trim and speech gate,
ASR filters, and the configured cleanup style. It simulates the 80 ms hold-release
tail and writes to a local result file. It uses no custom dictionary entries so
the fixtures remain a controlled comparison. It does not measure a physical mic,
resampling, keyboard events, accessibility insertion, or battery use.

The generated-speech comparison is reproducible with:

```sh
python3 experiments/streaming-comparison/app-trial/generate_fixtures.py
python3 experiments/streaming-comparison/app-trial/run_comparison.py
python3 experiments/streaming-comparison/app-trial/summarize.py
```

For paired batches with every intermediate stage, run
`./script/shoutout-compare --history`. It samples local transcription text,
synthesizes new audio locally, freezes the cleanup style and dictionary, and
compares both engines. It also accepts `--folder` or `--manifest`. The report
includes audio, raw recognition, dictionary text, cleanup candidates, final text,
failures, and timing. Personal text and generated audio stay in a private local
output directory. The diagnostic app must support replay schema 2; the runner
can use a separate comparison build without replacing the running app. See the
[batch guide](../../experiments/streaming-comparison/app-trial/README.md).

TTS references describe intended words. Review names and numeric/URL formatting
alongside WER. Quiet and noisy copies reuse the two original long passages.

For isolated CLI tests, set `SHOUTOUT_CLI_SUITE` to a temporary UserDefaults suite
and `SHOUTOUT_CONTROL_SOCKET` to a short socket path in a private temporary
directory. A private suite without an explicit socket always stays offline.
`SHOUTOUT_CLI_MODELS_DIRECTORY` overrides the ASR cache and puts the cleanup
cache in its `LanguageModels` subdirectory, including during replay. Set
`SHOUTOUT_CLI_LANGUAGE_MODELS_DIRECTORY` to override the cleanup cache separately.
Without these overrides, commands reuse the app's normal verified caches.
The app and headless host expose only a local Unix socket, with directory mode
0700 and socket mode 0600. A timed-out mutation is never retried as an offline
mutation because its outcome may be uncertain.

`python3 experiments/streaming-comparison/app-trial/test_cli.py` checks offline
settings persistence, live headless IPC, both models, silence rejection, cleanup,
and paced replay against the packaged build. It uses a temporary preference
suite and socket, and reuses the app's model caches. It opens no GUI.

To preserve existing build artifacts, set `SHOUTOUT_DIST_DIR` to an absolute output
directory when running `apps/macos/scripts/build-app.sh`. Set `SHOUTOUT_TEST_APP`
to the resulting `.app` path when running the CLI smoke test.
