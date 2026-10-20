#!/usr/bin/env python3
"""Compare both ShoutOut ASR engines on one frozen, local audio set."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid
import wave


HERE = Path(__file__).resolve().parent
REPO_ROOT = Path(__file__).resolve().parents[3]
INSTALLED_APP = Path.home() / "Applications/ShoutOut.app"
CANDIDATE_APP = REPO_ROOT / ".local-evals/batch-comparison-candidate/ShoutOut.app"
DICTIONARY = Path.home() / "Library/Application Support/com.ezraapple.shoutout/dictionary.json"
OUTPUT_ROOT = Path.home() / "Library/Application Support/com.ezraapple.shoutout/comparisons"
ENGINES = {"parakeet": "off", "hexStreaming": "on"}
AUDIO_EXTENSIONS = {".wav", ".m4a", ".mp3", ".aif", ".aiff", ".caf", ".flac", ".aac"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, value: object) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(path)


def executable(app: Path) -> Path:
    binary = app / "Contents/MacOS/ShoutOut"
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise ValueError(f"ShoutOut executable not found in {app}")
    return binary


def selected_app(requested: Path | None) -> Path:
    if requested is not None:
        return requested.expanduser().resolve()
    if os.environ.get("SHOUTOUT_COMPARE_APP"):
        return Path(os.environ["SHOUTOUT_COMPARE_APP"]).expanduser().resolve()
    if (CANDIDATE_APP / "Contents/MacOS/ShoutOut").is_file():
        return CANDIDATE_APP.resolve()
    return INSTALLED_APP.resolve()


def require_replay_diagnostics(binary: Path) -> None:
    result = subprocess.run([str(binary), "--cli", "capabilities"], capture_output=True,
                            text=True, timeout=15)
    try:
        response = json.loads(result.stdout)
    except json.JSONDecodeError:
        response = {}
    if (result.returncode or not response.get("ok") or
            response.get("values", {}).get("replaySchemaVersion") != "2"):
        raise RuntimeError(
            f"{binary} lacks replay schema v2 diagnostics. Build the comparison app "
            "and pass its .app bundle with --app."
        )


def profile_from_live_app(live_binary: Path) -> dict:
    # No private suite here: status reads the installed app or its live socket.
    environment = dict(os.environ)
    environment.pop("SHOUTOUT_CLI_SUITE", None)
    environment.pop("SHOUTOUT_CONTROL_SOCKET", None)
    result = subprocess.run([str(live_binary), "--cli", "status"], capture_output=True,
                            text=True, timeout=30, check=True, env=environment)
    response = json.loads(result.stdout)
    if not response.get("ok"):
        raise RuntimeError(response.get("message", "Live status failed"))
    values = response["values"]
    cleanup = values["cleanup"].lower()
    if cleanup not in ("true", "false"):
        raise ValueError(f"Unexpected cleanup status: {cleanup}")
    return {"cleanup": cleanup == "true", "style": values["style"]}


def private_directory(path: Path) -> Path:
    if path.exists() and any(path.iterdir()):
        raise ValueError(f"Output directory already contains files: {path}")
    path.mkdir(parents=True, mode=0o700, exist_ok=True)
    path.chmod(0o700)
    return path.resolve()


def source_rows(args: argparse.Namespace, output_dir: Path) -> list[dict]:
    if args.history:
        from history_fixtures import generate_history_fixtures
        manifest = generate_history_fixtures(output_dir / "history-source", count=args.history_count)
        return rows_from_manifest(Path(manifest))
    if args.folder:
        folder = args.folder.resolve()
        if not folder.is_dir():
            raise ValueError(f"Audio folder not found: {folder}")
        paths = sorted(path for path in folder.rglob("*") if path.is_file()
                       and path.suffix.lower() in AUDIO_EXTENSIONS
                       and not path.resolve().is_relative_to(output_dir))
        return [{"name": path.relative_to(folder).with_suffix("").as_posix(),
                 "path": str(path)} for path in paths]
    manifest = args.manifest
    if manifest is None:
        manifest = HERE / "fixtures/manifest.json"
        if not manifest.is_file():
            subprocess.run([sys.executable, str(HERE / "generate_fixtures.py")],
                           check=True, stdout=subprocess.DEVNULL, timeout=600)
    return rows_from_manifest(manifest)


def rows_from_manifest(manifest: Path) -> list[dict]:
    manifest = manifest.resolve()
    data = json.loads(manifest.read_text(encoding="utf-8"))
    rows = data["fixtures"] if isinstance(data, dict) else data
    if not isinstance(rows, list):
        raise ValueError("Manifest must contain a fixture array")
    result = []
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("path"), str):
            raise ValueError("Each fixture needs a path")
        path = (manifest.parent / row["path"]).resolve()
        if not path.is_file():
            raise ValueError(f"Audio file not found: {path}")
        if row.get("sha256") and sha256(path) != row["sha256"]:
            raise ValueError(f"Audio hash mismatch: {path}")
        fixture = {"name": row.get("name") or path.stem, "path": str(path),
                   "reference": row.get("reference", row.get("text", ""))}
        for key in ("source", "voice", "wordCount", "kind"):
            if key in row:
                fixture[key] = row[key]
        result.append(fixture)
    return result


def normalize(rows: list[dict], output_dir: Path) -> list[dict]:
    if not rows:
        raise ValueError("No audio fixtures found")
    normalized_dir = private_directory(output_dir / "audio")
    names = set()
    fixtures = []
    for index, row in enumerate(rows):
        name = str(row["name"])
        if not name.strip() or name.casefold().startswith("warmup") or name in names:
            raise ValueError(f"Fixture names must be unique and nonempty: {name!r}")
        names.add(name)
        source = Path(row["path"]).resolve()
        if not source.is_file():
            raise ValueError(f"Audio file not found: {source}")
        safe_name = re.sub(r"[^a-zA-Z0-9_-]+", "-", name).strip("-")[:64] or "audio"
        path = normalized_dir / f"{index:03d}-{safe_name}.wav"
        result = subprocess.run(["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16@16000",
                                 "-c", "1", str(source), str(path)], capture_output=True,
                                text=True, timeout=180)
        if result.returncode:
            raise RuntimeError(f"Could not normalize {source}: {result.stderr.strip()}")
        with wave.open(str(path), "rb") as audio:
            if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) != (1, 2, 16000):
                raise ValueError(f"Unexpected normalized WAV format: {path}")
            seconds = audio.getnframes() / 16000
        if seconds <= 0:
            raise ValueError(f"Empty audio fixture: {source}")
        fixture = {"name": name, "path": str(path.relative_to(output_dir)),
                   "sha256": sha256(path), "audioSeconds": round(seconds, 6)}
        if row.get("reference") is not None:
            fixture["reference"] = str(row["reference"])
        for key in ("source", "voice", "wordCount", "kind"):
            if key in row:
                fixture[key] = row[key]
        fixtures.append(fixture)
    return fixtures


def latency_subset(fixtures: list[dict], limit: int) -> list[dict]:
    if limit <= 0:
        raise ValueError("Latency limit must be positive")
    ranked = sorted(fixtures, key=lambda row: row["audioSeconds"])
    count = min(limit, len(ranked))
    if count == 1:
        return [ranked[-1]]
    indices = [round(index * (len(ranked) - 1) / (count - 1)) for index in range(count)]
    return [ranked[index] for index in indices]


def replay_manifest(output_dir: Path, name: str, fixtures: list[dict]) -> Path:
    path = output_dir / name
    rows = [dict(fixtures[0], name="warmup-not-scored"), *fixtures]
    write_json(path, [{"name": row["name"], "path": str(output_dir / row["path"]),
                       "reference": row.get("reference", "")} for row in rows])
    return path


def snapshot_dictionary(source: Path, output_dir: Path, required: bool = False) -> tuple[Path, int]:
    if required and not source.is_file():
        raise ValueError(f"Dictionary file not found: {source}")
    entries = json.loads(source.read_text(encoding="utf-8")) if source.is_file() else []
    if not isinstance(entries, list):
        raise ValueError("Dictionary must be a JSON array")
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("phrase"), str) or not isinstance(entry.get("aliases"), list):
            raise ValueError("Dictionary entries need phrase and aliases")
        try:
            uuid.UUID(entry["id"])
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError("Dictionary entry has an invalid UUID") from error
        if not all(isinstance(alias, str) for alias in entry["aliases"]):
            raise ValueError("Dictionary aliases must be strings")
    path = output_dir / "dictionary.json"
    write_json(path, entries)
    return path, len(entries)


def configure_suite(binary: Path, suite: str, profile: dict, streaming: str, environment: dict) -> None:
    settings = (("cleanup", "on" if profile["cleanup"] else "off"),
                ("style", profile["style"]), ("streaming", streaming))
    for key, value in settings:
        result = subprocess.run([str(binary), "--cli", "settings", "set", key, value],
                                env=environment, capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise RuntimeError(f"Could not set isolated {suite} {key}: {result.stderr.strip()}")


def timeout_for(fixtures: list[dict], paced: bool, override: float | None) -> float:
    if override is not None:
        return override
    seconds = sum(row["audioSeconds"] for row in fixtures)
    return max(300.0, seconds * (1.5 if paced else 4.0) + len(fixtures) * 25 + 180)


def launch_replay(binary: Path, suite: str, dictionary: Path, manifest: Path,
                  output: Path, paced: bool) -> tuple[subprocess.Popen, object]:
    env = dict(os.environ)
    env.pop("SHOUTOUT_CONTROL_SOCKET", None)
    env["SHOUTOUT_CLI_SUITE"] = suite
    env["SHOUTOUT_REPLAY_DICTIONARY"] = str(dictionary)
    log = output.with_suffix(".log").open("w", encoding="utf-8")
    command = [str(binary), "--cli", "replay", str(manifest), "--output", str(output)]
    if paced:
        command.append("--paced")
    try:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
    except BaseException:
        log.close()
        raise
    return process, log


def finish_process(process: subprocess.Popen, log: object, deadline: float) -> str | None:
    remaining = max(0, deadline - time.monotonic())
    try:
        return_code = process.wait(timeout=remaining)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        log.close()
        return "Timed out; partial replay output was saved"
    log.close()
    if return_code:
        return f"Replay exited {return_code}; see {Path(log.name).name}"
    return None


def validate_output(output: Path, expected_names: list[str]) -> str | None:
    if not output.is_file():
        return "Replay returned without a result file"
    try:
        rows = json.loads(output.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return f"Replay result could not be read: {error}"
    if not isinstance(rows, list) or len(rows) != len(expected_names):
        count = len(rows) if isinstance(rows, list) else "invalid"
        return f"Incomplete replay: {count} of {len(expected_names)} rows"
    if any(not isinstance(row, dict) or row.get("replaySchemaVersion") != 2 for row in rows):
        return "Replay output lacks schema v2 rows"
    names = [row.get("name") for row in rows]
    if names != expected_names:
        return "Replay output has missing, duplicate, or reordered fixture names"
    failed = [str(row.get("name")) for row in rows if row.get("status") not in
              ("completed", "silent", "lowInformation")]
    if failed:
        return f"Replay failed for {len(failed)} fixture(s): {', '.join(failed[:3])}"
    return None


def stop_process(process: subprocess.Popen, log: object) -> None:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    log.close()


def run_phase(binary: Path, suites: dict[str, str], dictionary: Path, manifest: Path,
              outputs: dict[str, Path], paced: bool, fixture_rows: list[dict],
              concurrent: bool, timeout_override: float | None) -> dict[str, str]:
    errors = {}
    if concurrent:
        active = {}
        try:
            for engine in ENGINES:
                process, log = launch_replay(binary, suites[engine], dictionary, manifest,
                                             outputs[engine], paced)
                active[engine] = (process, log, time.monotonic() + timeout_for(fixture_rows, paced, timeout_override))
            for engine, (process, log, deadline) in active.items():
                error = finish_process(process, log, deadline)
                if error is None:
                    error = validate_output(outputs[engine],
                                            ["warmup-not-scored", *[row["name"] for row in fixture_rows]])
                if error:
                    errors[engine] = error
        finally:
            for process, log, _ in active.values():
                if not log.closed:
                    stop_process(process, log)
    else:
        for engine in outputs:
            process, log = launch_replay(binary, suites[engine], dictionary, manifest,
                                         outputs[engine], paced)
            try:
                error = finish_process(process, log,
                                       time.monotonic() + timeout_for(fixture_rows, paced, timeout_override))
                if error is None:
                    error = validate_output(outputs[engine],
                                            ["warmup-not-scored", *[row["name"] for row in fixture_rows]])
                if error:
                    errors[engine] = error
            finally:
                if not log.closed:
                    stop_process(process, log)
    return errors


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="shoutout-compare", description=__doc__)
    sources = parser.add_mutually_exclusive_group()
    sources.add_argument("--manifest", type=Path, help="JSON fixture array or {fixtures: [...]}")
    sources.add_argument("--folder", type=Path, help="Scan a local audio folder recursively")
    sources.add_argument("--generated", action="store_true", help="Use bundled generated fixtures (default)")
    sources.add_argument("--history", action="store_true", help="Synthesize private fixtures from local dictation history")
    parser.add_argument("--history-count", type=int, default=18)
    parser.add_argument("--output", type=Path, help="New private output directory")
    parser.add_argument("--app", type=Path, help="Candidate ShoutOut.app bundle")
    parser.add_argument("--dictionary", type=Path)
    parser.add_argument("--skip-latency", action="store_true")
    parser.add_argument("--latency-limit", type=int, default=4)
    parser.add_argument("--latency-rounds", type=int, default=1)
    parser.add_argument("--timeout-seconds", type=float, help="Override each replay process timeout")
    return parser


def compare(args: argparse.Namespace) -> tuple[Path, int]:
    os.umask(0o077)
    if args.latency_rounds < 1 or args.latency_limit < 1 or args.history_count < 1:
        raise ValueError("Counts and limits must be positive")
    if args.timeout_seconds is not None and args.timeout_seconds <= 0:
        raise ValueError("Timeout must be positive")
    output_dir = private_directory(args.output or OUTPUT_ROOT / time.strftime("%Y%m%d-%H%M%S") / uuid.uuid4().hex[:8])
    candidate_app = selected_app(args.app)
    candidate = executable(candidate_app)
    require_replay_diagnostics(candidate)
    live = executable(INSTALLED_APP.resolve())
    profile = profile_from_live_app(live)
    dictionary, entry_count = snapshot_dictionary(
        (args.dictionary or DICTIONARY).expanduser(), output_dir, required=args.dictionary is not None)
    profile["dictionaryEntries"] = entry_count
    fixtures = normalize(source_rows(args, output_dir), output_dir)
    run = {
        "schemaVersion": 1,
        "app": {"path": str(candidate_app), "sha256": sha256(candidate)},
        "profile": profile,
        "fixtures": fixtures,
        "phases": {
            "quality": {"concurrent": True, "paced": False,
                        "outputs": {engine: f"quality-{engine}.json" for engine in ENGINES}, "errors": {}},
            "latency": {"concurrent": False, "paced": True, "rounds": 0 if args.skip_latency else args.latency_rounds,
                        "fixtureNames": [] if args.skip_latency else [row["name"] for row in latency_subset(fixtures, args.latency_limit)],
                        "outputs": {engine: [] for engine in ENGINES}, "errors": {}},
        },
        "limitations": ["Audio is file replay, not physical microphone capture or text insertion.",
                        "Paced replay simulates capture timing and the 80 ms hold-release tail.",
                        "Generated or history-synthesized references are TTS source text, not verified human speech."],
        "status": "running",
    }
    run_path = output_dir / "run.json"
    write_json(run_path, run)
    suites = {engine: f"ShoutOut.Compare.{uuid.uuid4().hex}" for engine in ENGINES}
    try:
        for engine, streaming in ENGINES.items():
            environment = dict(os.environ, SHOUTOUT_CLI_SUITE=suites[engine])
            environment.pop("SHOUTOUT_CONTROL_SOCKET", None)
            configure_suite(candidate, suites[engine], profile, streaming, environment)
        quality_manifest = replay_manifest(output_dir, "quality-manifest.json", fixtures)
        quality_outputs = {engine: output_dir / filename
                           for engine, filename in run["phases"]["quality"]["outputs"].items()}
        print("Quality: Parakeet and Hex streaming concurrently", flush=True)
        run["phases"]["quality"]["errors"] = run_phase(
            candidate, suites, dictionary, quality_manifest, quality_outputs, False,
            fixtures, True, args.timeout_seconds)
        write_json(run_path, run)
        if not args.skip_latency:
            selected = latency_subset(fixtures, args.latency_limit)
            for round_index in range(args.latency_rounds):
                ordered = selected if round_index % 2 == 0 else list(reversed(selected))
                manifest = replay_manifest(output_dir, f"latency-{round_index}-manifest.json", ordered)
                order = list(ENGINES) if round_index % 2 == 0 else list(reversed(ENGINES))
                for engine in order:
                    filename = f"latency-{round_index}-{engine}.json"
                    run["phases"]["latency"]["outputs"][engine].append(filename)
                    print(f"Latency round {round_index + 1}: {engine}", flush=True)
                    errors = run_phase(candidate, suites, dictionary, manifest,
                                       {engine: output_dir / filename}, True, ordered,
                                       False, args.timeout_seconds)
                    if errors:
                        run["phases"]["latency"]["errors"][filename] = errors[engine]
                    write_json(run_path, run)
        failed = bool(run["phases"]["quality"]["errors"] or run["phases"]["latency"]["errors"])
        run["status"] = "failed" if failed else "completed"
    except KeyboardInterrupt:
        run["status"] = "interrupted"
    except Exception as error:
        run["status"] = "failed"
        run["phases"]["quality"]["errors"]["runner"] = str(error)
    finally:
        write_json(run_path, run)
        for suite in suites.values():
            subprocess.run(["/usr/bin/defaults", "delete", suite], capture_output=True, timeout=10)
        try:
            from batch_report import render_report
            report = render_report(output_dir)
            print(f"Report: {report}", flush=True)
        except Exception as error:
            run["status"] = "failed"
            run["limitations"].append(f"Report generation failed: {error}")
            write_json(run_path, run)
    print(f"Run: {run_path} ({run['status']})", flush=True)
    return run_path, 0 if run["status"] == "completed" else (130 if run["status"] == "interrupted" else 1)


def main() -> int:
    args = make_parser().parse_args()
    try:
        _, status = compare(args)
        return status
    except Exception as error:
        print(f"Comparison could not start: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
