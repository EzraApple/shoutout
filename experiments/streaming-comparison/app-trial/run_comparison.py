#!/usr/bin/env python3
"""Run the bundled app's local replay mode without microphone or text insertion."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
RESULTS = HERE / 'results'
BINARY = ROOT / 'apps/macos/dist/ShoutOut.app/Contents/MacOS/ShoutOut'


def run(engine, manifest, output, paced):
    environment = dict(os.environ,
        SHOUTOUT_REPLAY_MANIFEST=str(manifest),
        SHOUTOUT_REPLAY_OUTPUT=str(output),
        SHOUTOUT_REPLAY_ENGINE=engine,
        SHOUTOUT_REPLAY_PACING='1' if paced else '0')
    print(output.name, 'started', flush=True)
    with output.with_suffix('.log').open('w') as log:
        subprocess.run([str(BINARY)], env=environment, stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=600)
    print(output.name, 'completed', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-quality', action='store_true')
    args = parser.parse_args()
    RESULTS.mkdir(exist_ok=True)
    rows = json.loads((HERE / 'fixtures/manifest.json').read_text())['fixtures']
    for row in rows:
        path = HERE / 'fixtures' / row['path']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == row['sha256'], path
        row['path'] = str(path)
    full_manifest = RESULTS / 'quality-manifest.json'
    full_manifest.write_text(json.dumps([dict(rows[0], name='warmup-not-scored')] + rows, indent=2))
    (RESULTS / 'build.json').write_text(json.dumps(dict(
        executable=str(BINARY), sha256=hashlib.sha256(BINARY.read_bytes()).hexdigest(),
        scope='Production services and capture collector replay; simulated 80ms hold tail; local output sink.',
        exclusions='Physical microphone/converter, keyboard events, accessibility insertion, and battery.'
    ), indent=2) + '\n')
    for engine in ['parakeet', 'hexStreaming']:
        if args.skip_quality:
            assert (RESULTS / f'{engine}-quality.json').exists(), engine
        else:
            run(engine, full_manifest, RESULTS / f'{engine}-quality.json', False)
    latency_names = {'01-save-file', '02-negation', '03-self-correction', '09-version-port',
                     '15-thank-you-tail', '17-paragraph-planning', 'quiet-01-save-file', 'control-silence'}
    rows = [row for row in rows if row['name'] in latency_names]
    for round_index in range(3):
        ordered = rows if round_index % 2 == 0 else list(reversed(rows))
        manifest = RESULTS / f'latency-{round_index}.json'
        manifest.write_text(json.dumps([dict(ordered[0], name='warmup-not-scored')] + ordered, indent=2))
        engines = ['parakeet', 'hexStreaming'] if round_index % 2 == 0 else ['hexStreaming', 'parakeet']
        for engine in engines:
            run(engine, manifest, RESULTS / f'{engine}-latency-{round_index}.json', True)


if __name__ == '__main__':
    main()
