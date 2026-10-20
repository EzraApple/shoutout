#!/usr/bin/env python3
"""Build a self-contained, local inspection report for paired app replay runs."""

from __future__ import annotations

from collections import Counter
from difflib import SequenceMatcher
from html import escape
import json
from pathlib import Path, PurePosixPath
import re
from statistics import median
from urllib.parse import quote


ENGINES = ("parakeet", "hexStreaming")
ENGINE_LABELS = {"parakeet": "Parakeet 1.1B", "hexStreaming": "Hex streaming 0.6B"}
STAGES = (
    ("rawText", "Raw ASR"),
    ("asrText", "ASR text"),
    ("dictionaryText", "Dictionary"),
    ("cleanupInput", "Cleanup input"),
    ("cleanupCandidate", "Cleanup candidate"),
    ("finalText", "Final text"),
)
DETAILS = (
    ("engineModel", "ASR model"),
    ("dictionaryEntries", "dictionary entries"),
    ("cleanupEnabled", "enabled"),
    ("cleanupAccepted", "accepted"),
    ("cleanupChanged", "changed"),
    ("cleanupFallback", "fallback"),
    ("cleanupStyle", "style"),
    ("cleanupModel", "model"),
    ("fallbacks", "ASR fallbacks"),
)
TIMES = (
    ("stopToSamplesMs", "Stop → samples"),
    ("stopToASRMs", "Stop → ASR"),
    ("engineWallMs", "ASR engine"),
    ("postProcessMs", "ASR postprocess"),
    ("modelWaitMs", "Model wait"),
    ("cleanupMs", "Cleanup"),
    ("stopToSinkMs", "Stop → local sink"),
    ("pipelineWallMs", "Full replay"),
)
TOKEN_RE = re.compile(r"\w+", re.UNICODE)


def words(value: object) -> list[str]:
    """Simple lexical normalization: Unicode words, case folded, punctuation split."""
    return TOKEN_RE.findall(str(value or "").casefold())


def word_errors(reference: object, hypothesis: object) -> tuple[int, int]:
    expected, actual = words(reference), words(hypothesis)
    previous = list(range(len(actual) + 1))
    for row_number, expected_word in enumerate(expected, 1):
        current = [row_number]
        for column, actual_word in enumerate(actual, 1):
            current.append(min(
                current[-1] + 1,
                previous[column] + 1,
                previous[column - 1] + (expected_word != actual_word),
            ))
        previous = current
    return previous[-1], len(expected)


def _load_rows(output_dir: Path, filename: object, problems: list[str]) -> list[dict]:
    if not isinstance(filename, str) or not filename:
        problems.append("Replay output filename is missing.")
        return []
    relative = PurePosixPath(filename)
    if relative.is_absolute() or ".." in relative.parts or "\\" in filename:
        problems.append(f"Unsafe replay output path: {filename}")
        return []
    path = output_dir / filename
    try:
        rows = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        problems.append(f"Could not read {filename}: {error}")
        return []
    if not isinstance(rows, list):
        problems.append(f"{filename} does not contain a row array.")
        return []
    valid = [row for row in rows if isinstance(row, dict)]
    if len(valid) != len(rows):
        problems.append(f"{filename} has {len(rows) - len(valid)} non-object rows.")
    return valid


def _warmup(item: dict) -> bool:
    return item.get("warmup") is True or item.get("name") == "warmup-not-scored"


def _audio_href(path: object) -> str | None:
    if not isinstance(path, str) or not path:
        return None
    relative = PurePosixPath(path)
    if (relative.is_absolute() or ".." in relative.parts or "\\" in path
            or ":" in relative.parts[0] or not path.startswith("audio/")):
        return None
    return quote(path, safe="/")


def _format_value(value: object) -> str:
    if value is None:
        return "—"
    if isinstance(value, bool):
        return "yes" if value else "no"
    if isinstance(value, float):
        return f"{value:.1f}"
    if isinstance(value, (list, dict)):
        return json.dumps(value, ensure_ascii=False)
    return str(value)


def _row_state(row: dict | None) -> str:
    if row is None:
        return "missing"
    return str(row.get("status") or "unknown")


