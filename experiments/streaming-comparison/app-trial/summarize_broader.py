#!/usr/bin/env python3
"""Separate raw recognition, mechanical processing, and unchanged cleanup."""
import collections
import importlib.util
import json
from pathlib import Path
import subprocess

from summarize import distance, EnglishTextNormalizer

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
RESULTS = HERE / 'results/broader'
NORMALIZE = EnglishTextNormalizer()


def normalized_errors(reference, hypothesis):
    return distance(NORMALIZE(reference).split(), NORMALIZE(hypothesis).split())


def main():
    manifest = json.loads((RESULTS / 'manifest.json').read_text())
    cases = {row['name']: row for row in manifest if row['name'] not in ['warmup-not-scored', 'control-silence']}
    engines = ['parakeet', 'hexStreaming']
    outputs = {}
    for engine in engines:
        rows = json.loads((RESULTS / f'{engine}.json').read_text())
        assert len(rows) == 233 and all(not row['paced'] for row in rows)
        outputs[engine] = {row['name']: row for row in rows if row['name'] in cases}
        assert set(outputs[engine]) == set(cases)
    captures = [dict(engine=engine, name=name, text=row['rawText'])
        for engine, rows in outputs.items() for name, row in rows.items()]
    result = subprocess.run([str(RESULTS / 'pipeline-probe')], input=json.dumps(captures),
        text=True, capture_output=True, check=True, timeout=30)
    probe = json.loads(result.stdout)
    (RESULTS / 'pipeline-probe.json').write_text(result.stdout)
    mechanical = {(row['engine'], row['name']): row['baseText'] for row in probe['mechanical']}
    audit_path = ROOT / 'apps/macos/Tools/DictationBenchmark/audit-expanded-facts.py'
    spec = importlib.util.spec_from_file_location('fact_audit', audit_path)
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)

    def fact_flags(name, text):
        # The original authored rules use name suffixes. Noise has an SNR suffix.
        if name.startswith('noise-'):
            for kind in ['negation', 'localhost', 'tail']:
                if '-' + kind + '-' in name:
                    name = 'noise-' + kind
                    break
        return audit.missing(name, text)

    grouped = {engine: collections.defaultdict(list) for engine in engines}
    observations = []
    for name, case in cases.items():
        observation = dict(name=name, category=case['category'], reference=case['reference'], variants={})
        for engine in engines:
            row = outputs[engine][name]
            texts = dict(raw=row['rawText'], mechanical=mechanical[engine, name], final=row['finalText'])
            variant = dict(texts=texts, status=row['status'],
                errors={stage: normalized_errors(case['reference'], text) for stage, text in texts.items()},
                phraseFlags={stage: fact_flags(name, text) for stage, text in texts.items()},
                referenceWords=len(NORMALIZE(case['reference']).split()),
                cleanupAccepted=row.get('cleanupAccepted'),
                cleanupChanged=texts['mechanical'] != texts['final'])
            observation['variants'][engine] = variant
            grouped[engine]['all'].append(variant)
            grouped[engine][case['category']].append(variant)
        observation['rawErrorDelta'] = observation['variants']['hexStreaming']['errors']['raw'] - observation['variants']['parakeet']['errors']['raw']
        observation['finalErrorDelta'] = observation['variants']['hexStreaming']['errors']['final'] - observation['variants']['parakeet']['errors']['final']
        observations.append(observation)
    summary = dict(groups={}, observations=observations,
        dictionary=probe['dictionaryDemonstration'], dictionaryScope=probe['dictionaryScope'],
        limitations=['Standard lexical WER; final WER also counts legitimate cleanup rewrites and spoken-command expansion.',
            'Authored phrase-preservation checks are narrow diagnostics and require manual semantic review.',
            'No custom dictionary aliases were applied in the scored replay.',
            'Natural/conversation corpora are public data; generated controls use intended TTS references.',
            'Unpaced quality replay; latency is excluded, and there is no microphone or text insertion.'])
    for engine, categories in grouped.items():
        summary['groups'][engine] = {}
        for category, rows in categories.items():
            words = sum(row['referenceWords'] for row in rows)
            summary['groups'][engine][category] = dict(clips=len(rows), words=words,
                stages={stage: dict(errors=sum(row['errors'][stage] for row in rows),
                    wer=sum(row['errors'][stage] for row in rows)/words,
                    phraseFlaggedClips=sum(bool(row['phraseFlags'][stage]) for row in rows))
                    for stage in ['raw', 'mechanical', 'final']},
                cleanupAccepted=sum(row['cleanupAccepted'] is True for row in rows),
                cleanupChanged=sum(row['cleanupChanged'] for row in rows))
    summary['rawPairs'] = dict(collections.Counter('better' if row['rawErrorDelta'] < 0 else 'worse' if row['rawErrorDelta'] > 0 else 'same' for row in observations))
    summary['finalPairs'] = dict(collections.Counter('better' if row['finalErrorDelta'] < 0 else 'worse' if row['finalErrorDelta'] > 0 else 'same' for row in observations))
    (RESULTS / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps({key: value for key, value in summary.items() if key != 'observations'}, indent=2))


if __name__ == '__main__':
    main()
