#!/usr/bin/env python3
"""Tests for private fixture preparation and paired replay scheduling."""

import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest import mock
import wave


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("batch_compare", HERE / "batch_compare.py")
batch_compare = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(batch_compare)


def write_wav(path: Path, seconds: float) -> None:
    with wave.open(str(path), "wb") as audio:
        audio.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
        audio.writeframes(b"\0\0" * int(seconds * 16000))


FAKE_APP = '''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import time

args = sys.argv[2:]
state = Path(os.environ["SHOUTOUT_TEST_STATE"])
state.mkdir(exist_ok=True)
suite = os.environ.get("SHOUTOUT_CLI_SUITE", "live")
profile = state / (suite + ".json")
if args == ["capabilities"]:
    version = "1" if os.environ.get("SHOUTOUT_TEST_LEGACY") else "2"
    print(json.dumps({"ok": True, "values": {"replaySchemaVersion": version}}))
elif args == ["status"]:
    print(json.dumps({"ok": True, "values": {"cleanup": "true", "style": "casual"}}))
elif args[:2] == ["settings", "set"]:
    saved = json.loads(profile.read_text()) if profile.exists() else {}
    saved[args[2]] = args[3]
    profile.write_text(json.dumps(saved))
    print(json.dumps({"ok": True, "values": saved}))
elif args[0] == "replay":
    assert "SHOUTOUT_CONTROL_SOCKET" not in os.environ
    assert os.environ["SHOUTOUT_REPLAY_DICTIONARY"]
    saved = json.loads(profile.read_text())
    assert saved["cleanup"] == "on" and saved["style"] == "casual"
    manifest = json.loads(Path(args[1]).read_text())
    output = Path(args[args.index("--output") + 1])
    start = time.monotonic()
    time.sleep(0.14)
    if os.environ.get("SHOUTOUT_TEST_FAIL") == saved["streaming"] and "--paced" not in args:
        output.write_text(json.dumps([{"name": manifest[0]["name"]}]))
        raise SystemExit(2)
    rows = [{"name": row["name"], "status": "completed", "finalText": "test",
             "replaySchemaVersion": 2}
            for row in manifest]
    if os.environ.get("SHOUTOUT_TEST_ROW_FAILURE") == saved["streaming"]:
        rows[-1]["status"] = "failed"
        rows[-1]["error"] = "synthetic replay failure"
    output.write_text(json.dumps(rows))
    events = state / "events.jsonl"
    with events.open("a") as log:
        log.write(json.dumps({"output": output.name, "start": start,
                              "end": time.monotonic(), "streaming": saved["streaming"]}) + "\\n")
else:
    raise SystemExit(3)
'''


class BatchCompareTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.folder = self.root / "input"
        self.folder.mkdir()
        write_wav(self.folder / "short.wav", 0.5)
        write_wav(self.folder / "long.wav", 1.0)
        self.app = self.root / "ShoutOut.app"
        binary = self.app / "Contents/MacOS/ShoutOut"
        binary.parent.mkdir(parents=True)
        binary.write_text(FAKE_APP)
        binary.chmod(0o700)
        self.state = self.root / "state"
        self.state.mkdir()
        self.dictionary = self.root / "dictionary.json"
        self.dictionary.write_text('[]')

    def args(self, *extra):
        return batch_compare.make_parser().parse_args([
            "--folder", str(self.folder), "--output", str(self.root / "output"),
            "--app", str(self.app), "--dictionary", str(self.dictionary), *extra,
        ])

    def test_normalized_audio_is_shared_and_phase_order_is_controlled(self):
        with mock.patch.object(batch_compare, "INSTALLED_APP", self.app), mock.patch.dict(
            os.environ, {"SHOUTOUT_TEST_STATE": str(self.state), "SHOUTOUT_CONTROL_SOCKET": "unused"}
        ):
            run_path, status = batch_compare.compare(self.args("--latency-rounds", "2"))
        self.assertEqual(status, 0)
        run = json.loads(run_path.read_text())
        self.assertEqual(run["status"], "completed")
        self.assertTrue((run_path.parent / "comparison.html").is_file())
        self.assertEqual(run["profile"], {"cleanup": True, "style": "casual", "dictionaryEntries": 0})
        self.assertEqual(len(run["fixtures"]), 2)
        self.assertEqual(set(run["phases"]["latency"]["fixtureNames"]), {"short", "long"})
        for fixture in run["fixtures"]:
            self.assertEqual(batch_compare.sha256(run_path.parent / fixture["path"]), fixture["sha256"])
            self.assertEqual((run_path.parent / fixture["path"]).stat().st_mode & 0o777, 0o600)
        self.assertEqual((run_path.parent / "quality-manifest.json").stat().st_mode & 0o777, 0o600)
        self.assertEqual(run_path.parent.stat().st_mode & 0o777, 0o700)
        quality_manifest = json.loads((run_path.parent / "quality-manifest.json").read_text())
        self.assertEqual(quality_manifest[0]["name"], "warmup-not-scored")
        self.assertEqual(quality_manifest[1]["path"], quality_manifest[0]["path"])
        events = [json.loads(line) for line in (self.state / "events.jsonl").read_text().splitlines()]
        quality = [event for event in events if event["output"].startswith("quality-")]
        self.assertEqual(len(quality), 2)
        self.assertLess(max(event["start"] for event in quality), min(event["end"] for event in quality))
        latency = [event for event in events if event["output"].startswith("latency-")]
        self.assertEqual([event["output"] for event in latency], [
            "latency-0-parakeet.json", "latency-0-hexStreaming.json",
            "latency-1-hexStreaming.json", "latency-1-parakeet.json",
        ])
        self.assertTrue(all(first["end"] <= second["start"] for first, second in zip(latency, latency[1:])))

    def test_partial_failure_keeps_results_and_marks_run_failed(self):
        with mock.patch.object(batch_compare, "INSTALLED_APP", self.app), mock.patch.dict(
            os.environ, {"SHOUTOUT_TEST_STATE": str(self.state), "SHOUTOUT_TEST_FAIL": "on"}
        ):
            run_path, status = batch_compare.compare(self.args("--skip-latency"))
        run = json.loads(run_path.read_text())
        self.assertEqual(status, 1)
        self.assertEqual(run["status"], "failed")
        self.assertIn("hexStreaming", run["phases"]["quality"]["errors"])
        self.assertTrue((run_path.parent / "quality-parakeet.json").is_file())
        self.assertEqual(len(json.loads((run_path.parent / "quality-hexStreaming.json").read_text())), 1)
        self.assertTrue((run_path.parent / "quality-hexStreaming.log").is_file())

    def test_old_app_is_rejected_before_replay(self):
        with mock.patch.object(batch_compare, "INSTALLED_APP", self.app), mock.patch.dict(
            os.environ, {"SHOUTOUT_TEST_STATE": str(self.state), "SHOUTOUT_TEST_LEGACY": "1"}
        ):
            with self.assertRaisesRegex(RuntimeError, "lacks replay schema v2 diagnostics"):
                batch_compare.compare(self.args())
        self.assertFalse((self.root / "output/run.json").exists())

    def test_per_clip_failure_marks_phase_failed_even_when_process_exits_zero(self):
        with mock.patch.object(batch_compare, "INSTALLED_APP", self.app), mock.patch.dict(
            os.environ, {"SHOUTOUT_TEST_STATE": str(self.state), "SHOUTOUT_TEST_ROW_FAILURE": "on"}
        ):
            run_path, status = batch_compare.compare(self.args("--skip-latency"))
        run = json.loads(run_path.read_text())
        self.assertEqual(status, 1)
        self.assertIn("hexStreaming", run["phases"]["quality"]["errors"])
        self.assertIn("fixture", run["phases"]["quality"]["errors"]["hexStreaming"])

    def test_history_source_is_generated_automatically(self):
        generated = []
        module = types.ModuleType("history_fixtures")

        def generate(output_dir, count):
            generated.append((output_dir, count))
            output_dir.mkdir()
            manifest = output_dir / "manifest.json"
            manifest.write_text(json.dumps([{"name": "personal-clip", "path": str(self.folder / "short.wav"),
                                             "reference": "A private reference", "source": "local-history-tts"}]))
            return manifest

        module.generate_history_fixtures = generate
        output = self.root / "output"
        output.mkdir()
        with mock.patch.dict(sys.modules, {"history_fixtures": module}):
            rows = batch_compare.source_rows(
                batch_compare.make_parser().parse_args(["--history", "--history-count", "7"]), output)
        self.assertEqual(generated, [(output / "history-source", 7)])
        self.assertEqual(rows[0]["reference"], "A private reference")
        self.assertEqual(rows[0]["source"], "local-history-tts")

    def test_folder_names_include_relative_directories(self):
        (self.folder / "one").mkdir()
        (self.folder / "two").mkdir()
        write_wav(self.folder / "one/same.wav", 0.2)
        write_wav(self.folder / "two/same.wav", 0.2)
        args = batch_compare.make_parser().parse_args(["--folder", str(self.folder)])
        rows = batch_compare.source_rows(args, self.root / "output")
        self.assertIn("one/same", [row["name"] for row in rows])
        self.assertIn("two/same", [row["name"] for row in rows])

    def test_candidate_selection_prefers_explicit_then_env_then_local_candidate(self):
        candidate = self.root / "candidate/ShoutOut.app"
        binary = candidate / "Contents/MacOS/ShoutOut"
        binary.parent.mkdir(parents=True)
        binary.write_text("test")
        with mock.patch.object(batch_compare, "CANDIDATE_APP", candidate), mock.patch.object(
            batch_compare, "INSTALLED_APP", self.app
        ):
            with mock.patch.dict(os.environ, {}, clear=True):
                self.assertEqual(batch_compare.selected_app(None), candidate.resolve())
            with mock.patch.dict(os.environ, {"SHOUTOUT_COMPARE_APP": str(self.app)}):
                self.assertEqual(batch_compare.selected_app(None), self.app.resolve())
                self.assertEqual(batch_compare.selected_app(candidate), candidate.resolve())

    def test_invalid_dictionary_entry_is_rejected_before_replay(self):
        self.dictionary.write_text('[{"id":"bad", "phrase":"name", "aliases":["alias"]}]')
        with self.assertRaisesRegex(ValueError, "invalid UUID"):
            batch_compare.snapshot_dictionary(self.dictionary, self.root, required=True)


if __name__ == "__main__":
    unittest.main()
