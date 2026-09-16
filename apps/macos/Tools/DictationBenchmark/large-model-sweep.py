#!/usr/bin/env python3
"""Serial ASR sweep followed by cleanup of every distinct output in all styles."""
import json
from collections import defaultdict
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
MACOS = HERE.parents[1]
OUTPUT = MACOS / ".build/large-model-comparison"
OUTPUT.mkdir(exist_ok=True)

def run(label, arguments):
    output = OUTPUT / f"{label}.json"
    if output.exists():
        rows = json.loads(output.read_text())
        passes = defaultdict(set)
        for row in rows:
            if row["kind"] != "audio-gate":
                passes[row["name"], row["kind"], row["style"]].add(row["repetition"])
        if passes and all(value == {0, 1} for value in passes.values()):
            print(f"Reuse completed {label}", flush=True)
            return rows
        output.replace(output.with_suffix(".incomplete.json"))
    command = [sys.executable, str(HERE / "run.py"), "--output", str(output),
               "--cache-mib", "0", "--repetitions", "2", *arguments]
    print(f"Start {label}", flush=True)
    with (OUTPUT / f"{label}.log").open("w") as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
    print(f"Finished {label}", flush=True)
    return json.loads(output.read_text())

if __name__ == "__main__":
    assert (MACOS / ".build/large-asr-models/provenance.json").exists(), "Finish model downloads first"
    audio = ["--audio-only", "--audio-manifest", str(MACOS / ".build/dictation-audio/model-manifest.json")]
    all_rows = []
    for index, label in enumerate(["parakeet-1.1b", "parakeet-1.1b-nemo-mel", "canary-1b", "qwen-asr-1.7b"]):
        # First run builds the current harness; later runs reuse that exact binary.
        rows = run(label, (["--skip-build"] if index else []) + audio + ["--asr", "python", "--python-model", label])
        all_rows.extend(dict(row, label=label) for row in rows)
    for label, version in [("parakeet-v2", "v2"), ("whisper", None), ("parakeet-v3", "v3")]:
        arguments = (["--fluid-audio", str(MACOS / ".build/FluidAudio-model-benchmark")]
                     if label == "parakeet-v2" else ["--skip-build"])
        arguments += audio
        if version:
            arguments += ["--asr", "parakeet", "--parakeet-version", version]
        rows = run(label, arguments)
        all_rows.extend(dict(row, label=label) for row in rows)
    (OUTPUT / "asr-combined.json").write_text(json.dumps(all_rows, indent=2) + "\n")

    # Identical transcripts share the same cleanup measurements, eliminating
    # pointless duplicate inference and timing differences due only to model order.
    texts = sorted({r["final"] for r in all_rows if r["kind"] == "asr" and r["final"]})
    fixtures = [dict(name=f"transcript-{i:04d}", input=text) for i, text in enumerate(texts)]
    inputs = OUTPUT / "lm-inputs.json"
    inputs.write_text(json.dumps(fixtures, indent=2) + "\n")
    print(f"Cleanup: {len(fixtures)} distinct transcripts, three styles, two passes", flush=True)
    run("lm-all-transcripts", ["--skip-build", "--lm-inputs", str(inputs)])
