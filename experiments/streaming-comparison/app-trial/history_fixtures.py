#!/usr/bin/env python3
"""Make private, reproducible TTS fixtures from local dictation text.

These clips are new synthetic speech. They do not recreate the original recordings.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
import wave
from pathlib import Path


SAMPLE_RATE = 16_000
GENERATOR_VERSION = 1
DEFAULT_HISTORY = Path.home() / "Library/Application Support/com.ezraapple.shoutout/transcription-history.json"
DEFAULT_OUTPUT = Path(__file__).resolve().parents[3] / ".local-evals/history-tts"
APP_SUPPORT = DEFAULT_HISTORY.parent
VOICE_PREFERENCE = ("Samantha", "Daniel", "Eddy (English (US))", "Alex", "Karen", "Serena")
BOILERPLATE = re.compile(r"^(?:test(?:ing)?[.!? ]*|(?:test|testing)[, ]+(?:one[, ]+two(?:[, ]+three)?|123)[.!? ]*)$", re.I)
NEGATION = re.compile(r"\b(?:not|don't|do not|never|without|isn't|can't|won't|no)\b", re.I)
CORRECTION = re.compile(r"\b(?:actually|rather|instead|correction|I mean|make that|wait)\b", re.I)
TECHNICAL = re.compile(r"\b(?:API|PR|URL|JSON|SQL|CLI|UI|GitHub|Swift|Python|deploy|server|database|model|repo)\b|\.[a-z]{2,5}\b", re.I)
CAMEL_CASE = re.compile(r"[a-z][A-Z]")


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _private_output_dir(output_dir: Path) -> Path:
    path = output_dir.expanduser().resolve()
    if ".local-evals" not in path.parts and not path.is_relative_to(APP_SUPPORT.resolve()):
        raise ValueError("output must be under a private .local-evals or ShoutOut Application Support directory")
    if path == APP_SUPPORT.resolve():
        raise ValueError("choose a dedicated output directory under ShoutOut Application Support")
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path, 0o700)
    if ".local-evals" in path.parts:
        anchor = Path(*path.parts[:path.parts.index(".local-evals") + 1])
        os.chmod(anchor, 0o700)
    return path


def _atomic_json(path: Path, value: object) -> None:
    payload = json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as destination:
            destination.write(payload)
            destination.flush()
            os.fsync(destination.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _word_count(text: str) -> int:
    return len(text.split())


def _features(text: str) -> set[str]:
    flags = set()
    if TECHNICAL.search(text) or CAMEL_CASE.search(text):
        flags.add("technical")
    if re.search(r"\d", text):
        flags.add("numeric")
    if "?" in text:
        flags.add("question")
    if NEGATION.search(text):
        flags.add("negation")
    if CORRECTION.search(text):
        flags.add("correction")
    return flags


def _candidate_texts(history_path: Path, snapshot: bytes | None = None) -> list[dict]:
    history = json.loads(snapshot if snapshot is not None else history_path.read_bytes())
    if not isinstance(history, list):
        raise ValueError("transcription history must be a JSON array")
    candidates = []
    seen = set()
    for entry in history:
        if not isinstance(entry, dict):
            continue
        raw = entry.get("languagePassInput") or entry.get("text")
        if not isinstance(raw, str):
            continue
        reference = " ".join(raw.split())
        count = _word_count(reference)
        if count < 3 or count > 500 or BOILERPLATE.fullmatch(reference):
            continue
        words = frozenset(re.findall(r"\w+", reference.casefold()))
        key = " ".join(re.findall(r"\w+", reference.casefold()))
        if key in seen:
            continue
        seen.add(key)
        stratum = "short" if count <= 30 else "medium" if count <= 90 else "long"
        candidates.append({
            "reference": reference,
            "wordCount": count,
            "stratum": stratum,
            "features": _features(reference),
            "words": words,
            "textSHA256": _sha256(reference.encode("utf-8")),
        })
    return candidates


def _select(candidates: list[dict], count: int) -> list[dict]:
    buckets = {stratum: [] for stratum in ("short", "medium", "long")}
    for candidate in candidates:
        buckets[candidate["stratum"]].append(candidate)
    selected = []
    used_words: set[str] = set()
    feature_counts: dict[str, int] = {}
    while len(selected) < count and any(buckets.values()):
        for stratum in buckets:
            if len(selected) >= count:
                break
            options = buckets[stratum]
            if not options:
                continue

            def score(candidate: dict) -> tuple:
                features = candidate["features"]
                return (
                    sum(feature_counts.get(feature, 0) == 0 for feature in features),
                    -sum(feature_counts.get(feature, 0) for feature in features),
                    len(candidate["words"] - used_words),
                    candidate["wordCount"],
                    candidate["textSHA256"],
                )

            choice = max(options, key=score)
            options.remove(choice)
            selected.append(choice)
            used_words.update(choice["words"])
            for feature in choice["features"]:
                feature_counts[feature] = feature_counts.get(feature, 0) + 1
    return selected


def _installed_english_voices() -> list[str]:
    result = subprocess.run(["/usr/bin/say", "-v", "?"], capture_output=True, text=True, timeout=15, check=True)
    available = []
    for line in result.stdout.splitlines():
        match = re.match(r"^(.*?)\s+en_[A-Z]{2}\s+#", line)
        if match:
            available.append(match.group(1).strip())
    preferred = [voice for voice in VOICE_PREFERENCE if voice in available]
    remaining = sorted(set(available) - set(preferred))
    voices = preferred + remaining
    if not voices:
        raise RuntimeError("no installed English macOS say voice was found")
    return voices[:3]


def _validate_wav(path: Path) -> None:
    with wave.open(str(path), "rb") as audio:
        actual = (audio.getnchannels(), audio.getsampwidth(), audio.getframerate(), audio.getcomptype())
        if actual != (1, 2, SAMPLE_RATE, "NONE") or audio.getnframes() == 0:
            raise RuntimeError("afconvert did not produce nonempty mono 16 kHz PCM16 WAV")


def _run_audio_command(arguments: list[str], stage: str) -> None:
    try:
        result = subprocess.run(arguments, capture_output=True, timeout=180)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"{stage} timed out") from error
    if result.returncode:
        # Tool output can contain private source text, so do not echo it.
        raise RuntimeError(f"{stage} failed with exit code {result.returncode}")


def _synthesize(reference: str, voice: str, destination: Path) -> None:
    with tempfile.TemporaryDirectory(prefix=".tts-", dir=destination.parent) as temporary_dir:
        temporary = Path(temporary_dir)
        speech_text = temporary / "speech.txt"
        source_audio = temporary / "speech.aiff"
        wav = temporary / "speech.wav"
        speech_text.write_text(reference, encoding="utf-8")
        os.chmod(speech_text, 0o600)
        _run_audio_command(["/usr/bin/say", "-v", voice, "-r", "178", "-f", str(speech_text), "-o", str(source_audio)], "say")
        _run_audio_command(["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(source_audio), str(wav)], "afconvert")
        _validate_wav(wav)
        os.chmod(wav, 0o600)
        if destination.exists() or destination.is_symlink():
            raise FileExistsError(f"unmanifested audio already exists: {destination}")
        os.replace(wav, destination)


def _validate_cached_row(existing: dict, expected: dict) -> None:
    for key, value in expected.items():
        if existing.get(key) != value:
            raise ValueError(f"cached fixture {expected['name']} does not match current selection ({key})")
    path = Path(expected["path"])
    if path.is_symlink() or not path.is_file() or existing.get("sha256") != _file_sha256(path):
        raise ValueError(f"cached fixture {expected['name']} has a missing or changed WAV")
    _validate_wav(path)


def generate_history_fixtures(output_dir: Path, count: int = 18, history_path: Path = DEFAULT_HISTORY) -> Path:
    """Return a replay-compatible manifest for private history-derived TTS audio."""
    if count < 0:
        raise ValueError("count must be nonnegative")
    output = _private_output_dir(Path(output_dir))
    history_path = Path(history_path).expanduser().resolve()
    history_snapshot = history_path.read_bytes()
    history_hash = _sha256(history_snapshot)
    selected = _select(_candidate_texts(history_path, history_snapshot), count)
    voices = _installed_english_voices() if selected else []
    manifest_path = output / "manifest.json"
    provenance_path = output / "provenance.json"
    if manifest_path.is_symlink() or provenance_path.is_symlink():
        raise ValueError("manifest and provenance must be regular files inside the private output directory")
    existing = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else []
    if not isinstance(existing, list) or len(existing) > len(selected):
        raise ValueError("existing manifest does not match the requested fixture set")
    rows = []
    strata = ("short", "medium", "long")
    counters = {stratum: 0 for stratum in strata}
    expected_rows = []
    for candidate in selected:
        stratum = candidate["stratum"]
        counters[stratum] += 1
        name = f"history-{stratum}-{counters[stratum]:02d}"
        expected_rows.append({
            "name": name,
            "path": str(output / f"{name}.wav"),
            "reference": candidate["reference"],
            "source": "local-history-tts",
            "wordCount": candidate["wordCount"],
            "voice": voices[(counters[stratum] - 1 + strata.index(stratum)) % len(voices)],
            "sourceTextSHA256": candidate["textSHA256"],
            "generatorVersion": GENERATOR_VERSION,
        })

    for index, row in enumerate(existing):
        _validate_cached_row(row, expected_rows[index])
        rows.append(row)

    def save_progress() -> None:
        _atomic_json(manifest_path, rows)
        _atomic_json(provenance_path, {
            "generator": "history_fixtures.py",
            "generatorVersion": GENERATOR_VERSION,
            "source": "local ShoutOut transcription history text; new macOS say speech",
            "sourceHistorySHA256": history_hash,
            "selectedCount": len(selected),
            "completedCount": len(rows),
            "voices": voices,
            "sampleRateHz": SAMPLE_RATE,
            "sampleFormat": "mono PCM16 WAV",
            "speechRateWordsPerMinute": 178,
            "selection": "deterministic short/medium/long rotation; complete entries of 3 to 500 words; deduplicated text",
            "limitations": [
                "Original dictation audio was not saved. These clips are synthesized from saved text.",
                "The text is an ASR-derived reference, not verified verbatim speech from the user.",
                "TTS pronunciation, timing, prosody, and microphone conditions differ from real dictation.",
                "Use the same WAV for paired engines; do not treat this corpus as a real-audio WER estimate.",
            ],
        })

    save_progress()
    for expected in expected_rows[len(rows):]:
        destination = Path(expected["path"])
        if destination.exists() or destination.is_symlink():
            raise FileExistsError(f"unmanifested audio already exists: {destination}")
        _synthesize(expected["reference"], expected["voice"], destination)
        rows.append({**expected, "sha256": _file_sha256(destination)})
        save_progress()
    return manifest_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--count", type=int, default=18)
    parser.add_argument("--history", type=Path, default=DEFAULT_HISTORY)
    args = parser.parse_args()
    manifest = generate_history_fixtures(args.output, args.count, args.history)
    rows = json.loads(manifest.read_text(encoding="utf-8"))
    print(json.dumps({"manifest": str(manifest), "fixtureCount": len(rows)}, indent=2))


if __name__ == "__main__":
    main()
