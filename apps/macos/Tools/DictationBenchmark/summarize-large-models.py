#!/usr/bin/env python3
"""Compare recognition and reconstructed ASR+LM stages; preserve every output."""
from collections import Counter, defaultdict
import html
import json
import math
from pathlib import Path
import re
import statistics
import sys

def words(text):
    return re.findall(r"[\w]+(?:'[\w]+)?", text.lower())

def distance(a, b):
    previous = list(range(len(b) + 1))
    for i, word in enumerate(a, 1):
        current = [i]
        for j, other in enumerate(b, 1):
            current.append(min(current[-1] + 1, previous[j] + 1, previous[j - 1] + (word != other)))
        previous = current
    return previous[-1]

def distribution(values):
    values = sorted(values)
    if not values:
        return None
    return dict(median=statistics.median(values), p95=values[math.ceil(len(values) * .95) - 1])

def error_rate(rows, field):
    reference = sum(len(words(r["reference"])) for r in rows)
    errors = sum(distance(words(r["reference"]), words(r[field])) for r in rows)
    return dict(errors=errors, referenceWords=reference, percent=100 * errors / reference)

if __name__ == "__main__":
    root = Path(sys.argv[1])
    asr = json.loads((root / "asr-combined.json").read_text())
    cleanup = json.loads((root / "lm-all-transcripts.json").read_text())
    lookup = {(r["input"], r["style"], r["repetition"]): r for r in cleanup if r["kind"] == "audio-lm"}
    grouped = defaultdict(list)
    for row in asr:
        if row["kind"] == "asr":
            grouped[row["label"]].append(row)
    baseline = {(r["name"], r["repetition"]): r for r in grouped["whisper"]}
    summary, details = {}, []
    for label, rows in grouped.items():
        raw_comparison = Counter()
        for r in rows:
            original = baseline[r["name"], r["repetition"]]
            change = distance(words(r["reference"]), words(r["input"])) - distance(words(r["reference"]), words(original["input"]))
            raw_comparison["better" if change < 0 else "worse" if change > 0 else "same"] += 1
        result = dict(runs=len(rows), clips=len({r["name"] for r in rows}),
            asrMs=distribution([r["wallMs"] for r in rows]),
            inferenceMs=distribution([r["inferenceMs"] for r in rows if r.get("inferenceMs") is not None]),
            bridgeAndPostprocessMs=distribution([r["wallMs"] - r["inferenceMs"] for r in rows if r.get("inferenceMs") is not None]),
            modelLoadMs=rows[0].get("modelLoadMs"),
            rawWER=error_rate(rows, "input"), postprocessedWER=error_rate(rows, "final"),
            originalWER=error_rate([r for r in rows if not r["name"].startswith("librispeech-")], "input"),
            librispeechWER=error_rate([r for r in rows if r["name"].startswith("librispeech-")], "input"),
            wordErrorComparisonRuns=raw_comparison, styles={})
        for style in ["standard", "casual", "formal"]:
            outcomes = []
            for r in rows:
                lm = lookup[r["final"], style, r["repetition"]] if r["final"] else None
                outcomes.append(dict(name=r["name"], label=label, repetition=r["repetition"], style=style,
                    reference=r["reference"], raw=r["input"], base=r["final"],
                    final=lm["final"] if lm else "", candidate=lm.get("candidate") if lm else None,
                    accepted=lm["accepted"] if lm else False, fallback=lm.get("fallback") if lm else "asr_dropped",
                    asrMs=r["wallMs"], lmMs=lm["wallMs"] if lm else 0,
                    reconstructedTotalMs=r["wallMs"] + (lm["wallMs"] if lm else 0)))
            result["styles"][style] = dict(lmMs=distribution([r["lmMs"] for r in outcomes]),
                reconstructedTotalMs=distribution([r["reconstructedTotalMs"] for r in outcomes]),
                finalWERDiagnostic=error_rate(outcomes, "final"),
                acceptedRuns=sum(r["accepted"] for r in outcomes),
                fallbackReasons=dict(Counter(r["fallback"] or "none" for r in outcomes)),
                changedWordSequences=sum(words(r["base"]) != words(r["final"]) for r in outcomes))
            details.extend(outcomes)
        summary[label] = result
    smoke = [r for r in cleanup if r["kind"] == "smoke-lm"]
    output = dict(models=summary, outputs=details, lmUniqueTranscripts=len({r["input"] for r in cleanup if r["kind"] == "audio-lm"}),
        lmLoadMs=cleanup[0].get("modelLoadMs"), lmMeasuredCalls=len(cleanup),
        smokeFailures=[dict(name=r["name"], repetition=r["repetition"], failure=r["failure"]) for r in smoke if r.get("failure")])
    (root / "summary.json").write_text(json.dumps(output, indent=2) + "\n")

    # A standalone comparison table: no external scripts, assets, or network calls.
    cells = []
    for r in details:
        if r["repetition"] != 0:
            continue
        columns = [r["name"], r["label"], r["style"], r["reference"], r["raw"], r["base"], r["final"],
            f'{r["asrMs"]:.1f}', f'{r["lmMs"]:.1f}', r["fallback"] or "accepted"]
        cells.append("<tr>" + "".join("<td>" + html.escape(str(v)) + "</td>" for v in columns) + "</tr>")
    page = '''<!doctype html><meta charset="utf-8"><title>ShoutOut ASR and LM outputs</title>
<style>body{font:14px system-ui;margin:24px;color:#17202a}input{padding:10px;width:420px;max-width:90%}
table{border-collapse:collapse;width:100%;margin-top:20px}td,th{border:1px solid #d8dee6;padding:10px;text-align:left;vertical-align:top}
th{position:sticky;top:0;background:#edf2f7}td:nth-child(n+4):nth-child(-n+7){min-width:250px;white-space:pre-wrap}
tr:nth-child(even){background:#f7f9fb}</style><h1>ASR → app postprocessing → LM</h1>
<p>First measured pass shown. Full JSON retains both passes. Times are separate warm stage measurements;
they are not microphone-to-paste latency. Reference WER after cleanup is diagnostic, since cleanup intentionally rewrites text.</p>
<input id="filter" placeholder="Filter by model, clip, style, or text" aria-label="Filter outputs"><span id="count"></span>
<table><thead><tr>''' + "".join(f"<th>{x}</th>" for x in ["Clip", "ASR", "Style", "Reference", "Raw ASR", "After app processing", "After LM", "ASR ms", "LM ms", "LM decision"]) + "</tr></thead><tbody>" + "".join(cells) + '''</tbody></table>
<script>const rows=[...document.querySelectorAll('tbody tr')];const filter=document.querySelector('#filter');
function update(){const q=filter.value.toLowerCase();let n=0;for(const row of rows){row.hidden=!row.textContent.toLowerCase().includes(q);if(!row.hidden)n++;}document.querySelector('#count').textContent=` ${n} rows`;}
filter.addEventListener('input',update);update();</script>'''
    (root / "outputs.html").write_text(page)
    print(json.dumps({k: {f: v[f] for f in ["asrMs", "rawWER", "modelLoadMs", "styles"]} for k, v in summary.items()}, indent=2))
