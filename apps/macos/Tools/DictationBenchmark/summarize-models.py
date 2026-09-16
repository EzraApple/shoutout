#!/usr/bin/env python3
"""Summarize serial model sweeps, retaining distinct outputs for quality review."""
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import re
import statistics
import sys

def distribution(values):
    values = sorted(values)
    return dict(median=round(statistics.median(values), 2),
                p95=round(values[math.ceil(len(values) * .95) - 1], 2))

def words(text):
    return re.findall(r"[\w]+(?:'[\w]+)?", text.lower())

def distance(reference, hypothesis):
    previous = list(range(len(hypothesis) + 1))
    for i, word in enumerate(reference, 1):
        current = [i]
        for j, other in enumerate(hypothesis, 1):
            current.append(min(current[-1] + 1, previous[j] + 1,
                               previous[j - 1] + (word != other)))
        previous = current
    return previous[-1]

root = Path(sys.argv[1])
summary = {}
for kind in ["lm", "asr"]:
    path = root / f"{kind}-combined.json"
    if not path.exists():
        continue
    rows = json.loads(path.read_text())
    if kind == "asr":
        for followup in sorted(root.glob("asr-*-combined.json")):
            rows += json.loads(followup.read_text())
    rows = [r for r in rows if r["kind"] != "audio-gate"]
    groups = defaultdict(list)
    for row in rows:
        groups[row["label"]].append(row)
    baseline_label = "llama" if kind == "lm" else "whisper"
    baseline = {(r["name"], r["style"], r["round"], r["repetition"]): r
                for r in groups[baseline_label]}
    summary[kind] = {}
    for label, group in groups.items():
        speeds, changes, regressions = [], [], []
        for r in group:
            key = (r["name"], r["style"], r["round"], r["repetition"])
            original = baseline.get(key)
            if original:
                assert original["input"] == r["input"] if kind == "lm" else original["reference"] == r["reference"]
                speeds.append(100 * (1 - r["wallMs"] / original["wallMs"]))
                if r["final"] != original["final"]:
                    changes.append(key)
                if r.get("failure") and not original.get("failure"):
                    regressions.append(key)
        cases = []
        for name, style in sorted({(r["name"], r["style"]) for r in group}):
            selected = [r for r in group if (r["name"], r["style"]) == (name, style)]
            outcomes = Counter(json.dumps({k: r.get(k) for k in
                ["input", "candidate", "final", "accepted", "fallback", "failure", "reference"]}, sort_keys=True)
                for r in selected)
            cases.append(dict(name=name, style=style, wallMs=distribution([r["wallMs"] for r in selected]),
                outcomes=[dict(count=count, **json.loads(outcome)) for outcome, count in outcomes.items()]))
        result = dict(runs=len(group), cases=len(cases), wallMs=distribution([r["wallMs"] for r in group]),
            pairedComparisons=len(speeds), medianPairedSpeedupPercent=round(statistics.median(speeds), 2) if speeds else None,
            changedFinalRuns=len(changes), newSmokeFailureRuns=len(regressions),
            smokeFailures=dict(Counter(r["name"] + " / " + r["style"] + ": " + r["failure"]
                for r in group if r.get("failure"))),
            fallbacks=dict(Counter(r.get("fallback", "none") for r in group)),
            maxPeakMiB=round(max(r["peakBytes"] for r in group) / 2**20, 2), caseResults=cases)
        if kind == "asr":
            result["wer"] = {}
            for subset, selected in [("all", group), ("original", [r for r in group if not r["name"].startswith("librispeech-")]),
                ("librispeech", [r for r in group if r["name"].startswith("librispeech-")])]:
                count = sum(len(words(r["reference"])) for r in selected)
                result["wer"][subset] = dict(referenceWords=count,
                    rawErrors=sum(distance(words(r["reference"]), words(r["input"])) for r in selected),
                    finalErrors=sum(distance(words(r["reference"]), words(r["final"])) for r in selected))
        summary[kind][label] = result
    if kind == "asr":
        original_cases = {c["name"]: c for c in summary[kind][baseline_label]["caseResults"]}
        def mean_errors(case):
            return sum(distance(words(o["reference"]), words(o["input"])) * o["count"]
                       for o in case["outcomes"]) / sum(o["count"] for o in case["outcomes"])
        for result in summary[kind].values():
            comparison = {"fewerErrors": [], "sameErrors": [], "moreErrors": []}
            for case in result["caseResults"]:
                change = mean_errors(case) - mean_errors(original_cases[case["name"]])
                comparison["fewerErrors" if change < 0 else "moreErrors" if change > 0 else "sameErrors"].append(case["name"])
            result["caseWordErrorComparisons"] = comparison
print(json.dumps(summary, indent=2))