def _is_scored(row: dict | None, reference: object) -> bool:
    return (row is not None and _row_state(row) in {"completed", "silent", "lowInformation"}
            and reference is not None and len(words(reference)) > 0)


def _index_rows(rows: list[dict], fixtures: dict[str, dict], problems: list[str],
                label: str, engine: str, paced: bool) -> dict[str, dict]:
    indexed: dict[str, dict] = {}
    for row in rows:
        if _warmup(row):
            continue
        name = row.get("name")
        if not isinstance(name, str) or not name:
            problems.append(f"{label}: replay row has no fixture name.")
            continue
        mismatches = []
        if row.get("engine") is not None and row["engine"] != engine:
            mismatches.append(f"engine {row['engine']} (expected {engine})")
        if row.get("paced") is not None and row["paced"] is not paced:
            mismatches.append(f"paced {row['paced']} (expected {paced})")
        if mismatches:
            problems.append(f"{label} {name}: metadata mismatch: {', '.join(mismatches)}.")
            row = {**row, "status": "metadata mismatch", "error": ", ".join(mismatches)}
        if name in indexed:
            problems.append(f"{label}: duplicate replay row for {name}; both rows are ambiguous.")
            indexed[name] = {"name": name, "status": "duplicate", "error": "Duplicate replay rows; cannot pair."}
        elif name not in fixtures:
            problems.append(f"{label}: unexpected replay row {name}.")
            indexed[name] = row
        else:
            indexed[name] = row
    return indexed


def _read_run(output_dir: Path) -> tuple[dict, list[str]]:
    manifest = json.loads((output_dir / "run.json").read_text(encoding="utf-8"))
    if not isinstance(manifest, dict) or manifest.get("schemaVersion") != 1:
        raise ValueError("run.json must be a schemaVersion 1 object")
    problems: list[str] = []
    fixtures = manifest.get("fixtures")
    if not isinstance(fixtures, list):
        raise ValueError("run.json fixtures must be an array")
    names = [row.get("name") for row in fixtures if isinstance(row, dict) and not _warmup(row)]
    duplicates = [name for name, count in Counter(names).items() if count > 1]
    if duplicates:
        raise ValueError(f"Duplicate fixture names cannot be paired: {duplicates}")
    return manifest, problems


def _expected_names(output_dir: Path, phase: dict, phase_name: str, round_index: int,
                    fixtures: dict[str, dict], problems: list[str]) -> list[str]:
    if phase_name == "quality":
        return list(fixtures)
    configured = phase.get("fixtureNames")
    if isinstance(configured, list):
        names = configured[round_index] if configured and isinstance(configured[0], list) and round_index < len(configured) else configured
        return [name for name in names if isinstance(name, str)]
    manifest = output_dir / f"latency-{round_index}-manifest.json"
    if manifest.is_file():
        return [row["name"] for row in _load_rows(output_dir, manifest.name, problems)
                if isinstance(row.get("name"), str) and not _warmup(row)]
    problems.append(f"latency round {round_index + 1}: expected fixture names unavailable; missing rows cannot be classified.")
    return []


