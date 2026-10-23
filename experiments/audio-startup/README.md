# Audio startup measurements

These local macOS tools separate recorder setup, hardware start, first buffer delivery,
and transcription-queue admission. They do not measure model inference or time to text.
No microphone audio is written to disk. Generated binaries and results stay in ignored
`output*` directories.

## Benchmark

Run from the repository root, with existing microphone permission and no recording active:

```sh
BENCH_ROUNDS=12 BENCH_VARIANTS=productionReference,retainedStopped,retainedPaused \
  bash experiments/audio-startup/run.sh
python3 experiments/audio-startup/summarize.py experiments/audio-startup/output/results.jsonl
```

The reference recorder is pinned to `f54f08958b03`. The runner rotates variant order,
uses the same input and capture workload, and excludes round zero from summaries.
Use the enum case names in `AudioStartupBench.swift` when selecting variants.

The confirmed built-in microphone run had 11 steady-state samples per variant:

| Recorder | Setup to engine ready, median | First raw buffer, median |
| --- | ---: | ---: |
| New engine each take | 160 ms | 264 ms |
| Retained, stopped engine | 78 ms | 183 ms |
| Retained, paused engine | 50 ms | 156 ms |

Paired paused-engine savings were about 109 ms to ready and 108 ms to the first
buffer. Input-node initialization and preparation accounted for most of the saved
work. The microphone was inactive between takes. A smaller requested tap buffer did
not change the observed 4,800-frame delivery size at 48 kHz.

## Production recorder lifecycle

```sh
bash experiments/audio-startup/verify-production.sh
VERIFY_ROUTE_STRESS=1 VERIFY_OUTPUT_DIR="$PWD/experiments/audio-startup/output-stress" \
  bash experiments/audio-startup/verify-production.sh
VERIFY_RAPID_SWITCH=1 VERIFY_OUTPUT_DIR="$PWD/experiments/audio-startup/output-rapid" \
  bash experiments/audio-startup/verify-production.sh
```

The verifier compiles the actual production recorder with a log stub. It checks
sample delivery and draining, hardware inactivity between takes, idle and active
route changes, replay isolation, and injected sleep/wake notifications. The stress
mode alternates 12 active route changes; the rapid mode switches twice in quick
succession. Injected notifications do not verify a physical sleep/wake cycle.

Route tests temporarily change the system default input, then restore it. They
accept only the local `BlackHole 2ch` or `Steam Streaming Microphone` virtual input.
They must never select an iPhone or a Continuity microphone. A watchdog restores
the original input if native audio code hangs and saves a local stack sample.

Production route recovery closes the sample gate and pauses hardware before it
cancels the take. It retains the old graph until the engine configuration event,
or a 1.5-second fallback. After repeated changes it waits 1.5 seconds from the last
change because an event may belong to an earlier route. Starting during that
window shows “Mic changing”; the microphone stays paused.

With explicit permission for local menu-bar screenshots, set
`PRIVACY_SCREENSHOT_DIRECTORY` and `VERIFY_TIMEOUT_SECONDS=70` to capture the
orange microphone indicator during recording and after pausing. Inspect those
images; CoreAudio's running flag alone does not verify the menu-bar UI.
