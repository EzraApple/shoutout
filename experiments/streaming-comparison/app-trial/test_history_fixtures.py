"""Tests use invented text and stubbed TTS; no personal history is read."""

from __future__ import annotations

import importlib.util
import json
import stat
import subprocess
import tempfile
import unittest
import wave
from pathlib import Path
from unittest.mock import patch


MODULE_PATH = Path(__file__).with_name("history_fixtures.py")
SPEC = importlib.util.spec_from_file_location("history_fixtures", MODULE_PATH)
assert SPEC and SPEC.loader
fixtures = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fixtures)


def write_wav(path: Path) -> None:
    with wave.open(str(path), "wb") as audio:
        audio.setparams((1, 2, 16_000, 0, "NONE", "not compressed"))
        audio.writeframes(b"\x00\x00" * 160)


class FakeSpeechTools:
    def __init__(self) -> None:
        self.spoken: list[tuple[str, str]] = []
        self.calls: list[list[str]] = []
        self.fail_after: int | None = None

    def run(self, arguments: list[str], **kwargs) -> subprocess.CompletedProcess:
        self.calls.append(arguments)
        if arguments[:3] == ["/usr/bin/say", "-v", "?"]:
            return subprocess.CompletedProcess(arguments, 0, "Samantha en_US # Hello\nDaniel en_GB # Hello\nEddy (English (US)) en_US # Hello\nAlice it_IT # Ciao\n", "")
        if arguments[0] == "/usr/bin/say":
            if self.fail_after is not None and len(self.spoken) >= self.fail_after:
                return subprocess.CompletedProcess(arguments, 1, b"private source content", b"private source content")
            source = Path(arguments[arguments.index("-f") + 1])
            self.spoken.append((arguments[arguments.index("-v") + 1], source.read_text(encoding="utf-8")))
            Path(arguments[arguments.index("-o") + 1]).write_bytes(b"aiff")
            return subprocess.CompletedProcess(arguments, 0, b"", b"")
        if arguments[0] == "/usr/bin/afconvert":
            write_wav(Path(arguments[-1]))
            return subprocess.CompletedProcess(arguments, 0, b"", b"")
        raise AssertionError(arguments)


class HistoryFixtureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.output = root / ".local-evals/history"
        self.history = root / "history.json"
        self.tools = FakeSpeechTools()
        self.patch = patch.object(fixtures.subprocess, "run", side_effect=self.tools.run)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def save_history(self, entries: list[dict]) -> None:
        self.history.write_text(json.dumps(entries), encoding="utf-8")

    def test_private_manifest_exact_reference_and_cache(self) -> None:
        self.save_history([
            {"languagePassInput": " Do not send $HOME or `whoami`.", "text": "Edited output replaces the source."},
            {"languagePassInput": "Please review the API release at 12:30?", "text": "Edited output."},
            {"languagePassInput": "Do not send $HOME or `whoami`!", "text": "Duplicate output."},
            {"languagePassInput": "", "text": "Fallback text is spoken when input is blank."},
            {"languagePassInput": "Testing one two three", "text": "Unwanted test boilerplate."},
        ])
        manifest = fixtures.generate_history_fixtures(self.output, count=18, history_path=self.history)
        rows = json.loads(manifest.read_text(encoding="utf-8"))
        self.assertEqual(len(rows), 3)
        self.assertEqual({row["reference"] for row in rows}, {text for _, text in self.tools.spoken})
        self.assertIn("Do not send $HOME or `whoami`.", {row["reference"] for row in rows})
        self.assertEqual([voice for voice, _ in self.tools.spoken], ["Samantha", "Daniel", "Eddy (English (US))"])
        self.assertTrue(all(row["source"] == "local-history-tts" for row in rows))
        self.assertTrue(all(Path(row["path"]).is_relative_to(self.output.resolve()) for row in rows))
        self.assertTrue(all(stat.S_IMODE(Path(row["path"]).stat().st_mode) == 0o600 for row in rows))
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(self.output.parent.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(manifest.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE((self.output / "provenance.json").stat().st_mode), 0o600)
        self.assertEqual(len(self.tools.spoken), 3)
        self.assertEqual(fixtures.generate_history_fixtures(self.output, 18, self.history), manifest)
        self.assertEqual(len(self.tools.spoken), 3)
        self.assertFalse(any("$HOME" in " ".join(call) or "whoami" in " ".join(call) for call in self.tools.calls))

    def test_balances_lengths_and_covers_complexity_without_truncation(self) -> None:
        short = "Please send the file today."
        medium = "Please review the API before lunch and tell me if version 2 is ready to deploy in staging tomorrow. " * 2
        long = "This is a complete release planning note with several ordinary words and a long ending. " * 9
        self.save_history([{"languagePassInput": value} for value in [short, medium, long]])
        rows = json.loads(fixtures.generate_history_fixtures(self.output, 3, self.history).read_text())
        self.assertEqual([row["name"] for row in rows], ["history-short-01", "history-medium-01", "history-long-01"])
        self.assertEqual([row["reference"] for row in rows], [short, medium.strip(), long.strip()])
        self.assertEqual({row["wordCount"] for row in rows}, {5, len(medium.split()), len(long.split())})

    def test_selection_is_stable_and_covers_available_complexity(self) -> None:
        texts = [
            "Please save these ordinary meeting notes today.",
            "Can the API accept version 2 tomorrow?",
            "Do not send the draft to anyone yet.",
            "Actually, make that Thursday instead of Friday.",
            "The invoice total is 123 dollars today.",
            "Please read the revised project summary aloud.",
        ]
        self.save_history([{"languagePassInput": value} for value in texts])
        candidates = fixtures._candidate_texts(self.history)
        selected = fixtures._select(candidates, 5)
        reversed_selection = fixtures._select(list(reversed(candidates)), 5)
        self.assertEqual([row["textSHA256"] for row in selected], [row["textSHA256"] for row in reversed_selection])
        covered = set().union(*(row["features"] for row in selected))
        self.assertEqual(covered, {"technical", "numeric", "question", "negation", "correction"})

    def test_each_length_stratum_uses_all_three_voices(self) -> None:
        entries = []
        for index in range(6):
            for word_count in (10, 50, 110):
                text = " ".join(["Please", "review", "sample", str(index), *(["details"] * (word_count - 4))])
                entries.append({"languagePassInput": text})
        self.save_history(entries)
        rows = json.loads(fixtures.generate_history_fixtures(self.output, 18, self.history).read_text())
        self.assertEqual(len(rows), 18)
        for stratum in ("short", "medium", "long"):
            voices = [row["voice"] for row in rows if row["name"].startswith(f"history-{stratum}-")]
            self.assertEqual(len(voices), 6)
            self.assertEqual(set(voices), {"Samantha", "Daniel", "Eddy (English (US))"})
            self.assertEqual({voice: voices.count(voice) for voice in set(voices)},
                             {voice: 2 for voice in set(voices)})

    def test_changed_audio_and_selection_are_rejected(self) -> None:
        self.save_history([{"languagePassInput": "Please keep the complete draft ready."}])
        manifest = fixtures.generate_history_fixtures(self.output, 1, self.history)
        row = json.loads(manifest.read_text())[0]
        Path(row["path"]).write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "changed WAV"):
            fixtures.generate_history_fixtures(self.output, 1, self.history)
        write_wav(Path(row["path"]))
        self.save_history([{"languagePassInput": "Please use a different draft instead."}])
        with self.assertRaisesRegex(ValueError, "does not match"):
            fixtures.generate_history_fixtures(self.output, 1, self.history)

    def test_cached_audio_symlink_is_rejected_without_following_target(self) -> None:
        self.save_history([{"languagePassInput": "Please keep this invented sample private."}])
        row = json.loads(fixtures.generate_history_fixtures(self.output, 1, self.history).read_text())[0]
        audio_path = Path(row["path"])
        other_audio = Path(self.temporary.name) / "outside.wav"
        audio_path.replace(other_audio)
        audio_path.symlink_to(other_audio)
        with self.assertRaisesRegex(ValueError, "missing or changed WAV"):
            fixtures.generate_history_fixtures(self.output, 1, self.history)
        self.assertTrue(other_audio.is_file())

    def test_partial_manifest_survives_synthesis_error_without_text_in_error(self) -> None:
        self.save_history([
            {"languagePassInput": "Please copy this private sample safely."},
            {"languagePassInput": "Please send this second private sample."},
        ])
        self.tools.fail_after = 1
        with self.assertRaisesRegex(RuntimeError, "say failed with exit code 1") as caught:
            fixtures.generate_history_fixtures(self.output, 2, self.history)
        self.assertNotIn("private source content", str(caught.exception))
        self.assertEqual(len(json.loads((self.output / "manifest.json").read_text())), 1)
        self.assertEqual(json.loads((self.output / "provenance.json").read_text())["completedCount"], 1)
        self.tools.fail_after = None
        rows = json.loads(fixtures.generate_history_fixtures(self.output, 2, self.history).read_text())
        self.assertEqual(len(rows), 2)

    def test_private_output_required_and_long_entries_are_skipped(self) -> None:
        self.save_history([{"languagePassInput": "This entry is small enough to speak."}])
        with self.assertRaisesRegex(ValueError, "private"):
            fixtures.generate_history_fixtures(Path(self.temporary.name) / "public", 1, self.history)
        too_long = "one " * 501
        self.save_history([{"languagePassInput": too_long}])
        rows = json.loads(fixtures.generate_history_fixtures(self.output, 1, self.history).read_text())
        self.assertEqual(rows, [])
        self.assertFalse(self.tools.spoken)


if __name__ == "__main__":
    unittest.main()