def _collect(output_dir: Path, manifest: dict, problems: list[str]) -> tuple[list[dict], dict]:
    fixtures = {row["name"]: row for row in manifest["fixtures"]
                if isinstance(row, dict) and isinstance(row.get("name"), str) and not _warmup(row)}
    for name, fixture in fixtures.items():
        audio_path = fixture.get("path")
        if _audio_href(audio_path) is None:
            problems.append(f"{name}: normalized audio path is missing or unsafe.")
        elif not (output_dir / audio_path).is_file():
            problems.append(f"{name}: normalized audio file is missing: {audio_path}")
    phases = manifest.get("phases") or {}
    observations: list[dict] = []
    metrics: dict = {}
    for phase_name in ("quality", "latency"):
        phase = phases.get(phase_name) or {}
        for engine, error in (phase.get("errors") or {}).items():
            if error:
                problems.append(f"{phase_name} {engine}: {_format_value(error)}")
        outputs = phase.get("outputs") or {}
        rounds = 1
        if phase_name == "latency":
            rounds = max([int(phase.get("rounds", 0))] +
                         [len(value) for value in outputs.values() if isinstance(value, list)])
        phase_metrics = {engine: {"raw": {"errors": 0, "words": 0, "clips": 0},
                                  "final": {"errors": 0, "words": 0, "clips": 0},
                                  "statuses": Counter(), "timings": [], "noReference": 0}
                         for engine in ENGINES}
        for round_index in range(rounds):
            indexes = {}
            for engine in ENGINES:
                filenames = outputs.get(engine)
                filename = (filenames[round_index] if isinstance(filenames, list) and round_index < len(filenames)
                            else filenames if isinstance(filenames, str) and round_index == 0 else None)
                rows = _load_rows(output_dir, filename, problems) if filename else []
                indexes[engine] = _index_rows(rows, fixtures, problems,
                                              f"{phase_name} round {round_index + 1} {engine}",
                                              engine, phase_name == "latency")
                if filename is None:
                    problems.append(f"{phase_name} round {round_index + 1} {engine}: output missing.")
            # Include unexpected outputs as visible rows, but never mistake them for a fixture pair.
            expected = _expected_names(output_dir, phase, phase_name, round_index, fixtures, problems)
            names = expected + sorted((set(indexes[ENGINES[0]]) | set(indexes[ENGINES[1]])) - set(expected))
            for name in names:
                fixture = fixtures.get(name)
                reference = fixture.get("reference") if fixture else None
                rows = {engine: indexes[engine].get(name) for engine in ENGINES}
                observation = {"phase": phase_name, "round": round_index + 1,
                               "name": name, "fixture": fixture, "reference": reference,
                               "rows": rows, "unexpected": fixture is None,
                               "audioAvailable": bool(fixture and _audio_href(fixture.get("path")) and
                                                      (output_dir / fixture["path"]).is_file())}
                observations.append(observation)
                for engine, row in rows.items():
                    metric = phase_metrics[engine]
                    metric["statuses"][_row_state(row)] += 1
                    if reference is None:
                        metric["noReference"] += 1
                    if _is_scored(row, reference):
                        for field, key in (("rawText", "raw"), ("finalText", "final")):
                            if row.get(field) is not None:
                                errors, word_count = word_errors(reference, row[field])
                                metric[key]["errors"] += errors
                                metric[key]["words"] += word_count
                                metric[key]["clips"] += 1
                    if (_row_state(row) == "completed" and isinstance(row.get("stopToSinkMs"), (int, float))
                            and not isinstance(row["stopToSinkMs"], bool)):
                        metric["timings"].append(row["stopToSinkMs"])
        metrics[phase_name] = {}
        for engine, metric in phase_metrics.items():
            metrics[phase_name][engine] = {
                "statuses": dict(metric["statuses"]),
                "withoutReference": metric["noReference"],
                "rawASR": {**metric["raw"], "wer": metric["raw"]["errors"] / metric["raw"]["words"] if metric["raw"]["words"] else None},
                "final": {**metric["final"], "wer": metric["final"]["errors"] / metric["final"]["words"] if metric["final"]["words"] else None},
                "medianStopToSinkMs": median(metric["timings"]) if metric["timings"] else None,
                "timedClips": len(metric["timings"]),
            }
    return observations, metrics


def _highlight_pair(left: object, right: object) -> tuple[str, str]:
    """Mark differing lexical words; text and spacing remain escaped and intact."""
    def pieces(value: object) -> tuple[list[str], list[str]]:
        tokens = re.findall(r"\w+|\W+", str(value or ""), re.UNICODE)
        word_list = [token.casefold() for token in tokens if TOKEN_RE.fullmatch(token)]
        return tokens, word_list

    left_tokens, left_words = pieces(left)
    right_tokens, right_words = pieces(right)
    equal_left: set[int] = set()
    equal_right: set[int] = set()
    matcher = SequenceMatcher(None, left_words, right_words, autojunk=False)
    for a, b, size in matcher.get_matching_blocks():
        equal_left.update(range(a, a + size))
        equal_right.update(range(b, b + size))

    def markup(tokens: list[str], equal: set[int]) -> str:
        output, index = [], 0
        for token in tokens:
            if TOKEN_RE.fullmatch(token):
                safe = escape(token)
                output.append(safe if index in equal else f"<mark>{safe}</mark>")
                index += 1
            else:
                output.append(escape(token))
        return "".join(output) or '<span class="muted">empty</span>'
    return markup(left_tokens, equal_left), markup(right_tokens, equal_right)


