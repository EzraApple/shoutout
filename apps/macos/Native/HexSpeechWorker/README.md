# Hex speech worker

This is a persistent, out-of-process Metal transcription helper. It uses Hex commit `083179900e85c1e23bb3a13591957eade092d79e`'s Parakeet Unified English Q8_0 model, `transcribe-cpp =0.2.4`, one decoder thread, and the library's default buffered stream context. It verifies the model's byte count and SHA-256 before loading, warms offline inference, probes the stream, then writes one `ready` line. It reads one request and writes one response at a time. Native diagnostics go to stderr; stdout contains only protocol JSON.

Build the release bundle with `./build.sh`. The default output is universal (`arm64` and `x86_64`) at `build/release/hex-speech-worker`. `./build.sh --arm64-only` makes a smaller arm64 artifact. The script installs CMake into its ignored `build/tools/` directory if necessary, pins the macOS 15 deployment target, and places `ModelMetadata.json` and `Licenses/` beside the executable. The release binary uses only system dynamic libraries; the transcribe.cpp Metal shader library is embedded by its native build. The script ad hoc signs the local artifact so it can run during development. The app's packaging step must sign the nested executable with the release identity before signing the app.

The model is downloaded separately. `ModelMetadata.json` has the pinned URL, revision, file name, size, SHA-256, architecture, variant, and sample rate for the Swift downloader. Download to a temporary file, verify size and hash, then move it into the app's model cache. Launch the helper with an absolute path: `hex-speech-worker --model /absolute/path/parakeet-unified-en-0.6b-Q8_0.gguf`. Startup may take longer on a cold machine because it hashes and loads 731 MB, warms the model, and probes Metal. Wait for `ready` before recording commands.

The protocol uses newline-delimited JSON over stdin and stdout. Every non-startup response has the matching string `id`. IDs use ASCII letters, digits, hyphens, or underscores and cannot be reused in one worker process. Audio is base64-encoded, little-endian `f32` mono PCM at 16 kHz. A 160 ms feed is 2,560 samples. Feed acknowledgments come after native `stream.feed` completes. `finish` returns full authoritative text after native finalization and session rotation. The worker retains all accepted stream audio and transcribes the full clip offline if streaming fails or returns empty text. An invalid audio payload aborts that capture; a malformed request returns an error without changing the active stream. The caller may kill and restart the worker if inference stalls; there is no in-process finish timeout. One capture may be active at a time.

| Request | Response |
| --- | --- |
| Startup | `{"event":"ready","status":"ready","streamAvailable":true,"model":"...","modelSha256":"...","backend":"metal"}` or one error line and process exit |
| `{"op":"begin","id":"a"}` | `{"id":"a","event":"begun","status":"ok"}` |
| `{"op":"feed","id":"a","audio":"..."}` | `{"id":"a","event":"fed","status":"ok","samples":2560}` |
| `{"op":"finish","id":"a"}` | `{"id":"a","event":"result","status":"ok","text":"...","source":"stream"}`; `source` can be `fallback` |
| `{"op":"cancel","id":"a"}` | `{"id":"a","event":"cancelled","status":"ok"}`; an unknown ID is a harmless no-op |
| `{"op":"transcribe","id":"b","audio":"..."}` | `{"id":"b","event":"result","status":"ok","text":"...","source":"offline"}` |
| Invalid request | `{"id":"...","event":"error","status":"error","message":"...","error":"..."}`; `id` is omitted when unavailable |

Offline transcription matches Hex's minimum 1.5 seconds of audio plus 200 ms trailing silence for this model. It observes the model's advertised maximum audio length when chunking. The selected model currently advertises no maximum. The helper does not capture, resample, trim, normalize, or paste audio. ShoutOut must supply the 16 kHz samples it intends to transcribe. The 10-minute audio and 64 MiB JSON-line limits prevent unbounded input; the app should split or reject larger captures.

For an app bundle, copy `build/release/hex-speech-worker` to `ShoutOut.app/Contents/Helpers/HexSpeechWorker`. Copy `ModelMetadata.json`, `THIRD_PARTY_NOTICES.md`, and `Licenses/` to `ShoutOut.app/Contents/Resources/HexSpeechWorker/`. The parent app's packaging step handles these copies and signs the nested helper with the release identity before signing the app. Launch `Contents/Helpers/HexSpeechWorker` as a child process with pipes. The executable has no bundled model and must receive the verified cache path at launch.
