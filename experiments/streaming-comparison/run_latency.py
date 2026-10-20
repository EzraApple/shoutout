#!/usr/bin/env python3
"""Run warmed ASR paths sequentially, with paced streaming and rotating order."""
import argparse
import json
import subprocess
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cached-macos', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    fixtures = root / '.build/fixtures'
    results = root / '.build/results'
    binary = root / '.build/native-hex/target/release/native-hex-benchmark'
    model = root / '.build/native-hex/model/parakeet-unified-en-0.6b-Q8_0.gguf'
    original = json.loads((fixtures / 'latency-manifest.json').read_text())
    orders = [['current', 'batch', 'stream'], ['stream', 'batch', 'current'], ['batch', 'current', 'stream']]
    for round_index, order in enumerate(orders):
        rows = original if round_index % 2 == 0 else list(reversed(original))
        manifest = fixtures / f'latency-round-{round_index}.json'
        manifest.write_text(json.dumps(rows, indent=2) + '\n')
        native_manifest = fixtures / f'latency-native-round-{round_index}.json'
        native_manifest.write_text(json.dumps([dict(rows[0], name='warmup-not-scored')] + rows, indent=2) + '\n')
        for mode in order:
            print(f'round={round_index} engine={mode} started', flush=True)
            if mode == 'current':
                command = [sys.executable, str(root / 'run_current.py'), '--latency',
                    '--cached-macos', str(args.cached_macos), '--manifest', str(manifest),
                    '--output', str(results / f'current-latency-{round_index}.json')]
                subprocess.run(command, check=True)
            else:
                output = results / f'hex-{mode}-latency-{round_index}.jsonl'
                command = [str(binary), 'run', '--mode', mode, '--packet-ms', '160',
                           '--model', str(model), '--manifest', str(native_manifest), '--output', str(output)]
                with output.with_suffix('.log').open('w') as log:
                    subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
            print(f'round={round_index} engine={mode} completed', flush=True)


if __name__ == '__main__':
    main()