def _card(row: dict | None, engine: str, highlighted_final: str, phase: str,
          reference: object) -> str:
    state = _row_state(row)
    if row is None:
        return f'<section class="engine"><h4>{ENGINE_LABELS[engine]} <span class="badge bad">missing</span></h4><p class="error">No replay row was written for this fixture.</p></section>'
    status_class = "ok" if state in {"completed", "silent", "lowInformation"} else "bad"
    content = [f'<section class="engine"><h4>{ENGINE_LABELS[engine]} <span class="badge {status_class}">{escape(state)}</span></h4>']
    if row.get("error"):
        content.append(f'<p class="error">{escape(_format_value(row["error"]))}</p>')
    if _is_scored(row, reference):
        scores = []
        for field, label in (("rawText", "Raw ASR"), ("finalText", "Final")):
            if row.get(field) is not None:
                errors, count = word_errors(reference, row[field])
                scores.append(f"{label}: {errors}/{count} word edits")
        content.append(f'<p class="clip-score">{" · ".join(scores) if scores else "Text fields unavailable for scoring"}</p>')
    else:
        content.append('<p class="clip-score muted">Reference score unavailable</p>')
    content.append('<dl class="stages primary-stages">')
    for field, label in (STAGES[0], STAGES[-1]):
        value = row.get(field)
        display = highlighted_final if field == "finalText" else escape(_format_value(value))
        content.append(f'<dt>{label}</dt><dd>{display}</dd>')
    content.append('</dl><details class="pipeline"><summary>Pipeline details</summary><dl class="stages">')
    for field, label in STAGES[1:-1]:
        content.append(f'<dt>{label}</dt><dd>{escape(_format_value(row.get(field)))}</dd>')
    content.append('</dl><div class="details">')
    for field, label in DETAILS:
        content.append(f'<span><b>{label}</b> {escape(_format_value(row.get(field)))}</span>')
    content.append('</div><div class="times">')
    timing_label = "Contended, unpaced stage timings" if phase == "quality" else "Serial, paced stage timings"
    content.append(f'<strong>{timing_label}</strong>')
    for field, label in TIMES:
        value = row.get(field)
        content.append(f'<span>{label}: {escape(_format_value(value))}{" ms" if isinstance(value, (int, float)) and not isinstance(value, bool) else ""}</span>')
    content.append('</div></details></section>')
    return "".join(content)


def _observation_html(observation: dict) -> str:
    fixture = observation["fixture"] or {}
    rows = observation["rows"]
    left, right = _highlight_pair((rows["parakeet"] or {}).get("finalText"),
                                  (rows["hexStreaming"] or {}).get("finalText"))
    phase = observation["phase"]
    states = [_row_state(rows[engine]) for engine in ENGINES]
    def has_fallback(value: object) -> bool:
        return str(value).strip().casefold() not in {"none", "false", "no", "0", "", "null"}
    fallbacks = any(has_fallback((rows[engine] or {}).get("cleanupFallback")) or
                    has_fallback((rows[engine] or {}).get("fallbacks")) for engine in ENGINES)
    differing = words((rows[ENGINES[0]] or {}).get("finalText")) != words((rows[ENGINES[1]] or {}).get("finalText"))
    failure = observation["unexpected"] or any(state not in {"completed", "silent", "lowInformation"} for state in states)
    tags = ["difference"] if differing else []
    if failure:
        tags.append("failure")
    if fallbacks:
        tags.append("fallback")
    href = _audio_href(fixture.get("path"))
    if not observation["audioAvailable"]:
        href = None
    audio = (f'<audio controls preload="none" src="{escape(href, quote=True)}"></audio>' if href else
             '<span class="muted">Audio unavailable</span>')
    reference = observation["reference"]
    reference_html = (f'<span>{escape(_format_value(reference))}</span>' if words(reference) else
                      '<span class="muted">No scorable reference words; error rate unavailable.</span>')
    note = '<span class="badge bad">unexpected output</span>' if observation["unexpected"] else ""
    source = fixture.get("source")
    if source == "local-history-tts":
        note += '<span class="badge">Synthetic from local history</span>'
    elif source:
        note += f'<span class="badge">{escape(_format_value(source))}</span>'
    voice = f' · voice {escape(_format_value(fixture["voice"]))}' if fixture.get("voice") is not None else ""
    word_count = f' · {escape(_format_value(fixture["wordCount"]))} words' if fixture.get("wordCount") is not None else ""
    return (f'<article class="clip" data-phase="{phase}" data-tags="{" ".join(tags)}">'
            f'<div class="clip-head"><div><h3>{escape(observation["name"])} {note}</h3>'
            f'<p>{phase.title()} · round {observation["round"]} · '
            f'{escape(_format_value(fixture.get("audioSeconds")))} s{word_count}{voice} · '
            f'SHA-256 {escape(_format_value(fixture.get("sha256")))}</p></div>{audio}</div>'
            f'<p class="reference"><b>Reference</b> {reference_html}</p>'
            f'<div class="engine-grid">{_card(rows["parakeet"], "parakeet", left, phase, reference)}'
            f'{_card(rows["hexStreaming"], "hexStreaming", right, phase, reference)}</div></article>')


