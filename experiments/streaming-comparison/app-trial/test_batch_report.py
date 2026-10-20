#!/usr/bin/env python3
"""Focused checks for the local paired replay report."""

import json
from pathlib import Path
import tempfile
import unittest

from batch_report import render_report, word_errors


class BatchReportTests(unittest.TestCase):
    def test_lexical_word_errors(self):
        self.assertEqual(word_errors("Save notes.txt", "save notes txt"), (0, 3))
        self.assertEqual(word_errors("one two three", "one four"), (2, 3))
        self.assertEqual(word_errors("", "unexpected"), (1, 0))

    def test_pairs_by_name_and_keeps_missing_failed_and_unreferenced_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "audio").mkdir()
            for name in ("001% sample.wav", "002.wav", "003.wav", "004.wav"):
                (output / "audio" / name).write_bytes(b"synthetic audio placeholder")
            fixtures = [
                {"name": "first", "path": "audio/001% sample.wav", "reference": "Save the notes", "sha256": "a", "audioSeconds": 2.1,
                 "source": "local-history-tts", "voice": "Alex", "wordCount": 3},
                {"name": "second", "path": "audio/002.wav", "reference": "Two words", "sha256": "b", "audioSeconds": 1},
                {"name": "no-reference", "path": "audio/003.wav", "sha256": "c", "audioSeconds": 1},
                {"name": "missing", "path": "audio/004.wav", "reference": "Absent row", "sha256": "d", "audioSeconds": 1},
                {"name": "warmup-not-scored", "path": "audio/005.wav", "reference": "Ignore", "sha256": "e", "audioSeconds": 1},
            ]
            manifest = {"schemaVersion": 1, "app": {"path": "local", "sha256": "hash"},
                        "profile": {"cleanup": True, "style": "standard", "dictionaryEntries": 0},
                        "fixtures": fixtures,
                        "phases": {"quality": {"concurrent": True, "paced": False,
                                              "outputs": {"parakeet": "p.json", "hexStreaming": "h.json"},
                                              "errors": {"hexStreaming": "model warning"}},
                                   "latency": {"concurrent": False, "paced": True, "rounds": 1,
                                               "fixtureNames": ["first", "second", "no-reference", "missing"],
                                               "outputs": {"parakeet": ["lp.json"], "hexStreaming": ["lh.json"]},
                                               "errors": {}}},
                        "limitations": ["Local only"], "status": "interrupted"}
            (output / "run.json").write_text(json.dumps(manifest))
            def row(name, engine, raw, final, **extra):
                return {"name": name, "engine": engine, "status": "completed", "rawText": raw,
                        "finalText": final, "stopToSinkMs": 100, **extra}
            self._write(output, "p.json", [row("second", "parakeet", "Two words", "Two words"),
                                           row("first", "parakeet", "Save notes", "Save the notes"),
                                           row("no-reference", "parakeet", "Mystery", "Mystery"),
                                           row("warmup-not-scored", "parakeet", "Ignore", "Ignore")])
            self._write(output, "h.json", [row("first", "hexStreaming", "Save the notes", "Save <b>notes</b> </script>"),
                                           {"name": "second", "engine": "hexStreaming", "status": "failed",
                                            "error": "failed <script>alert(1)</script>", "stopToSinkMs": 9000},
                                           row("no-reference", "hexStreaming", "Mystery", "Different")])
            self._write(output, "lp.json", [row("first", "parakeet", "Save the notes", "Save the notes")])
            self._write(output, "lh.json", [row("first", "hexStreaming", "Save the notes", "Save the notes")])
            report = render_report(output)
            html = report.read_text()
            summary = json.loads((output / "summary.json").read_text())
            self.assertEqual(summary["fixtureCount"], 4)
            self.assertEqual(summary["rowCount"], 8)
            self.assertEqual(summary["metrics"]["quality"]["parakeet"]["rawASR"],
                             {"errors": 1, "words": 5, "clips": 2, "wer": .2})
            self.assertEqual(summary["metrics"]["quality"]["hexStreaming"]["rawASR"],
                             {"errors": 0, "words": 3, "clips": 1, "wer": 0})
            self.assertEqual(summary["metrics"]["quality"]["hexStreaming"]["statuses"],
                             {"completed": 2, "failed": 1, "missing": 1})
            self.assertEqual(summary["metrics"]["quality"]["hexStreaming"]["withoutReference"], 1)
            self.assertEqual(summary["metrics"]["quality"]["hexStreaming"]["medianStopToSinkMs"], 100)
            self.assertEqual(summary["metrics"]["quality"]["hexStreaming"]["timedClips"], 2)
            self.assertNotIn("warmup-not-scored", html)
            self.assertIn('src="audio/001%25%20sample.wav"', html)
            self.assertIn("Synthetic from local history", html)
            self.assertIn("generated-text references", html)
            self.assertIn("&lt;script&gt;alert(1)&lt;/script&gt;", html)
            self.assertNotIn("<script>alert(1)</script>", html)
            self.assertIn("&lt;/script&gt;", html)
            self.assertIn("<mark>", html)
            self.assertIn('<details class="pipeline"><summary>Pipeline details</summary>', html)
            self.assertIn('<dl class="stages primary-stages"><dt>Raw ASR</dt>', html)
            self.assertIn('<dt>Final text</dt>', html)
            self.assertIn('<p><b>Synthetic history audio:</b>', html)
            self.assertIn('<p><b>Two timing modes:</b>', html)
            self.assertIn("quality hexStreaming: model warning", summary["problems"])

    def test_legitimate_warmup_named_clip_remains_visible(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "audio").mkdir()
            (output / "audio" / "001.wav").write_bytes(b"audio placeholder")
            (output / "run.json").write_text(json.dumps({
                "schemaVersion": 1,
                "fixtures": [{"name": "warmup-demo", "path": "audio/001.wav", "reference": "Hello"},
                             {"name": "warmup-not-scored", "warmup": True}],
                "phases": {"quality": {"outputs": {"parakeet": "p.json", "hexStreaming": "h.json"}},
                           "latency": {"rounds": 0, "outputs": {"parakeet": [], "hexStreaming": []}}}}))
            for name in ("p.json", "h.json"):
                self._write(output, name, [{"name": "warmup-not-scored", "status": "completed"},
                                           {"name": "warmup-demo", "status": "completed",
                                            "rawText": "Hello", "finalText": "Hello", "stopToSinkMs": 50}])
            html = render_report(output).read_text()
            summary = json.loads((output / "summary.json").read_text())
            self.assertEqual(summary["fixtureCount"], 1)
            self.assertEqual(summary["rowCount"], 1)
            self.assertIn("warmup-demo", html)
            self.assertNotIn("warmup-not-scored", html)
            self.assertEqual(summary["metrics"]["quality"]["parakeet"]["final"]["clips"], 1)

    def test_missing_output_and_unsafe_audio_are_visible(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "run.json").write_text(json.dumps({
                "schemaVersion": 1, "fixtures": [{"name": "one", "path": "../secret.wav"}],
                "phases": {"quality": {"outputs": {"parakeet": "absent.json"}},
                           "latency": {"outputs": {}}}, "status": "failed"}))
            html = render_report(output).read_text()
            summary = json.loads((output / "summary.json").read_text())
            self.assertIn("Audio unavailable", html)
            self.assertNotIn("secret.wav", html)
            self.assertEqual(summary["metrics"]["quality"]["parakeet"]["statuses"], {"missing": 1})
            self.assertEqual(summary["metrics"]["quality"]["parakeet"]["rawASR"]["wer"], None)
            self.assertTrue(any("Could not read absent.json" in item for item in summary["problems"]))

    def test_mismatched_replay_metadata_is_not_scored(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "run.json").write_text(json.dumps({
                "schemaVersion": 1, "fixtures": [{"name": "one", "path": "audio/001.wav", "reference": "one word"}],
                "phases": {"quality": {"outputs": {"parakeet": "p.json", "hexStreaming": "h.json"}}}}))
            self._write(output, "p.json", [{"name": "one", "engine": "hexStreaming", "paced": True,
                                             "status": "completed", "rawText": "one word", "finalText": "one word",
                                             "cleanupFallback": "none", "fallbacks": 0}])
            self._write(output, "h.json", [])
            html = render_report(output).read_text()
            summary = json.loads((output / "summary.json").read_text())
            self.assertEqual(summary["metrics"]["quality"]["parakeet"]["statuses"], {"metadata mismatch": 1})
            self.assertIsNone(summary["metrics"]["quality"]["parakeet"]["rawASR"]["wer"])
            self.assertIn("metadata mismatch", html)
            self.assertIn("engine hexStreaming (expected parakeet)", html)
            self.assertIn("paced True (expected False)", html)
            self.assertIn('difference failure', html)

    def test_latency_subset_does_not_count_unselected_clips_as_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "run.json").write_text(json.dumps({
                "schemaVersion": 1,
                "fixtures": [{"name": "chosen", "path": "audio/001.wav"},
                             {"name": "other", "path": "audio/002.wav"}],
                "phases": {"quality": {"outputs": {}},
                           "latency": {"rounds": 1, "fixtureNames": ["chosen"],
                                       "outputs": {"parakeet": ["lp.json"], "hexStreaming": ["lh.json"]}}}}))
            self._write(output, "lp.json", [{"name": "chosen", "status": "completed"}])
            self._write(output, "lh.json", [{"name": "chosen", "status": "completed"}])
            render_report(output)
            summary = json.loads((output / "summary.json").read_text())
            self.assertEqual(summary["rowCount"], 3)
            self.assertEqual(summary["metrics"]["latency"]["parakeet"]["statuses"], {"completed": 1})
            self.assertEqual(summary["metrics"]["quality"]["parakeet"]["statuses"], {"missing": 2})

    @staticmethod
    def _write(output: Path, name: str, rows: list[dict]):
        (output / name).write_text(json.dumps(rows))


if __name__ == "__main__":
    unittest.main()
