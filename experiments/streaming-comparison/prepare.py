#!/usr/bin/env python3
"""Freeze shared PCM inputs; never record audio or change the installed app."""
import argparse
import array
import hashlib
import json
import math
import random
import struct
import wave
from pathlib import Path


def analyze(samples):
    if not samples:
        return False, False
    rms = math.sqrt(sum(x * x for x in samples) / len(samples))
    peak = max(abs(x) for x in samples)
    ratio = sum(abs(x) >= .001 for x in samples) / len(samples)
    speech = peak >= .003 and rms >= .0006 and ratio >= .002
    sustained = (speech and len(samples) / 16000 >= .25
                 and len(samples) / 16000 * ratio >= .12
                 and rms >= .0012 and ratio >= .015)
    return speech, sustained


def trim(samples):
    # Same 100 ms scan, 700 ms minimum trim, and 200 ms retained tail as the app.
    end = len(samples)
    while end > 0 and not analyze(samples[max(0, end - 1600):end])[0]:
        end = max(0, end - 1600)
    if not end:
        return []
    keep = min(len(samples), end + 3200)
    return samples[:keep] if len(samples) - keep >= 11200 else samples


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    audio_dir = args.output / 'audio'
    audio_dir.mkdir(exist_ok=True)
    rows, controls = [], []
    for section in ['audio', 'conversation-audio']:
        manifest = args.source / section / 'manifest.json'
        for case in json.loads(manifest.read_text()):
            source = manifest.parent / case['path']
            assert hashlib.sha256(source.read_bytes()).hexdigest() == case['sha256'], source
            with wave.open(str(source)) as handle:
                assert (handle.getnchannels(), handle.getsampwidth(), handle.getframerate()) == (1, 2, 16000)
                pcm = array.array('h', handle.readframes(handle.getnframes()))
            samples = [x / 32768 for x in pcm]
            trimmed = trim(samples)
            gate = analyze(trimmed)[1]
            if not gate:
                assert not case['reference'], case['name']
                controls.append(dict(name=case['name'], samples=len(samples), gate='rejected'))
                continue
            destination = audio_dir / (case['name'] + '.wav')
            with wave.open(str(destination), 'wb') as handle:
                handle.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
                handle.writeframes(pcm[:len(trimmed)].tobytes())
            rows.append(dict(case, path=str(destination.resolve()),
                             duration=len(trimmed) / 16000,
                             original_duration=len(samples) / 16000,
                             source_path=str(source), original_sha256=case['sha256'],
                             sha256=hashlib.sha256(destination.read_bytes()).hexdigest()))
    quiet_sources = [next(r for r in rows if r['name'] == 'dictation-samantha-request'),
                     min((r for r in rows if r['category'] == 'conversation'), key=lambda r: r['duration'])]
    for case in quiet_sources:
        with wave.open(case['path']) as handle:
            pcm = array.array('h', handle.readframes(handle.getnframes()))
        quiet = array.array('h', [round(x * .1) for x in pcm])
        assert analyze([x / 32768 for x in quiet])[1], case['name']
        destination = audio_dir / ('quiet-' + case['name'] + '.wav')
        with wave.open(str(destination), 'wb') as handle:
            handle.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
            handle.writeframes(quiet.tobytes())
        rows.append(dict(case, name='quiet-' + case['name'], category='quiet',
                         path=str(destination.resolve()), amplitude_gain=.1,
                         source='20 dB attenuation of ' + case['name'],
                         sha256=hashlib.sha256(destination.read_bytes()).hexdigest()))
    random.Random(20261018).shuffle(rows)
    (args.output / 'quality-manifest.json').write_text(json.dumps(rows, indent=2) + '\n')
    names = ['dictation-samantha-request', 'dictation-daniel-tiny-stop',
             'dictation-samantha-correction', 'dictation-daniel-self-correction',
             'dictation-samantha-identifier', 'dictation-daniel-negation',
             'noise-negation-10', 'noise-tail-10', 'dictation-long-2',
             'long-natural-61-60']
    # Add four real conversational clips at the quartiles of recording duration.
    conversation = sorted((r for r in rows if r['category'] == 'conversation'),
                          key=lambda r: (r['duration'], r['name']))
    names += [conversation[i]['name'] for i in [0, 12, 25, 49]]
    latency = [next(r for r in rows if r['name'] == name) for name in names]
    (args.output / 'latency-manifest.json').write_text(json.dumps(latency, indent=2) + '\n')
    provenance = dict(seed=20261018, quality_count=len(rows), gate_controls=controls,
                      latency_count=len(latency), latency_audio_seconds=sum(r['duration'] for r in latency),
                      source=str(args.source), trim='ShoutOut 0800a3e AudioSignalAnalysis defaults')
    (args.output / 'fixtures.json').write_text(json.dumps(provenance, indent=2) + '\n')
    print(json.dumps(provenance, indent=2))


if __name__ == '__main__':
    main()
