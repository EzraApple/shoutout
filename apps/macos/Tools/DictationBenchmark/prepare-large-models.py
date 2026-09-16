#!/usr/bin/env python3
"""Download pinned public ASR checkpoints into the isolated benchmark directory."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import shutil
import urllib.request

ROOT = Path(__file__).resolve().parents[2] / ".build/large-asr-models"
MODELS = {
    "parakeet-1.1b": ("mlx-community/parakeet-tdt-1.1b", "a48da3b2e1aa436c4077acb978bb3a2b65fd1b45"),
    "qwen-asr-1.7b": ("mlx-community/Qwen3-ASR-1.7B-bf16", "e1f6c266914abc5a46e8756e02580f834a6cf8a7"),
    "canary-1b": ("qfuxa/canary-mlx", "1d2d321f7bfd2026ee2dcb5639f524ab8b5f0c96"),
}

def download_weights(url, target):
    partial = target.with_name(target.name + ".partial")
    prefix = partial.stat().st_size if partial.exists() else 0
    with urllib.request.urlopen(urllib.request.Request(url, headers={"Range": "bytes=0-0"}), timeout=60) as response:
        assert response.status == 206
        total = int(response.headers["Content-Range"].split("/")[1])
    parts = target.with_name(target.name + ".parts")
    parts.mkdir(exist_ok=True)
    ranges = [(start, min(start + 64 * 1024 * 1024, total) - 1)
              for start in range(prefix, total, 64 * 1024 * 1024)]
    def fetch(bounds):
        start, end = bounds
        path = parts / f"{start}-{end}"
        if path.exists() and path.stat().st_size == end - start + 1:
            return path
        for attempt in range(3):
            try:
                request = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
                with urllib.request.urlopen(request, timeout=90) as response:
                    assert response.headers["Content-Range"] == f"bytes {start}-{end}/{total}"
                    with path.open("wb") as output:
                        shutil.copyfileobj(response, output, 1024 * 1024)
                assert path.stat().st_size == end - start + 1
                print(f"Chunk {target.parent.name}: {end + 1}/{total}", flush=True)
                return path
            except Exception:
                if attempt == 2:
                    raise
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        completed = list(pool.map(fetch, ranges))
    assembled = target.with_name(target.name + ".assembled")
    with assembled.open("wb") as output:
        if prefix:
            with partial.open("rb") as source:
                shutil.copyfileobj(source, output, 8 * 1024 * 1024)
        for path in completed:
            with path.open("rb") as source:
                shutil.copyfileobj(source, output, 8 * 1024 * 1024)
    assert assembled.stat().st_size == total
    assembled.replace(target)
    if partial.exists():
        partial.unlink()
    shutil.rmtree(parts)

def download(job):
    label, repo, revision, name = job
    target = ROOT / label / name
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        url = f"https://huggingface.co/{repo}/resolve/{revision}/{name}"
        if name.endswith(".safetensors"):
            download_weights(url, target)
        else:
            temporary = target.with_name(target.name + ".partial")
            with urllib.request.urlopen(url, timeout=120) as response:
                with temporary.open("wb") as output:
                    shutil.copyfileobj(response, output, 1024 * 1024)
            temporary.replace(target)
    digest = hashlib.sha256()
    with target.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    print(f"Ready {label}/{name}: {target.stat().st_size} bytes", flush=True)
    return str(target.relative_to(ROOT)), digest.hexdigest()

if __name__ == "__main__":
    jobs = []
    expected = {}
    for label, (repo, revision) in MODELS.items():
        with urllib.request.urlopen(f"https://huggingface.co/api/models/{repo}/revision/{revision}?blobs=true") as response:
            metadata = json.load(response)
        for file in metadata["siblings"]:
            name = file["rfilename"]
            if name != ".gitattributes":
                jobs.append((label, repo, revision, name))
                if "lfs" in file:
                    expected[f"{label}/{name}"] = file["lfs"]["sha256"]
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        hashes = dict(pool.map(download, jobs))
    for path, digest in expected.items():
        assert hashes[path] == digest, f"Checkpoint checksum mismatch: {path}"
    (ROOT / "provenance.json").write_text(json.dumps(
        {"models": MODELS, "sha256": hashes, "verifiedPublishedSHA256": expected}, indent=2) + "\n")
