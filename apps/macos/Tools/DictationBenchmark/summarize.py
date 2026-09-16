#!/usr/bin/env python3
"""Summarize latency and compare every candidate/final/fallback against zero-cache runs."""
from collections import Counter
import json
import math
from pathlib import Path
import re
import statistics
import sys


def percentiles(values):
    values = sorted(values)
    return {"median": round(statistics.median(values), 2),
            "p95": round(values[math.ceil(len(values) * .95) - 1], 2)}


def words(text):
    return re.findall(r"[\w]+(?:'[\w]+)?", text.lower())


def edit_distance(reference, hypothesis):
    previous = list(range(len(hypothesis) + 1))
    for index, word in enumerate(reference, 1):
        current = [index]
        for column, other in enumerate(hypothesis, 1):
            current.append(min(current[-1] + 1, previous[column] + 1,
                               previous[column - 1] + (word != other)))
        previous = current
    return previous[-1]


rows = json.loads(Path(sys.argv[1]).read_text())
lm = [row for row in rows if row["kind"].endswith("-lm")]
key = lambda row: (row["kind"], row["name"], row["style"], row["repetition"])
baseline = {key(row): row for row in lm if row["cacheMiB"] == 0 and not row.get("promptCache", False)}
summary = {"policies": {}, "audio": {}, "computeProfiles": {}}
for limit, prefix in sorted({(row["cacheMiB"], row.get("promptCache", False)) for row in lm}):
    group = [row for row in lm if row["cacheMiB"] == limit and row.get("promptCache", False) == prefix]
    changes = []
    speedups = []
    for row in group:
        original = baseline.get(key(row))
        if original is None:
            continue
        fields = [field for field in ["candidate", "final", "accepted", "fallback", "failure"]
                  if row.get(field) != original.get(field)]
        if fields:
            changes.append({"name": row["name"], "style": row["style"],
                            "repetition": row["repetition"], "fields": fields})
        speedups.append(100 * (1 - row["wallMs"] / original["wallMs"]))
    summary["policies"][f"{limit}-prefix" if prefix else str(limit)] = {
        "runs": len(group), "wallMs": percentiles([row["wallMs"] for row in group]),
        "medianPairedSpeedupPercent": round(statistics.median(speedups), 2) if speedups else None,
        "maxPeakMiB": round(max(row["peakBytes"] for row in group) / 2**20, 2),
        "maxIdleCacheBytes": max(row["cachedBytes"] for row in group),
        "failures": dict(Counter(row["name"] + ": " + row["failure"] for row in group if row.get("failure"))),
        "fallbacks": dict(Counter(row.get("fallback", "none") for row in group)),
        "differencesFromBaseline": changes,
    }
asr = [row for row in rows if row["kind"] == "asr"]
def compute_profile(row):
    return row.get("compute", {"ane": "default", "gpu": "encoder-gpu"}.get(row.get("encoder"), "default"))

asr_baseline = {(row["name"], row["repetition"]): row for row in asr if compute_profile(row) == "default"}
for profile in sorted({compute_profile(row) for row in asr}):
    group = [row for row in asr if compute_profile(row) == profile]
    changes = []
    speedups = []
    for row in group:
        original = asr_baseline.get((row["name"], row["repetition"]))
        if original:
            fields = [field for field in ["input", "final", "accepted"] if row.get(field) != original.get(field)]
            if fields: changes.append({"name": row["name"], "repetition": row["repetition"], "fields": fields})
            speedups.append(100 * (1 - row["wallMs"] / original["wallMs"]))
    reference_words = sum(len(words(row["reference"])) for row in group)
    errors = sum(edit_distance(words(row["reference"]), words(row["input"])) for row in group)
    summary["computeProfiles"][profile] = {
        "runs": len(group), "wallMs": percentiles([row["wallMs"] for row in group]),
        "medianPairedSpeedupPercent": round(statistics.median(speedups), 2) if speedups else None,
        "rawWordErrorRate": round(errors / max(1, reference_words), 4),
        "differencesFromBaseline": changes,
    }
for name, profile in sorted({(row["name"], compute_profile(row)) for row in asr}):
    group = [row for row in asr if row["name"] == name and compute_profile(row) == profile]
    reference = words(group[0]["reference"])
    summary["audio"][name + " / " + profile] = {
        "runs": len(group), "wallMs": percentiles([row["wallMs"] for row in group]),
        "distinctRawTranscripts": len({row["input"] for row in group}),
        "distinctFinalTranscripts": len({row["final"] for row in group}),
        "rawWordErrorRate": round(edit_distance(reference, words(group[0]["input"])) / max(1, len(reference)), 4),
        "raw": group[0]["input"], "final": group[0]["final"],
    }
summary["audioGateResults"] = [row for row in rows if row["kind"] == "audio-gate"]
print(json.dumps(summary, indent=2))
