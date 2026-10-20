#!/usr/bin/env python3
"""Generate a small, reproducible macOS `say` speech corpus for app-path trials."""

from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
import platform
import random
import shutil
import subprocess
import sys
import tempfile
import wave
from pathlib import Path


SAMPLE_RATE = 16_000
VOICES = ["Samantha", "Daniel", "Eddy (English (US))"]
NOISE_SEED = 20261019

PHRASES = [
    ("01-save-file", VOICES[0], "Save the meeting notes in the project folder."),
    ("02-negation", VOICES[1], "Do not send the draft, and do not delete the backup."),
    ("03-self-correction", VOICES[2], "Please set the reminder for Friday—actually, make that Thursday."),
    ("04-person-name", VOICES[0], "Send the revised agenda to Siobhan McKenzie before lunch."),
    ("05-config", VOICES[1], "Open the config dot json file and change the retry count to three."),
    ("06-url", VOICES[2], "Go to example dot com slash changelog and read the release notes."),
    ("07-date-time", VOICES[0], "The appointment is October nineteenth, twenty twenty-six, at three forty-five p.m."),
    ("08-money-number", VOICES[1], "The total is one thousand two hundred fifty dollars and fifty cents."),
    ("09-version-port", VOICES[2], "The build is version two point four point one, running on port eight thousand eighty."),
    ("10-acronym", VOICES[0], "Ask the SRE team to check the API before the next deploy."),
    ("11-final-word", VOICES[1], "The last word in this recording is sapphire."),
    ("12-homophones", VOICES[2], "Their new release is over there, and they are ready to ship it."),
    ("13-technical-name", VOICES[0], "Maya Chen will review the PostgreSQL migration after lunch."),
    ("14-contrast", VOICES[1], "Keep the feature enabled in staging, but disable it in production."),
    ("15-thank-you-tail", VOICES[2], "That is everything I needed. Thank you."),
    ("16-short-command", VOICES[0], "Copy the link, then stop recording."),
]

PARAGRAPHS = [
    (
        "17-paragraph-planning",
        VOICES[1],
        "Maya Chen is preparing the release plan for version two point four point one. "
        "The build is ready, but the team must not deploy it before the security review. "
        "On October nineteenth, twenty twenty-six, Siobhan will check the config dot json "
        "file and confirm that the retry limit is three. The service should listen on port "
        "eight thousand eighty, and the public status page is example dot com slash status. "
        "The first report says the test passed on Friday; actually, it passed on Thursday. "
        "Please keep that correction in the release notes. If the database migration fails, "
        "stop the rollout and restore the backup. If it succeeds, send the summary to the "
        "SRE team. The final approval must come from Jordan Lee, and the last word in this "
        "message is complete.",
    ),
    (
        "18-paragraph-travel",
        VOICES[2],
        "I am calling about the reservation under the name Siobhan McKenzie. We are due "
        "to arrive at three forty-five p.m. on October nineteenth, twenty twenty-six, and "
        "our confirmation number is seven eight three one nine. The first email listed "
        "room four twelve, but the corrected room is four twenty one. Please do not cancel "
        "the booking, and do not charge the card twice. The total should be one thousand "
        "two hundred fifty dollars and fifty cents, including the late checkout fee. I "
        "will send the receipt to example dot com slash support after we arrive. If you "
        "need to reach me, ask for Maya Chen or Jordan Lee at the front desk. Please read "
        "the final note back to me: the car is blue, not green, and it should wait by the "
        "north entrance. That is the complete request.",
    ),
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def convert_speech(text: str, voice: str, destination: Path, ffmpeg: str) -> None:
    with tempfile.TemporaryDirectory(prefix="shoutout-say-") as temp_dir:
        temp = Path(temp_dir)
        source_text = temp / "speech.txt"
        source_audio = temp / "speech.aiff"
        source_text.write_text(text + "\n", encoding="utf-8")
        subprocess.run(["say", "-v", voice, "-r", "178", "-f", str(source_text), "-o", str(source_audio)], check=True, timeout=120)
        subprocess.run(
            [ffmpeg, "-nostdin", "-v", "error", "-y", "-i", str(source_audio),
             "-ac", "1", "-ar", str(SAMPLE_RATE), "-c:a", "pcm_s16le", str(destination)],
            check=True,
        )


def read_wav(path: Path) -> list[int]:
    with wave.open(str(path), "rb") as wav:
        if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) != (1, 2, SAMPLE_RATE):
            raise ValueError(f"unexpected WAV format: {path}")
        return list(array.array("h", wav.readframes(wav.getnframes())))


