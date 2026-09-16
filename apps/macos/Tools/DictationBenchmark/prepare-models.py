#!/usr/bin/env python3
"""Download immutable public MLX snapshots into a benchmark-only directory."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import sys
import urllib.request

MODELS = {
    "mlx-community/Qwen3.5-0.8B-4bit": "da28692b5f139cb0ec58a356b437486b7dac7462",
    "mlx-community/LFM2.5-1.2B-Instruct-4bit": "dee2f8a2786e6648bb644a7ca40652842490034b",
}
destination = Path(sys.argv[1]).resolve()
for model, revision in MODELS.items():
    root = destination / model
    root.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(f"https://huggingface.co/api/models/{model}/revision/{revision}") as response:
        metadata = json.load(response)
    names = [f["rfilename"] for f in metadata["siblings"]
             if f["rfilename"].endswith((".json", ".jinja", ".safetensors"))]

    def download(name):
        path = root / name
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            partial = path.with_suffix(path.suffix + ".partial")
            urllib.request.urlretrieve(f"https://huggingface.co/{model}/resolve/{revision}/{name}", partial)
            partial.rename(path)
        digest = hashlib.sha256()
        with path.open("rb") as file:
            for chunk in iter(lambda: file.read(1024 * 1024), b""):
                digest.update(chunk)
        return name, dict(bytes=path.stat().st_size, sha256=digest.hexdigest())

    with ThreadPoolExecutor(max_workers=4) as pool:
        files = dict(pool.map(download, names))
    (root / "benchmark-provenance.json").write_text(json.dumps(
        dict(model=model, revision=revision, files=files), indent=2) + "\n")
    print(model, sum(f["bytes"] for f in files.values()), "bytes", flush=True)
