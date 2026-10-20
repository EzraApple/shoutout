#!/usr/bin/env python3
"""Summarize frozen app replay results, keeping raw ASR and cleanup separate."""
import collections
import html
import json
import math
from pathlib import Path
import statistics
import sys

HERE = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE.parent / '.build/scoring'))
from whisper_normalizer import EnglishTextNormalizer


def distance(a, b):
    previous = list(range(len(b) + 1))
    for index, word in enumerate(a, 1):
        current = [index]
        for column, other in enumerate(b, 1):
            current.append(min(current[-1] + 1, previous[column] + 1,
                               previous[column - 1] + (word != other)))
        previous = current
    return previous[-1]


def timings(values):
    values = sorted(values)
    return dict(n=len(values), median=round(statistics.median(values), 2),
                p95=round(values[math.ceil(len(values) * .95) - 1], 2))


def rows(path):
    return [r for r in json.loads(path.read_text()) if r['name'] != 'warmup-not-scored']


def main():
    results = HERE / 'results'
    normalize = EnglishTextNormalizer()
    quality, latency = {}, {}
    all_rows = {}
    for engine in ['parakeet', 'hexStreaming']:
        clips = rows(results / f'{engine}-quality.json')
        assert len(clips) == 23 and sum(r['status'] == 'silent' for r in clips) == 1
        for row in clips:
            row['errors'] = distance(normalize(row['reference']).split(), normalize(row['rawText']).split())
            row['words'] = len(normalize(row['reference']).split())
        all_rows[engine] = {r['name']: r for r in clips}
        quality[engine] = dict(clips=len(clips), errors=sum(r['errors'] for r in clips),
            words=sum(r['words'] for r in clips),
            wer=round(sum(r['errors'] for r in clips) / sum(r['words'] for r in clips), 5),
            silence=[r['name'] for r in clips if r['status'] == 'silent'])
        observations = []
        for path in sorted(results.glob(f'{engine}-latency-*.json')):
            observations += rows(path)
        if observations:
            assert len(observations) == 24, (engine, len(observations))
            assert all(value == 3 for value in collections.Counter(r['name'] for r in observations).values())
            speech = [r for r in observations if r['status'] != 'silent']
            assert all(r['paced'] for r in speech)
            latency[engine] = dict(
                asr=timings([r['stopToASRMs'] for r in speech]),
                sink=timings([r['stopToSinkMs'] for r in speech]),
                by_clip={name: dict(
                    asr=timings([r['stopToASRMs'] for r in speech if r['name'] == name]),
                    sink=timings([r['stopToSinkMs'] for r in speech if r['name'] == name]))
                    for name in sorted({r['name'] for r in speech})},
                transcript_changes=[r['name'] for r in speech
                    if r['rawText'] != all_rows[engine][r['name']]['rawText']],
                observations=observations)
    summary = dict(quality=quality, latency=latency, observations=all_rows,
        limitations=[
            'Fresh synthetic English speech; fixed intended TTS text, not human phonetic references.',
            'Standard English normalization still penalizes some equivalent dates, times, filenames, and URLs.',
            'Two long passages recur in quiet/noisy copies; WER is a screening score.',
            'ASR and sink timings include an 80ms simulated hold tail; microphone, converter, key events, paste and energy are excluded.',
            'Production capture collection, stream queue, ASR filters and unchanged cleanup services are used.',
            'No custom dictionary entries are applied in replay; outputs are saved locally without insertion.'])
    (results / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    body = []
    for engine in quality:
        t = latency.get(engine, {})
        body.append('<tr><td>' + engine + '</td><td>' + f"{quality[engine]['wer']*100:.2f}%" + '</td><td>' +
            str(t.get('asr', {}).get('median', 'pending')) + '</td><td>' +
            str(t.get('sink', {}).get('median', 'pending')) + '</td></tr>')
    timing_rows = []
    if len(latency) == 2:
        for name, values in latency['parakeet']['by_clip'].items():
            other = latency['hexStreaming']['by_clip'][name]
            timing_rows.append('<tr><td>' + html.escape(name) + '</td>' + ''.join(
                '<td>' + str(value) + '</td>' for value in [values['asr']['median'], other['asr']['median'],
                    values['sink']['median'], other['sink']['median']]) + '</tr>')
    texts = []
    for name, current in all_rows['parakeet'].items():
        other = all_rows['hexStreaming'][name]
        texts.append('<tr><td>' + html.escape(name) + '</td>' + ''.join('<td>' + html.escape(text) + '</td>'
            for text in [current['reference'], current['rawText'], other['rawText'], current['finalText'], other['finalText']]) + '</tr>')
    report = ('<!doctype html><meta charset="utf-8"><title>Local streaming app trial</title>'
        '<style>body{font:15px system-ui;margin:32px;color:#202124}table{border-collapse:collapse;width:100%;margin:20px 0}'
        'td,th{border:1px solid #ddd;padding:12px;vertical-align:top}th{background:#eee}td{overflow-wrap:anywhere}</style>'
        '<h1>Local streaming app trial</h1><p>23 fresh TTS clips. Eight latency controls, three rounds; one silence '
        'control excluded from latency. Real-time replay includes the 80ms hold tail, shared audio gates, ASR filters '
        'and unchanged standard cleanup. Text goes to a local result file.</p><table><tr><th>Engine</th><th>Normalized WER</th>'
        '<th>Median stop to ASR, ms</th><th>Median stop to cleaned text, ms</th></tr>' + ''.join(body) + '</table>'
        '<p>WER still counts some equivalent number, date, filename, and URL formatting as errors. Names and key facts '
        'need separate review. Physical mic/converter, keyboard handling, insertion and battery are not measured.</p>'
        '<h2>Per-clip medians, ms</h2><table><tr><th>Clip</th><th>Current ASR</th><th>Streaming ASR</th>'
        '<th>Current cleaned text</th><th>Streaming cleaned text</th></tr>' + ''.join(timing_rows) + '</table>'
        '<h2>Transcripts before and after cleanup</h2><table><tr><th>Clip</th><th>Reference</th><th>Current raw</th>'
        '<th>Streaming raw</th><th>Current cleaned</th><th>Streaming cleaned</th></tr>' + ''.join(texts) + '</table>')
    (results / 'comparison.html').write_text(report)
    print(json.dumps(dict(quality=quality, latency={k:{s:v[s] for s in ['asr','sink','transcript_changes']} for k,v in latency.items()}), indent=2))


if __name__ == '__main__':
    main()
