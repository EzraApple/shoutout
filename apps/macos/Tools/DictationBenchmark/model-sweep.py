#!/usr/bin/env python3
"""Run isolated, serial model comparisons using an already-built benchmark binary."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import urllib.request

HERE = Path(__file__).resolve().parent
BUILD = HERE.parents[1] / ".build"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--kind", choices=["lm", "asr", "asr-v2"], required=True)
parser.add_argument("--output-directory", type=Path, required=True)
args = parser.parse_args()
args.output_directory.mkdir(parents=True, exist_ok=True)
models = [
    ("llama", "mlx-community/Llama-3.2-1B-Instruct-4bit"),
    ("qwen", "mlx-community/Qwen3.5-0.8B-4bit"),
    ("lfm", "mlx-community/LFM2.5-1.2B-Instruct-4bit"),
]
all_rows = []

def run(label, parameters, round_index):
    output = args.output_directory / f"{label}-{round_index}.json"
    print("Starting", label, "round", round_index, flush=True)
    command = [sys.executable, str(HERE / "run.py"), "--skip-build", "--cache-mib", "0",
               "--output", str(output), *parameters]
    with output.with_suffix(".log").open("w") as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
    rows = json.loads(output.read_text())
    for row in rows:
        row["round"] = round_index
        row["label"] = label
    all_rows.extend(rows)
    (args.output_directory / f"{args.kind}-combined.json").write_text(
        json.dumps(all_rows, indent=2) + "\n")
    print("Finished", label, len(rows), "rows", flush=True)

if args.kind == "lm":
    for label, model in models:
        if label != "llama" and not (BUILD / "model-candidates" / model / "benchmark-provenance.json").exists():
            raise SystemExit("Finish prepare-models.py before starting timed runs: " + model)
    # Latin-square model order spreads thermal/time-of-run effects across models.
    for round_index in range(3):
        for offset in range(3):
            label, model = models[(offset + round_index) % 3]
            parameters = ["--repetitions", "1", "--lm-model", model,
                          "--lm-inputs", str(BUILD / "dictation-audio/lm-model-inputs.json")]
            if label != "llama":
                parameters += ["--lm-directory", str(BUILD / "model-candidates" / model)]
            run(label, parameters, round_index)
elif args.kind == "asr":
    with urllib.request.urlopen("https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml") as response:
        provenance = json.load(response)
    (args.output_directory / "parakeet-hub-provenance.json").write_text(
        json.dumps(provenance, indent=2) + "\n")
    # Reverse engine order in the second round. Each file gets a warmup per process.
    for round_index in range(2):
        for engine in (["whisper", "parakeet"] if round_index == 0 else ["parakeet", "whisper"]):
            run(engine, ["--repetitions", "2", "--audio-only", "--asr", engine,
                "--audio-manifest", str(BUILD / "dictation-audio/model-manifest.json")], round_index)
else:
    if not (args.output_directory / "asr-combined.json").exists():
        raise SystemExit("Run the ASR baseline sweep first")
    for round_index in range(2):
        run("parakeet-v2encoder", ["--repetitions", "2", "--audio-only", "--asr", "parakeet",
            "--parakeet-encoder", "int8-v2", "--audio-manifest",
            str(BUILD / "dictation-audio/model-manifest.json")], round_index)
