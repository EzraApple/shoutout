#!/usr/bin/env python3
"""Compare recognition text and release latency; cleanup is excluded."""
import argparse
import collections
import html
import importlib.util
import json
import math
import re
import statistics
import sys
from pathlib import Path

sys.dont_write_bytecode = True


def words(text):
    return re.findall(r"[\w]+(?:'[\w]+)?", text.lower().replace('’', "'"))


def distance(reference, hypothesis):
    previous = list(range(len(hypothesis) + 1))
    for index, word in enumerate(reference, 1):
        current = [index]
        for column, other in enumerate(hypothesis, 1):
            current.append(min(current[-1] + 1, previous[column] + 1,
                               previous[column - 1] + (word != other)))
        previous = current
    return previous[-1]


def percentiles(values):
    ordered = sorted(values)
    return dict(count=len(values), median=round(statistics.median(ordered), 2),
                p95=round(ordered[math.ceil(.95 * len(ordered)) - 1], 2))


def native(path):
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    return {r['name']: r for r in rows if r['name'] != 'warmup-not-scored'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(Path(__file__).resolve().parent / '.build/scoring'))
    from whisper_normalizer import EnglishTextNormalizer
    normalize = EnglishTextNormalizer()
    fixtures = json.loads((args.fixtures / 'quality-manifest.json').read_text())
    cases = {r['name']: r for r in fixtures}
    current_rows = json.loads((args.results / 'current-quality.json').read_text())
    current = {r['name']: dict(r, text=r['input']) for r in current_rows if r['kind'] == 'asr'}
    batch = native(args.results / 'hex-batch-quality.jsonl')
    stream = native(args.results / 'hex-stream-quality.jsonl')
    variants = dict(current=current, hex_batch=batch, hex_stream=stream)
    assert all(set(rows) == set(cases) for rows in variants.values()), 'Incomplete quality corpus'
    audit_path = Path(__file__).resolve().parents[2] / 'apps/macos/Tools/DictationBenchmark/audit-expanded-facts.py'
    spec = importlib.util.spec_from_file_location('fact_audit', audit_path)
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    quality, comparisons = {}, []
    for label, rows in variants.items():
        groups = collections.defaultdict(list)
        for name, row in rows.items():
            reference = words(cases[name]['reference'])
            errors = distance(reference, words(row['text']))
            row['errors'] = errors
            row['reference_words'] = len(reference)
            normalized_reference = normalize(cases[name]['reference']).split()
            row['normalized_errors'] = distance(normalized_reference, normalize(row['text']).split())
            row['normalized_reference_words'] = len(normalized_reference)
            row['missing_facts'] = audit.missing(name, row['text'])
            groups['all'].append(row)
            groups[cases[name]['category']].append(row)
        quality[label] = {}
        for category, group in groups.items():
            error_count = sum(r['errors'] for r in group)
            word_count = sum(r['reference_words'] for r in group)
            quality[label][category] = dict(clips=len(group), errors=error_count,
                reference_words=word_count, word_error_rate=round(error_count / word_count, 5),
                normalized_errors=sum(r['normalized_errors'] for r in group),
                normalized_reference_words=sum(r['normalized_reference_words'] for r in group),
                normalized_word_error_rate=round(sum(r['normalized_errors'] for r in group)
                    / sum(r['normalized_reference_words'] for r in group), 5),
                fact_failures=sum(bool(r['missing_facts']) for r in group),
                fallbacks=sum(r.get('source') == 'fallback' for r in group))
    for name, case in cases.items():
        comparisons.append(dict(name=name, category=case['category'], duration=case['duration'],
            reference=case['reference'], variants={label: rows[name] for label, rows in variants.items()},
            stream_error_delta=stream[name]['errors'] - current[name]['errors'],
            normalized_stream_error_delta=stream[name]['normalized_errors'] - current[name]['normalized_errors'],
            normalized_stream_batch_error_delta=stream[name]['normalized_errors'] - batch[name]['normalized_errors'],
            stream_batch_error_delta=stream[name]['errors'] - batch[name]['errors']))
    latency = {}
    latency_cases = {r['name']: r for r in json.loads((args.fixtures / 'latency-manifest.json').read_text())}
    for label, pattern, field in [('current', 'current-latency-*.json', 'wallMs'),
                                   ('hex_batch', 'hex-batch-latency-*.jsonl', 'batch_ms'),
                                   ('hex_stream', 'hex-stream-latency-*.jsonl', 'release_to_text_ms')]:
        observations = []
        for path in sorted(args.results.glob(pattern)):
            if label == 'current' and not re.fullmatch(r'current-latency-\d+\.json', path.name):
                continue
            rows = (json.loads(path.read_text()) if path.suffix == '.json'
                    else list(native(path).values()))
            assert collections.Counter(r['name'] for r in rows) == collections.Counter(latency_cases.keys()), path
            round_index = int(re.search(r'-(\d+)\.', path.name)[1])
            observations += [dict(r, round=round_index) for r in rows]
        if observations:
            assert collections.Counter(r['name'] for r in observations) == collections.Counter(
                {name: 3 for name in latency_cases}), f'{label}: expected three complete rounds'
            assert all(r.get(field) is not None for r in observations), label
            if label != 'current':
                assert all(r['samples'] == round(latency_cases[r['name']]['duration'] * 16000)
                           for r in observations), label
            if label == 'hex_stream':
                assert all(r['source'] == 'stream' and r['fed_samples'] == r['samples'] for r in observations), label
            latency[label] = dict(all=percentiles([r[field] for r in observations]),
                short=percentiles([r[field] for r in observations if cases[r['name']]['duration'] < 15]),
                long=percentiles([r[field] for r in observations if cases[r['name']]['duration'] >= 15]),
                rounds={str(index): percentiles([r[field] for r in observations if r['round'] == index])
                        for index in range(3)},
                transcript_changes=[dict(name=r['name'], round=r['round'],
                    timed_text=r['input'] if label == 'current' else r['text'],
                    quality_text=variants[label][r['name']]['text']) for r in observations
                    if (r['input'] if label == 'current' else r['text']) != variants[label][r['name']]['text']],
                by_clip={name: percentiles([r[field] for r in observations if r['name'] == name])
                         for name in latency_cases},
                observations=observations)
    paired_latency = [dict(name=name, duration=case['duration'],
        medians={label: values['by_clip'][name]['median'] for label, values in latency.items()},
        stream_saving_ms=round(latency['current']['by_clip'][name]['median']
                             - latency['hex_stream']['by_clip'][name]['median'], 2))
        for name, case in latency_cases.items()] if len(latency) == 3 else []
    summary = dict(quality=quality, latency=latency,
        machine=json.loads((args.results / 'machine.json').read_text()),
        paired_latency=paired_latency,
        stream_vs_current=dict(better=sum(r['stream_error_delta'] < 0 for r in comparisons),
            same=sum(r['stream_error_delta'] == 0 for r in comparisons),
            worse=sum(r['stream_error_delta'] > 0 for r in comparisons)),
        stream_vs_hex_batch=dict(better=sum(r['stream_batch_error_delta'] < 0 for r in comparisons),
            same=sum(r['stream_batch_error_delta'] == 0 for r in comparisons),
            worse=sum(r['stream_batch_error_delta'] > 0 for r in comparisons)),
        normalized_stream_vs_current=dict(better=sum(r['normalized_stream_error_delta'] < 0 for r in comparisons),
            same=sum(r['normalized_stream_error_delta'] == 0 for r in comparisons),
            worse=sum(r['normalized_stream_error_delta'] > 0 for r in comparisons)),
        normalized_stream_vs_hex_batch=dict(better=sum(r['normalized_stream_batch_error_delta'] < 0 for r in comparisons),
            same=sum(r['normalized_stream_batch_error_delta'] == 0 for r in comparisons),
            worse=sum(r['normalized_stream_batch_error_delta'] > 0 for r in comparisons)),
        limitations=['English screening corpus, not proof of broad accuracy parity.',
            'Word error ignores case and punctuation; numeric formatting can count as error.',
            'Secondary WER uses the pinned standard Whisper English normalizer on both references and hypotheses.',
            'Long fixtures reuse natural source clips; category results are reported separately.',
            'Latency is replayed release to available ASR text; capture, cleanup and paste are excluded.',
            'Current latency includes production output filters and mechanical postprocessing; Hex stops before session rotation.',
            'Hex batch applies minimum-length padding and extra trailing silence; streaming receives the original PCM.',
            'Quality streaming is unpaced; only paced latency files provide release timing.'],
        observations=comparisons)
    (args.results / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    labels = dict(current='Current Parakeet', hex_batch='Hex batch', hex_stream='Hex streaming')
    overview = []
    for label in variants:
        timing = latency.get(label, {}).get('all', {})
        overview.append('<tr><td>' + labels[label] + '</td><td>' +
            f"{100 * quality[label]['all']['normalized_word_error_rate']:.2f}%" + '</td><td>' +
            f"{100 * quality[label]['conversation']['normalized_word_error_rate']:.2f}%" + '</td><td>' +
            str(timing.get('median', 'pending')) + '</td><td>' + str(timing.get('p95', 'pending')) + '</td></tr>')
    timing_cells = []
    for row in paired_latency:
        timing_cells.append('<tr><td>' + html.escape(row['name']) + '</td><td>' +
            f"{row['duration']:.1f} s" + '</td>' + ''.join(
                '<td>' + str(row['medians'][label]) + ' ms</td>' for label in variants) +
            '<td>' + str(row['stream_saving_ms']) + ' ms</td></tr>')
    cells = []
    def render_text(text):
        escaped = html.escape(text)
        if len(text) > 600:
            return '<details><summary>' + html.escape(text[:160]) + '…</summary><p>' + escaped + '</p></details>'
        return escaped
    for row in sorted(comparisons, key=lambda r: (-r['normalized_stream_error_delta'], r['name'])):
        texts = ''.join('<td>' + render_text(row['variants'][label]['text']) +
                        f"<small>{row['variants'][label]['normalized_errors']} normalized word errors; "
                        f"{row['variants'][label]['errors']} literal errors</small></td>"
                        for label in variants)
        cells.append('<tr><td>' + html.escape(row['name']) + '</td><td>' +
                     render_text(row['reference']) + '</td>' + texts + '</tr>')
    report = ('<!doctype html><meta charset="utf-8"><title>Streaming transcription comparison</title>'
        '<style>body{font:15px system-ui;margin:32px;color:#202124}table{border-collapse:collapse;width:100%}'
        'td,th{padding:12px;border:1px solid #ddd;vertical-align:top}th{position:sticky;top:0;background:#eee}'
        'small{display:block;color:#666;margin-top:8px}td{min-width:160px;overflow-wrap:anywhere}'
        'summary{cursor:pointer}details p{white-space:normal}</style>'
        '<h1>Streaming transcription comparison</h1><p>Recognition before cleanup. '
        'Quality: 231 speech clips. Timings: 14 clips, three rounds, warmed models. '
        'Latency excludes microphone capture, cleanup and paste. Hex uses its native Metal runtime; '
        'no MLX conversion is needed. Tested on an Apple M3 Max. Lower word error rate is better.</p><table><thead><tr>'
        '<th>Path</th><th>Normalized WER</th><th>Conversational WER</th><th>Median ms</th><th>p95 ms</th>'
        '</tr></thead><tbody>' + ''.join(overview) + '</tbody></table><p>'
        'Current timing includes its output filters and mechanical text processing. Hex streaming stops '
        'when text is available, before session rotation. Hex batch includes its normal padding. '
        'The English corpus is a screening test; number formatting and imperfect references can affect WER.</p>'
        '<h2>Release latency by clip</h2><p>Medians of three rounds. Positive savings mean streaming '
        'finished earlier than current Parakeet.</p><table><thead><tr><th>Clip</th><th>Audio</th>'
        '<th>Current</th><th>Hex batch</th><th>Hex stream</th><th>Streaming savings</th>'
        '</tr></thead><tbody>' + ''.join(timing_cells) + '</tbody></table><h2>Transcript review</h2><p>'
        'Rows sorted by extra normalized streaming errors versus current Parakeet.</p><table><thead><tr>'
        '<th>Clip</th><th>Reference</th><th>Current Parakeet</th><th>Hex batch</th><th>Hex stream</th>'
        '</tr></thead><tbody>' + ''.join(cells) + '</tbody></table>')
    (args.results / 'comparison.html').write_text(report)
    print(json.dumps({k: summary[k] for k in ['quality', 'stream_vs_current', 'stream_vs_hex_batch']}, indent=2))
    print('Latency:', json.dumps({k: {g: v[g] for g in ['all', 'short', 'long']} for k, v in latency.items()}, indent=2))


if __name__ == '__main__':
    main()