def write_wav(path: Path, samples: list[int]) -> None:
    pcm = array.array("h", samples)
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(path), "wb") as wav:
        wav.setparams((1, 2, SAMPLE_RATE, 0, "NONE", "not compressed"))
        wav.writeframes(pcm.tobytes())


def make_noisy(samples: list[int], snr_db: float, rng: random.Random) -> list[int]:
    rms = math.sqrt(sum(value * value for value in samples) / len(samples))
    noise_rms = rms / (10 ** (snr_db / 20))
    noisy = [round(sample + rng.gauss(0, noise_rms)) for sample in samples]
    return [max(-32768, min(32767, value)) for value in noisy]


def describe(path: Path, base: dict, kind: str, text: str, voice: str | None = None) -> dict:
    samples = read_wav(path)
    return {
        **base,
        "kind": kind,
        "source_text_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest() if text else None,
        "path": path.name,
        "text": text,
        "voice": voice,
        "sample_rate_hz": SAMPLE_RATE,
        "channels": 1,
        "sample_format": "pcm_s16le",
        "samples": len(samples),
        "duration_seconds": round(len(samples) / SAMPLE_RATE, 4),
        "sha256": sha256(path),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent / "fixtures")
    args = parser.parse_args()
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise SystemExit("ffmpeg is required to convert macOS say output to mono 16 kHz WAV")
    args.output.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, voice, text in [*PHRASES, *PARAGRAPHS]:
        path = args.output / f"{name}.wav"
        convert_speech(text, voice, path, ffmpeg)
        rows.append(describe(path, {"name": name, "reference": text, "source": "macOS say"}, "speech", text, voice))

    derived = [
        ("quiet-01-save-file", "01-save-file", "quiet", -20.0),
        ("quiet-17-paragraph-planning", "17-paragraph-planning", "quiet", -20.0),
        ("noisy-02-negation", "02-negation", "noisy", 15.0),
        ("noisy-18-paragraph-travel", "18-paragraph-travel", "noisy", 15.0),
    ]
    rng = random.Random(NOISE_SEED)
    for name, source_name, kind, level in derived:
        source = args.output / f"{source_name}.wav"
        samples = read_wav(source)
        path = args.output / f"{name}.wav"
        if kind == "quiet":
            changed = [round(sample * 10 ** (level / 20)) for sample in samples]
        else:
            changed = make_noisy(samples, level, rng)
        write_wav(path, changed)
        source_row = next(row for row in rows if row["name"] == source_name)
        rows.append(describe(
            path,
            {"name": name, "reference": source_row["reference"], "derived_from": source_name,
             "derived_from_sha256": source_row["sha256"],
             "source": "PCM attenuation" if kind == "quiet" else "seeded Gaussian noise mix",
             "level_db": level, "noise_seed": NOISE_SEED if kind == "noisy" else None},
            kind, source_row["reference"], source_row["voice"],
        ))

    silence_path = args.output / "control-silence.wav"
    write_wav(silence_path, [0] * (2 * SAMPLE_RATE))
    rows.append(describe(silence_path, {"name": "control-silence", "reference": ""}, "silence", ""))

    manifest = {
        "schema_version": 1,
        "purpose": "Fresh local TTS fixtures for app-path engine comparison; no ASR is run here.",
        "generator": "macOS say + ffmpeg, followed by deterministic PCM attenuation/noise",
        "macos_version": subprocess.run(["sw_vers", "-productVersion"], check=True,
            capture_output=True, text=True).stdout.strip(),
        "python_version": platform.python_version(),
        "sample_rate_hz": SAMPLE_RATE,
        "voice_rate_words_per_minute": 178,
        "voices": VOICES,
        "noise_seed": NOISE_SEED,
        "fixtures": rows,
    }
    manifest_path = args.output / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    summary = {
        "manifest": str(manifest_path),
        "fixture_count": len(rows),
        "counts": {kind: sum(row["kind"] == kind for row in rows)
                   for kind in sorted({row["kind"] for row in rows})},
        "speech_duration_seconds": round(sum(row["duration_seconds"] for row in rows if row["kind"] == "speech"), 3),
        "all_duration_seconds": round(sum(row["duration_seconds"] for row in rows), 3),
        "macos_version": manifest["macos_version"],
        "python_version": manifest["python_version"],
        "voices": VOICES,
        "fixtures": [{"name": row["name"], "duration_seconds": row["duration_seconds"], "sha256": row["sha256"]} for row in rows],
    }
    summary_path = args.output / "generation-summary.json"
    summary["manifest_sha256"] = sha256(manifest_path)
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
