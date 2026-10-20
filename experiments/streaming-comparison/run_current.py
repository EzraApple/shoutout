#!/usr/bin/env python3
"""Run the source-verified production Parakeet benchmark without cleanup."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cached-macos', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--repetitions', type=int, default=1)
    parser.add_argument('--latency', action='store_true', help='One common speech warmup, then first pass for each timed clip')
    args = parser.parse_args()
    current = Path(__file__).resolve().parents[2] / 'apps/macos'
    stage = args.cached_macos / '.build/dictation-benchmark-package'
    hashes = json.loads((stage / 'source-hashes.json').read_text())
    paths = {p.stem: p for p in (current / 'Sources/Services').glob('*.swift') if p.stem in hashes}
    paths.update({'Core/' + p.name: p for p in (current / 'Sources/Core').glob('*.swift')})
    paths['Package.resolved'] = current / 'Package.resolved'
    for key, path in paths.items():
        assert hashes[key] == hashlib.sha256(path.read_bytes()).hexdigest(), f'Production source changed: {key}'
    for key, digest in hashes.items():
        if key.startswith('Staged/'):
            path = stage / 'Sources/DictationBenchmark' / key.removeprefix('Staged/')
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, path
    binary = args.cached_macos / '.build/release/DictationBenchmark'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    tokenizers = Path(__file__).resolve().parent / '.build/tokenizers'
    if not tokenizers.exists():
        shutil.copytree(args.cached_macos / '.build/benchmark-tokenizers', tokenizers)
    # Foundation appendingPathComponent treats these fixture paths as components.
    # Stage relative paths for the existing harness, while native Hex uses absolutes.
    staged_manifest = args.output.with_suffix('.manifest.json')
    fixtures = json.loads(args.manifest.read_text())
    for fixture in fixtures:
        path = Path(fixture['path'])
        if not path.is_absolute():
            path = args.manifest.resolve().parent / path
        fixture['path'] = os.path.relpath(path, staged_manifest.resolve().parent)
    if args.latency:
        warmup = dict(fixtures[0], name='warmup-not-scored')
        fixtures.insert(0, warmup)
    staged_manifest.write_text(json.dumps(fixtures, indent=2) + '\n')
    env = dict(os.environ, BENCH_OUTPUT=str(args.output.resolve()),
               BENCH_REPETITIONS=str(args.repetitions), BENCH_CACHE_MIB='0',
               BENCH_AUDIO_ONLY='1', BENCH_ASR='production-parakeet',
               BENCH_COMPUTE_PROFILES='default', BENCH_MEASURE_FIRST_PASS='1' if args.latency else '0',
               BENCH_PIPELINE_STYLE='', BENCH_MODEL_ID='large-v3-v20240930_turbo_632MB',
               BENCH_MODEL_ROOT='/Users/ezraapple/Library/Application Support/com.ezraapple.shoutout/Models',
               BENCH_AUDIO_MANIFEST=str(staged_manifest.resolve()),
               BENCH_TOKENIZERS=str(tokenizers))
    metadata = dict(binary=str(binary), binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                    production_source_hashes={k: hashes[k] for k in paths},
                    manifest_sha256=hashlib.sha256(args.manifest.read_bytes()).hexdigest(),
                    repetitions=args.repetitions, cleanup=False,
                    latency=args.latency,
                    note='Existing release executable; staged sources and production source hashes verified before run.')
    args.output.with_suffix('.provenance.json').write_text(json.dumps(metadata, indent=2) + '\n')
    with args.output.with_suffix('.log').open('w') as log:
        subprocess.run([str(binary)], env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    rows = json.loads(args.output.read_text())
    rows = [r for r in rows if r['name'] != 'warmup-not-scored']
    args.output.write_text(json.dumps(rows, indent=2) + '\n')
    print(json.dumps(dict(output=str(args.output), row_count=len(rows),
                          kinds=sorted(set(r['kind'] for r in rows)))))


if __name__ == '__main__':
    main()