def _metric_html(metrics: dict, phase: str) -> str:
    blocks = []
    for engine in ENGINES:
        item = metrics[phase][engine]
        raw, final = item["rawASR"], item["final"]
        def wer(stage: dict) -> str:
            return f'{stage["wer"] * 100:.2f}% · {stage["errors"]}/{stage["words"]} words · {stage["clips"]} clips' if stage["wer"] is not None else "N/A · no scored reference words"
        statuses = ", ".join(f"{escape(key)} {count}" for key, count in sorted(item["statuses"].items()))
        timing = f'{item["medianStopToSinkMs"]:.1f} ms ({item["timedClips"]} clips)' if item["medianStopToSinkMs"] is not None else "N/A"
        blocks.append(f'<div class="metric"><h3>{ENGINE_LABELS[engine]}</h3>'
                      f'<p><b>Raw ASR WER</b> {wer(raw)}</p><p><b>Final lexical WER</b> {wer(final)}</p>'
                      f'<p><b>Median completed stop → local sink</b> {timing}</p>'
                      f'<p><b>Rows</b> {statuses or "none"}; no reference: {item["withoutReference"]}</p></div>')
    return "".join(blocks)


CSS = """
:root{font-family:ui-sans-serif,system-ui,-apple-system,sans-serif;color:#182127;background:#f3f6f5}
*{box-sizing:border-box}body{margin:0}header{background:#132b30;color:#fff;padding:2.5rem max(2rem,calc((100vw - 1440px)/2))}h1{font-size:2rem;margin:0 0 .5rem}h2{margin:2rem 0 .7rem}h3{margin:.1rem 0 .4rem}h4{margin:.1rem 0 1rem;font-size:1.15rem}p{line-height:1.45;margin:.35rem 0}main{max-width:1500px;margin:auto;padding:1.5rem 2rem 5rem}.lede{color:#d5e5e3;max-width:70rem}.meta{display:flex;flex-wrap:wrap;gap:.5rem;margin-top:1.1rem}.meta span,.badge{border-radius:999px;padding:.25rem .6rem;background:#dce9e7;color:#17393a;font-size:.82rem}.meta span{background:#315158;color:#fff}.badge.ok{background:#d7f1df;color:#176239}.badge.bad{background:#ffe1db;color:#962e28}.notice{border-left:4px solid #d48d25;padding:.8rem 1rem;background:#fff8e8;margin:1rem 0}.summary-grid,.engine-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:1rem}.metric,.clip,.engine{background:#fff;border:1px solid #d7e0de;border-radius:12px}.metric{padding:1rem}.metric p{font-size:.9rem}.metric b{display:block;color:#41605f}.toolbar{position:sticky;top:0;z-index:2;background:#f3f6f5;padding:.8rem 0;display:flex;gap:.8rem;flex-wrap:wrap;align-items:center;border-bottom:1px solid #d4e0dc}.toolbar input{min-width:16rem;flex:1;padding:.7rem;border:1px solid #9bb3af;border-radius:8px;font:inherit}.toolbar select{padding:.65rem;border:1px solid #9bb3af;border-radius:8px;font:inherit}.toolbar label{white-space:nowrap}.clip{margin:1rem 0;padding:1.1rem}.clip-head{display:flex;justify-content:space-between;align-items:center;gap:1rem}.clip-head p{font-size:.82rem;color:#617777;overflow-wrap:anywhere}audio{max-width:270px}.reference{padding:.8rem;background:#f3f7f6;border-radius:7px;margin:.9rem 0;white-space:pre-wrap}.reference b{margin-right:.5rem}.engine{padding:1rem;min-width:0}.stages{display:grid;grid-template-columns:8rem minmax(0,1fr);gap:.35rem .8rem;margin:0}.stages dt{font-size:.8rem;color:#607774;padding:.45rem 0}.stages dd{margin:0;padding:.45rem 0;border-bottom:1px solid #eef1f0;white-space:pre-wrap;overflow-wrap:anywhere}.details,.times{display:flex;flex-wrap:wrap;gap:.35rem .7rem;margin-top:1rem;font-size:.8rem}.details span,.times span{background:#f2f6f5;padding:.28rem .45rem;border-radius:5px}.details b{color:#52706b}.times strong{width:100%;color:#355a58}.error{color:#a4362d;font-weight:600;overflow-wrap:anywhere}mark{background:#ffe08a;padding:0 .1em;border-radius:2px}.muted{color:#738786;font-style:italic}.empty{padding:2rem;text-align:center;color:#617777}[hidden]{display:none!important}@media(max-width:850px){.summary-grid,.engine-grid{grid-template-columns:1fr}.clip-head{display:block}audio{width:100%;max-width:none}.stages{grid-template-columns:6.5rem minmax(0,1fr)}main{padding:1rem}header{padding:2rem 1rem}}
.primary-stages{margin-bottom:.7rem}.pipeline{border-top:1px solid #d7e0de;padding-top:.6rem}.pipeline summary,.notice summary{cursor:pointer;color:#176565;font-weight:600}.pipeline[open] summary{margin-bottom:.7rem}
"""

