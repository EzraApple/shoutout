#!/usr/bin/env python3
"""Export measured model summaries and local artifact provenance after sweeps finish."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
MACOS = HERE.parents[1]
BUILD = MACOS / ".build"
runs = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()

def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()

def file_hashes(root):
    return {str(path.relative_to(root)): dict(bytes=path.stat().st_size, sha256=digest(path))
            for path in sorted(root.rglob("*")) if path.is_file()
            and not any(part.startswith(".") for part in path.relative_to(root).parts)}

summary = json.loads(subprocess.check_output([
    sys.executable, str(HERE / "summarize-models.py"), str(runs)
], text=True))
audio_root = BUILD / "dictation-audio"
audio = json.loads((audio_root / "model-manifest.json").read_text())
for fixture in audio:
    assert digest(audio_root / fixture["path"]) == fixture["sha256"], fixture["name"]
summary["provenance"] = dict(
    gitHead=subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
    hardware=subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip(),
    memoryBytes=int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True)),
    macOS=subprocess.check_output(["sw_vers"], text=True).strip(),
    audioManifest=audio,
    additionalLanguageInputs=json.loads((audio_root / "lm-model-inputs.json").read_text()),
    sourceHashesAtBuildByRun={p.name: json.loads(p.read_text()) for p in sorted(runs.glob("*.sources.json"))},
    rawResultHashes={p.name: digest(p) for p in sorted(runs.glob("*.json"))
                     if p.name.endswith("-combined.json")},
    mlxMetalLibrarySHA256=digest(BUILD / "release/mlx.metallib"),
    candidateSnapshots={p.parent.name: json.loads(p.read_text())
        for p in sorted((BUILD / "model-candidates/mlx-community").glob("*/benchmark-provenance.json"))},
    parakeetRevision=json.loads((runs / "parakeet-hub-provenance.json").read_text())["sha"],
    parakeetArtifacts=file_hashes(BUILD / "parakeet-tdt-0.6b-v3"),
)
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(summary, indent=2) + "\n")
print(output)
