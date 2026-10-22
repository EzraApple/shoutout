"""Summarize completed hardware runs; exclude round zero from steady-state comparisons."""
import collections
import json
import math
import pathlib
import statistics
import sys


def distribution(values):
    values = sorted(values)
    return {
        "n": len(values),
        "median": statistics.median(values),
        "p90": values[math.ceil(len(values) * 0.9) - 1],
        "minimum": values[0],
        "maximum": values[-1],
    }


path = pathlib.Path(sys.argv[1])
records = [json.loads(line) for line in path.read_text().splitlines()]
metadata = next(row for row in records if row["type"] == "metadata")
takes = [row for row in records if row["type"] == "take"]
errors = [row for row in records if row["type"] == "error"]
assert not errors, errors
assert records[-1] == {"type": "complete", "finalDeviceRunning": 0}, records[-1]
assert len(takes) == metadata["rounds"] * len({row["variant"] for row in takes})
failures = []
for row in takes:
    issues = {
        key: row.get(key)
        for key in ["idleDeviceRunningBefore", "idleDeviceRunningAfter",
                    "idleCallbacksBefore", "callbacksAfterStop", "conversionErrors"]
        if row.get(key) != 0
    }
    if row["callbacks"] < 3 or row["convertedFrames"] == 0:
        issues["audioDelivery"] = False
    if row["deviceRunningDuring"] != 1:
        issues["deviceRunningDuring"] = row["deviceRunningDuring"]
    for key in ["defaultDeviceBefore", "defaultDeviceAfter"]:
        if key in row and row[key] != metadata["deviceID"]:
            issues[key] = row[key]
    if issues:
        failures.append({"variant": row["variant"], "round": row["round"], "issues": issues})
assert not failures, failures

groups = collections.defaultdict(list)
for row in takes:
    if row["round"] > 0:
        groups[row["variant"]].append(row)

summary = {"metadata": metadata, "totalTakes": len(takes), "idleOrDeliveryFailures": failures,
           "excludedRounds": [0], "variants": {}, "pairedSavingsMs": {}}
for variant, rows in groups.items():
    phases = set().union(*(row["phases"] for row in rows))
    summary["variants"][variant] = {
        "phasesMs": {phase: distribution([row["phases"][phase] for row in rows if phase in row["phases"]])
                     for phase in sorted(phases)},
        "firstRawBufferMs": distribution([row["requestToFirstRawBufferMs"] for row in rows]),
        "firstConvertedBufferMs": distribution([row["requestToFirstConvertedBufferMs"] for row in rows]),
        "firstSampleTimestampMs": distribution([row["requestToFirstSampleTimestampMs"] for row in rows]),
        "actualFirstBufferFrames": sorted({row["firstBufferFrames"] for row in rows}),
        "targetCapturedCount": sum(row["targetCaptured"] for row in rows),
    }

reference = {row["round"]: row for row in groups.get("productionReference", [])}
for variant, rows in groups.items():
    if variant == "productionReference" or not reference:
        continue
    summary["pairedSavingsMs"][variant] = {
        "engineReady": distribution([
            reference[row["round"]]["phases"]["requestToEngineReadyMs"]
            - row["phases"]["requestToEngineReadyMs"] for row in rows]),
        "firstRawBuffer": distribution([
            reference[row["round"]]["requestToFirstRawBufferMs"]
            - row["requestToFirstRawBufferMs"] for row in rows]),
    }

output = path.with_name("summary.json")
output.write_text(json.dumps(summary, indent=2) + "\n")
for variant, row in summary["variants"].items():
    ready = row["phasesMs"]["requestToEngineReadyMs"]
    buffer = row["firstRawBufferMs"]
    print(f"{variant}: n={ready['n']} ready median={ready['median']:.1f} p90={ready['p90']:.1f} "
          f"first-buffer median={buffer['median']:.1f} p90={buffer['p90']:.1f}")
print(f"{len(takes)} takes; no observed idle, route, or delivery failures. Summary: {output}")
