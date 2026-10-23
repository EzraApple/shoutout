#!/bin/bash
set -euo pipefail
TASK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TASK_DIR/../.." && pwd)"
OUTPUT_DIR="${BENCH_OUTPUT_DIR:-$TASK_DIR/output}"
mkdir -p "$OUTPUT_DIR"
MACOS_SOURCES="$REPO_DIR/apps/macos/Sources"
# Keep the original baseline reproducible after production AudioRecorder changes.
git -C "$REPO_DIR" show f54f08958b03:apps/macos/Sources/Services/AudioRecorder.swift \
  > "$OUTPUT_DIR/ReferenceAudioRecorder.swift"
python3 "$TASK_DIR/instrument-recorder.py" \
  "$OUTPUT_DIR/ReferenceAudioRecorder.swift" "$OUTPUT_DIR/InstrumentedAudioRecorder.swift"
xcrun swiftc -O -swift-version 5 -emit-library -emit-module -module-name ShoutOutCore \
  "$MACOS_SOURCES/Core/TextInsertionFormatter.swift" \
  -emit-module-path "$OUTPUT_DIR/ShoutOutCore.swiftmodule" \
  -o "$OUTPUT_DIR/libShoutOutCore.dylib"
xcrun swiftc -O -swift-version 5 -parse-as-library \
  -I "$OUTPUT_DIR" -L "$OUTPUT_DIR" -lShoutOutCore \
  -Xlinker -rpath -Xlinker "$OUTPUT_DIR" \
  "$TASK_DIR/AudioStartupBench.swift" \
  "$OUTPUT_DIR/InstrumentedAudioRecorder.swift" \
  "$MACOS_SOURCES/Services/AudioConverterInputProvider.swift" \
  "$MACOS_SOURCES/Services/RecordingTranscriptionQueue.swift" \
  "$MACOS_SOURCES/Services/TextInserter.swift" \
  -o "$OUTPUT_DIR/AudioStartupBench"
"$OUTPUT_DIR/AudioStartupBench" > "$OUTPUT_DIR/results.jsonl" 2> "$OUTPUT_DIR/stderr.log"
echo "$OUTPUT_DIR/results.jsonl"
