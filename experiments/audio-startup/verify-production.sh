#!/bin/bash
set -euo pipefail
TASK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TASK_DIR/../.." && pwd)"
OUTPUT_DIR="${VERIFY_OUTPUT_DIR:-$TASK_DIR/output-production}"
mkdir -p "$OUTPUT_DIR"
xcrun swiftc -O "$TASK_DIR/AudioDeviceControl.swift" -o "$OUTPUT_DIR/AudioDeviceControl"
RECORDER_SOURCE="$REPO_DIR/apps/macos/Sources/Services/AudioRecorder.swift"
SWIFT_FLAGS=(-O -swift-version 6 -parse-as-library)
if [[ "${VERIFY_COLD_BASELINE:-0}" == "1" ]]; then
  SWIFT_FLAGS+=(-D COLD_RECORDER_BASELINE)
  RECORDER_SOURCE="$OUTPUT_DIR/ColdAudioRecorder.swift"
  git -C "$REPO_DIR" show f54f08958b03:apps/macos/Sources/Services/AudioRecorder.swift > "$RECORDER_SOURCE"
  cat >> "$RECORDER_SOURCE" <<'SWIFT'

extension AudioRecorder {
    var onInterruption: ((String) -> Void)? {
        get { nil }
        set {}
    }
    func tearDown() {
        if isRecording { _ = stopRecording() }
    }
}
SWIFT
fi
xcrun swiftc "${SWIFT_FLAGS[@]}" \
  "$TASK_DIR/VerifyProductionRecorder.swift" \
  "$RECORDER_SOURCE" \
  "$REPO_DIR/apps/macos/Sources/Services/AudioConverterInputProvider.swift" \
  -o "$OUTPUT_DIR/VerifyProductionRecorder"
python3 "$TASK_DIR/run-verification.py" "$OUTPUT_DIR"
python3 - "$OUTPUT_DIR/results.jsonl" <<'PY'
import json
import sys
rows = [json.loads(line) for line in open(sys.argv[1])]
assert any(row.get("type") == "complete" and row.get("passed") for row in rows), rows
assert rows[-1]["inputRestored"] and rows[-1]["idleDeviceRunning"] == 0, rows[-1]
PY
echo "$OUTPUT_DIR/results.jsonl"