JS = """
const search=document.querySelector('#search');
const phase=document.querySelector('#phase');
const mode=document.querySelector('#mode');
const cards=[...document.querySelectorAll('.clip')];
const count=document.querySelector('#visible-count');
function filter(){
  const query=search.value.trim().toLocaleLowerCase();
  let visible=0;
  for(const card of cards){
    const tags=card.dataset.tags.split(' ');
    const show=(!query||card.textContent.toLocaleLowerCase().includes(query)) &&
      (phase.value==='all'||card.dataset.phase===phase.value) &&
      (mode.value==='all'||tags.includes(mode.value));
    card.hidden=!show;
    if(show)visible++;
  }
  count.textContent=`${visible} of ${cards.length} rows`;
}
for(const control of [search,phase,mode])control.addEventListener(control===search?'input':'change',filter);
filter();
"""


def _render_html(manifest: dict, observations: list[dict], metrics: dict, problems: list[str]) -> str:
    app = manifest.get("app") or {}
    profile = manifest.get("profile") or {}
    limitations = manifest.get("limitations") or []
    extra_limits = [
        "Audio is the normalized file fed to the replay engines. This run does not measure physical microphone capture, resampling capture, key events, AX paste, or energy.",
        "Clips labeled Synthetic from local history are newly synthesized from sampled local transcription text. Their expected words are generated-text references, not the original speech ground truth. Synthetic voices do not reproduce the user's prosody, microphone, or background noise.",
        "Quality replays are concurrent and unpaced; their stage timings include contention and are not release latency. Latency replays are serial and paced.",
        "WER uses case-folded Unicode words with punctuation split. It does not equate spoken and written numbers or dates. Final WER can count legitimate cleanup rewrites.",
        "Transcript disagreement shows what to inspect; it does not establish which engine is correct. No reference means unknown error, not zero error.",
    ]
    status = escape(_format_value(manifest.get("status")))
    metadata = (
        f'<span>Status: {status}</span><span>App: {escape(_format_value(app.get("path")))}</span>'
        f'<span>App SHA-256: {escape(_format_value(app.get("sha256")))}</span>'
        f'<span>Cleanup: {escape(_format_value(profile.get("cleanup")))}</span>'
        f'<span>Style: {escape(_format_value(profile.get("style")))}</span>'
        f'<span>Dictionary entries: {escape(_format_value(profile.get("dictionaryEntries")))}</span>')
    if any(isinstance(fixture, dict) and fixture.get("source") == "local-history-tts"
           for fixture in manifest.get("fixtures", [])):
        metadata += '<span>Source: synthetic audio from local history</span>'
        source_note = ('<p><b>Synthetic history audio:</b> Expected words come from generated text. '
                       'These clips do not recreate the original speech or its noise and prosody.</p>')
    else:
        source_note = ""
    problem_html = "".join(f'<li>{escape(problem)}</li>' for problem in problems)
    if not problems:
        problem_html = '<li>None recorded.</li>'
    limits_html = "".join(f'<li>{escape(str(item))}</li>' for item in [*limitations, *extra_limits])
    cards = "".join(_observation_html(item) for item in observations)
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Streaming comparison</title><style>{CSS}</style></head><body>
<header><h1>Streaming comparison</h1><p class="lede">Paired local replay of the production collector, ASR, filters, dictionary, and cleanup, ending at a local sink. Inspect each normalized audio clip and every recorded text stage.</p><div class="meta">{metadata}</div></header>
<main><section class="notice"><b>How to read this report</b>{source_note}
<p><b>Two timing modes:</b> Quality runs are concurrent and unpaced. Latency runs are serial and paced. Compare their timings within each mode.</p>
<details><summary>Scoring, provenance, and scope details</summary><ul>{limits_html}</ul></details></section>
<h2>Quality · concurrent, unpaced</h2><div class="summary-grid">{_metric_html(metrics, "quality")}</div>
<h2>Latency · serial, paced</h2><div class="summary-grid">{_metric_html(metrics, "latency")}</div>
<details><summary>Run and output problems ({len(problems)})</summary><ul>{problem_html}</ul></details>
<div class="toolbar"><input id="search" type="search" placeholder="Search clip name, reference, or any text stage" aria-label="Search clips">
<select id="phase" aria-label="Phase"><option value="all">Both phases</option><option value="quality">Quality</option><option value="latency">Latency</option></select>
<select id="mode" aria-label="Filter"><option value="all">All rows</option><option value="difference">Final text differences</option><option value="failure">Failures or missing</option><option value="fallback">Fallbacks</option></select>
<span id="visible-count"></span></div>
<div id="clips">{cards}</div></main><script>{JS}</script></body></html>'''


def render_report(output_dir: Path) -> Path:
    """Read run.json and replay rows; write summary.json and comparison.html."""
    output_dir = Path(output_dir)
    manifest, problems = _read_run(output_dir)
    observations, metrics = _collect(output_dir, manifest, problems)
    summary = {
        "schemaVersion": 1,
        "status": manifest.get("status"),
        "app": manifest.get("app"),
        "profile": manifest.get("profile"),
        "fixtureCount": sum(isinstance(item, dict) and not _warmup(item) for item in manifest["fixtures"]),
        "sourceCounts": dict(Counter(str(item.get("source") or "unspecified") for item in manifest["fixtures"]
                                     if isinstance(item, dict) and not _warmup(item))),
        "rowCount": len(observations),
        "metrics": metrics,
        "problems": problems,
        "limitations": manifest.get("limitations") or [],
        "scoring": "case-folded Unicode word tokens; punctuation split; no number/date equivalence; missing references unscored",
    }
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    report = output_dir / "comparison.html"
    report.write_text(_render_html(manifest, observations, metrics, problems), encoding="utf-8")
    return report


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_dir", type=Path)
    arguments = parser.parse_args()
    print(render_report(arguments.output_dir))
