# Hex native comparison runner

This standalone runner uses Hex commit `083179900e85c1e23bb3a13591957eade092d79e`'s default Parakeet Unified English Q8_0 GGUF with `transcribe-cpp =0.2.4` and Metal. The model is 731,357,568 bytes; its expected SHA-256 is `4b50b6dd862bf6e346929aaf4f5eaacec003bfa3f56462d6c874b41ef2f38795`. Hex's default stream buffers 5.6 s of left context, 1.04 s per chunk, and 1.04 s of right context. The library selects those defaults when `StreamOptions::default()` is passed. The inference thread matches Hex's `QOS_CLASS_USER_INTERACTIVE` setting. The model is loaded and warmed before any measured clip; QoS status, startup and probe costs are printed on stderr.

Build (CMake is required; this workspace keeps a private copy under `.build/native-hex/cmake-package`):

```sh
PYTHONPATH="$(pwd)/experiments/streaming-comparison/.build/native-hex/cmake-package" \
PATH="$(pwd)/experiments/streaming-comparison/.build/native-hex/cmake-package/bin:$PATH" \
CARGO_TARGET_DIR=experiments/streaming-comparison/.build/native-hex/target \
cargo build --release --manifest-path experiments/streaming-comparison/native-hex/Cargo.toml
```

Probe, then run either batch or stream with one JSON manifest:

```sh
BIN=experiments/streaming-comparison/.build/native-hex/target/release/native-hex-benchmark
MODEL=experiments/streaming-comparison/.build/native-hex/model/parakeet-unified-en-0.6b-Q8_0.gguf
"$BIN" probe --model "$MODEL"
"$BIN" run --mode batch --model "$MODEL" --manifest fixtures.json --output batch.jsonl
"$BIN" run --mode stream --model "$MODEL" --manifest fixtures.json --output stream.jsonl
"$BIN" run --mode stream --unpaced-stream --packet-ms 160 --model "$MODEL" --manifest fixtures.json --output stream-unpaced.jsonl
```

`fixtures.json` is an array of `{ "name": "sample-id", "path": "/absolute/mono-16k.wav", "reference": "human transcript" }`. A selected-name manifest can be passed for a latency subset without changing the runner. Audio must be 16 kHz mono WAV, 16/24/32-bit PCM or 32-bit float. Files are decoded before any measured clip. Each JSONL result includes raw final text, timing, source (`stream`, `offline`, or `fallback`), model and runtime pins, and sample counts. Release timings are `null` for unpaced streaming because unpaced feed cannot represent user release latency.

Batch follows Hex's minimum 1.5 s padding and 200 ms trailing silence for this model. It splits clips above the model's advertised audio limit into chunks and pads each chunk to the 1.5 s minimum, then joins nonempty chunk text with spaces. Stream feeds the raw clip, like Hex's live capture path. Hex normally sends 160 ms packets; `--packet-ms 20` is for optional 20 ms packet quality checks. `release_to_text_ms` includes any queued feed work after the paced producer's release and stream finalization. `session_rotation_ms` measures the subsequent session rotation; `release_to_final_ms` includes both stages. `total_compute_ms` sums feed and finalization wall time and excludes pacing. Batch `batch_ms` includes session rotation; batch `total_compute_ms` measures inference alone. The runner does not enforce Hex's 1.5 s finish deadline or 250 ms overfeed guard; exact-length fixtures cannot trigger the latter. It does not include microphone capture, resampling, silence gating/trimming, text normalization, or paste latency. Corpus transcripts stay in local JSONL files. `PROVENANCE.sha256` records the downloaded Hex source files, model, runner source, and release executable.
