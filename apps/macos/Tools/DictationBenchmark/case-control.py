#!/usr/bin/env python3
"""Repeat original dictation outputs and controlled casing/punctuation variants."""
import json
from pathlib import Path
import random
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1] / ".build/large-model-comparison"
rows = json.loads((ROOT / "asr-combined.json").read_text())
texts = {r["final"] for r in rows if r["kind"] == "asr"
         and not r["name"].startswith("librispeech-") and r["final"]}
request = "can you send this over when you get a chance"
texts.update([request, request.capitalize(), request + "?", request.capitalize() + "?"])
fixtures = [dict(name=f"case-control-{i:03d}", input=text) for i, text in enumerate(sorted(texts))]
random.Random(20260915).shuffle(fixtures)
path = ROOT / "case-control-inputs.json"
path.write_text(json.dumps(fixtures, indent=2) + "\n")
print(f"{len(fixtures)} distinct inputs, three styles, three passes with odd rounds reversed", flush=True)
subprocess.run([sys.executable, str(HERE / "run.py"), "--output", str(ROOT / "case-control.json"),
    "--lm-inputs", str(path), "--cache-mib", "0", "--repetitions", "3", "--reverse-odd-rounds"], check=True)
