#!/usr/bin/env python3
"""Replay the frozen larger corpus through the packaged app and unchanged cleanup."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
APP = ROOT / 'apps/macos/dist/ShoutOut.app/Contents/MacOS/ShoutOut'
RESULTS = HERE / 'results/broader'
CORPUS = HERE.parent / '.build/fixtures/quality-manifest.json'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    RESULTS.mkdir(parents=True, exist_ok=True)
    rows = json.loads(CORPUS.read_text())
    for row in rows:
        path = Path(row['path'])
        assert sha256(path) == row['sha256'], path
    assert len(rows) == 231 and len({row['name'] for row in rows}) == 231
    silence = HERE / 'fixtures/control-silence.wav'
    manifest = RESULTS / 'manifest.json'
    manifest.write_text(json.dumps([dict(rows[0], name='warmup-not-scored')] + rows + [dict(
        name='control-silence', path=str(silence), reference='', category='silence', sha256=sha256(silence))], indent=2) + '\n')
    (RESULTS / 'build.json').write_text(json.dumps(dict(app=str(APP), appSHA256=sha256(APP),
        corpusManifestSHA256=sha256(CORPUS), replayManifestSHA256=sha256(manifest),
        speechClips=231, dictionary='No custom aliases, controlled equally for both engines.',
        cleanup='Unchanged production Llama-3.2-1B-Instruct-4bit, standard style.',
        pacing='Unpaced quality evaluation; timings must not be interpreted as release latency.'), indent=2) + '\n')
    for engine in ['parakeet', 'hexStreaming']:
        suite = 'ShoutOut.Broader.' + uuid.uuid4().hex
        environment = dict(os.environ, SHOUTOUT_CLI_SUITE=suite)
        environment.pop('SHOUTOUT_CONTROL_SOCKET', None)
        try:
            for key, value in [('streaming', 'on' if engine == 'hexStreaming' else 'off'),
                               ('cleanup', 'on'), ('style', 'normal')]:
                subprocess.run([str(APP), '--cli', 'settings', 'set', key, value],
                    env=environment, check=True, capture_output=True, timeout=30)
            output = RESULTS / f'{engine}.json'
            print(engine, 'started', flush=True)
            with (RESULTS / f'{engine}.log').open('w') as log:
                subprocess.run([str(APP), '--cli', 'replay', str(manifest), '--output', str(output)],
                    env=environment, stdout=log, stderr=log, check=True, timeout=1200)
            result = json.loads(output.read_text())
            assert len(result) == 233 and all(not row['paced'] for row in result)
            assert sum(row['status'] == 'silent' for row in result) == 1
            print(engine, 'completed', flush=True)
        finally:
            subprocess.run(['/usr/bin/defaults', 'delete', suite], capture_output=True)


if __name__ == '__main__':
    main()
