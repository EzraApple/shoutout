#!/usr/bin/env python3
"""Resident MLX ASR worker; newline JSON protocol for the isolated Swift harness."""
import base64
import contextlib
import json
import os
from pathlib import Path
import sys
import time
import traceback
from types import SimpleNamespace

protocol = sys.stdout
label = sys.argv[1]
checkpoint = ("parakeet-1.1b" if label.startswith("parakeet-1.1b")
              else "canary-1b" if label.startswith("canary-1b") else label)
directory = Path(__file__).resolve().parents[2] / ".build/large-asr-models" / checkpoint
metrics = Path(os.environ["BENCH_PYTHON_METRICS"])
metrics.parent.mkdir(parents=True, exist_ok=True)
metrics.write_text("")

def send(value):
    protocol.write(json.dumps(value) + "\n")
    protocol.flush()

def record(value):
    with metrics.open("a") as output:
        output.write(json.dumps(value) + "\n")

def word_timings(tokens):
    words, pieces = [], []
    def finish():
        if pieces and "".join(t.text for t in pieces).strip():
            words.append(dict(text="".join(t.text for t in pieces).strip(),
                start=float(pieces[0].start), end=float(pieces[-1].end),
                probability=sum(float(t.confidence) for t in pieces) / len(pieces)))
    for token in tokens:
        if token.text[:1].isspace():
            finish()
            pieces = []
        pieces.append(token)
    finish()
    return words

def split_at_quiet_boundaries(audio):
    # Keep every sample. Choose a quiet 100 ms interval between 15 and 24 s
    # from each chunk start, rather than exceeding Canary's short-audio context.
    start = 0
    while len(audio) - start > 24 * 16000:
        candidates = range(start + 15 * 16000, start + 24 * 16000, 1600)
        boundary = min(candidates, key=lambda i: float(np.mean(audio[i:i + 1600] ** 2))) + 800
        yield audio[start:boundary]
        start = boundary
    if start < len(audio):
        yield audio[start:]

try:
    with contextlib.redirect_stdout(sys.stderr):
        import mlx.core as mx
        import numpy as np
        start = time.perf_counter()
        if label.startswith("parakeet-1.1b"):
            from parakeet_mlx import from_pretrained
            from parakeet_mlx.audio import get_logmel
            model = from_pretrained(str(directory))
            if label.endswith("nemo-mel"):
                from dataclasses import fields
                from mlx_audio.stt.models.parakeet.audio import PreprocessArgs, log_mel_spectrogram
                settings = json.loads((directory / "config.json").read_text())["preprocessor"]
                accepted = {f.name for f in fields(PreprocessArgs)}
                frontend_config = PreprocessArgs(**{k: v for k, v in settings.items() if k in accepted})
                get_logmel = lambda audio, _: log_mel_spectrogram(audio, frontend_config)
        else:
            from mlx_audio.stt import load
            model = load(str(directory), strict=True)
        mx.eval(model.parameters())
        mx.synchronize()
        load_ms = (time.perf_counter() - start) * 1000
    record(dict(kind="load", loadMs=load_ms, activeBytes=mx.get_active_memory()))
    send(dict(ready=True, loadMs=load_ms))
    for line in sys.stdin:
        request = json.loads(line)
        audio = np.frombuffer(base64.b64decode(request["samples"]), dtype="<f4")
        with contextlib.redirect_stdout(sys.stderr):
            mx.reset_peak_memory()
            start = time.perf_counter()
            samples = mx.array(audio)
            chunk_tokens = []
            if label.startswith("parakeet-1.1b"):
                mel = get_logmel(samples, model.preprocessor_config)
                result = model.generate(mel)[0]
                words = word_timings(result.tokens)
            elif label.startswith("canary-1b"):
                chunks = split_at_quiet_boundaries(audio) if label.endswith("-chunked") else [audio]
                parts = []
                for chunk in chunks:
                    part = model.generate(mx.array(chunk), source_lang="en", target_lang="en",
                        temperature=0, max_tokens=1024)
                    parts.append(part.text)
                    chunk_tokens.append(part.generation_tokens)
                result = SimpleNamespace(text=" ".join(parts), generation_tokens=sum(chunk_tokens))
                words = []
            else:
                result = model.generate(samples, language="English", temperature=0, max_tokens=1024)
                words = []
            mx.synchronize()
            elapsed = (time.perf_counter() - start) * 1000
        tokens = len(result.tokens) if label.startswith("parakeet-1.1b") else result.generation_tokens
        record(dict(kind="inference", samples=len(audio), inferenceMs=elapsed, outputTokens=tokens,
            text=result.text, words=words,
            chunkCount=len(chunk_tokens) or 1,
            tokenLimitReached=any(t >= 1024 for t in chunk_tokens) if chunk_tokens
                else not label.startswith("parakeet-1.1b") and tokens >= 1024,
            peakBytes=mx.get_peak_memory(), activeBytes=mx.get_active_memory(), cachedBytes=mx.get_cache_memory()))
        send(dict(text=result.text, words=words, inferenceMs=elapsed))
except Exception:
    error = traceback.format_exc()
    print(error, file=sys.stderr, flush=True)
    send(dict(error=error))
    sys.exit(1)
