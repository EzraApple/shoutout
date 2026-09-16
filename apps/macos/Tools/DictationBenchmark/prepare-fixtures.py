#!/usr/bin/env python3
"""Create deterministic local audio fixtures, plus Whisper's public JFK sample."""
import hashlib
import json
from pathlib import Path
import random
import struct
import subprocess
import sys
import urllib.request
import wave

destination = Path(sys.argv[1]).resolve()
destination.mkdir(parents=True, exist_ok=True)
texts = {
    "short-request": "Can you send this over when you get a chance?",
    "correction": "I want to meet on Tuesday, wait, no, Monday, at three in the afternoon.",
    "technical": "Keep version two point zero and the database column unchanged. Please have a sub agent check localhost and review the pull request.",
    "filler": "Um, I think this is, like, ready to ship, but we should, uh, check the logs first.",
    "long": "Before we ship this update, please check the recording flow from beginning to end. Start with a short request, then try a longer recording with pauses between sentences. Make sure the final words are preserved when I release the key. Keep the original meaning and all of the technical details. I want the cleanup to remove repeated words and obvious fillers without turning my instructions into an answer. Also check that the history includes the final text and that the clipboard is restored after insertion. If the model cannot safely clean the transcript, keep the original text. We should review the results on Monday, actually, make that Tuesday afternoon.",
}
fixtures = []
for index, (name, text) in enumerate(texts.items()):
    voice = "Samantha" if index % 2 == 0 else "Daniel"
    text_path = destination / f"{name}.txt"
    text_path.write_text(text)
    path = destination / f"{name}.wav"
    subprocess.run(["say", "-v", voice, "-r", "185", "-o", str(path),
                    "--data-format=LEI16@16000", "-f", str(text_path)], check=True)
    fixtures.append(dict(name=name, path=path.name, reference=text, source=f"macOS say {voice}, 185 wpm"))

source = "https://raw.githubusercontent.com/openai/whisper/main/tests/jfk.flac"
jfk = destination / "jfk.flac"
urllib.request.urlretrieve(source, jfk)
fixtures.append(dict(name="jfk-natural", path=jfk.name,
    reference="And so my fellow Americans ask not what your country can do for you ask what you can do for your country.",
    source=source))

with wave.open(str(destination / "short-request.wav"), "rb") as audio:
    frames = audio.readframes(audio.getnframes())
randomizer = random.Random(42)
noisy = b"".join(struct.pack("<h", max(-32768, min(32767, sample + int(randomizer.gauss(0, 180)))))
                 for (sample,) in struct.iter_unpack("<h", frames))
for name, data, reference in [
    ("background-noise", noisy, texts["short-request"]),
    ("trailing-silence", frames + bytes(16000 * 2 * 3), texts["short-request"]),
    ("silence", bytes(16000 * 2 * 3), ""),
]:
    with wave.open(str(destination / f"{name}.wav"), "wb") as audio:
        audio.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
        audio.writeframes(data)
    fixtures.append(dict(name=name, path=f"{name}.wav", reference=reference, source="generated PCM"))

for fixture in fixtures:
    fixture["sha256"] = hashlib.sha256((destination / fixture["path"]).read_bytes()).hexdigest()
(destination / "manifest.json").write_text(json.dumps(fixtures, indent=2) + "\n")
print(destination / "manifest.json")
