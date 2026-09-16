#!/usr/bin/env python3
"""Instrument only staged ChatSession calls to inspect native prompt/decode timings."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True
import run as runner

runner.stage_package()
sources = runner.STAGE / "Sources/DictationBenchmark"
shutil.copy2(runner.HERE / "LMProfile.swift", sources / "LMProfile.swift")
service = sources / "LanguagePassService.swift"
text = service.read_text()
text = text.replace(
    'session.respond(to: LanguagePassPrompt.userPrompt(for: baseText, style: style))',
    'LMProfile.respond(session, prompt: LanguagePassPrompt.userPrompt(for: baseText, style: style), input: baseText, stage: "initial")')
text = text.replace('retrySession.respond(to: retryPrompt)',
    'LMProfile.respond(retrySession, prompt: retryPrompt, input: baseText, stage: "retry")')
service.write_text(text)
main = sources / "BenchmarkMain.swift"
text = main.read_text()
needle = '\n    for repetition in 0..<repetitions {\n'
assert text.count(needle) == 1
main.write_text(text.replace(needle, '\n    await LMProfile.shared.reset()\n' + needle))
hash_path = runner.STAGE / "source-hashes.json"
hashes = json.loads(hash_path.read_text())
for path in sources.glob("*.swift"):
    hashes["Staged/" + path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
hash_path.write_text(json.dumps(hashes, indent=2) + "\n")
subprocess.run(["swift", "build", "-c", "release", "--package-path", str(runner.STAGE),
    "--scratch-path", str(runner.MACOS / ".build"), "--product", "DictationBenchmark"], check=True)
output = runner.MACOS / ".build/lm-stage-profile.json"
env = dict(os.environ, BENCH_LM_PROFILE=str(output.with_suffix(".phases.json")))
subprocess.run([sys.executable, str(runner.HERE / "run.py"), "--skip-build", "--output", str(output),
    "--cache-mib", "0", "--repetitions", "3"], env=env, check=True)
