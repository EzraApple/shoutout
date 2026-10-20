#!/usr/bin/env python3
"""Diagnostic rescore for explicit written/spoken formatting equivalents."""
import json
import re

from compare_hex_modes import HERE, RESULTS, save
from summarize import distance, EnglishTextNormalizer

NORMALIZE = EnglishTextNormalizer()


def normalize_format(text):
    # Keep the spoken filename/URL form before the base scorer removes punctuation.
    text = re.sub(r'\bconfig\.json\b', 'config dot json', text, flags=re.I)
    text = re.sub(r'\bexample\.com\b', 'example dot com', text, flags=re.I)
    # Match clock notation to the base scorer's representation of spoken time.
    text = re.sub(r'\b(\d{1,2})[:.](\d{2})\s*([ap])[.\s]*m\b',
        lambda match: match[1] + match[2] + ' ' + match[3] + ' m', text, flags=re.I)
    text = NORMALIZE(text)
    # A month followed by an ordinal and by a cardinal describes the same date.
    return re.sub(
        r'\b((?:january|february|march|april|may|june|july|august|september|october|november|december)\s+\d+)(?:st|nd|rd|th)\b',
        r'\1', text)


def main():
    for first, second in [('config dot json', 'config.json'),
                          ('example dot com slash status', 'example.com/slash status'),
                          ('October nineteenth', 'October 19'),
                          ('three forty-five p.m.', '3:45 p.m.'),
                          ('three forty-five p.m.', '3.45pm')]:
        assert normalize_format(first) == normalize_format(second), (first, second)
    for first, second in [('Maya Chen', 'Mayochen'), ('status page is', 'status pages'),
                          ('$1250.50', '1250.50'), ('the complete request', 'a complete request')]:
        assert normalize_format(first) != normalize_format(second), (first, second)
    source = json.loads((RESULTS / 'summary.json').read_text())
    scores, clips = {}, {}
    for engine in ['current', 'hexBatchApp', 'hexStreamApp']:
        errors = words = 0
        for name, row in source['perClip'].items():
            reference = normalize_format(row['reference']).split()
            hypothesis = normalize_format(row[engine]['text']).split()
            count = distance(reference, hypothesis)
            errors += count
            words += len(reference)
            clips.setdefault(name, {})[engine] = dict(errors=count, normalized=' '.join(hypothesis))
        scores[engine] = dict(errors=errors, words=words, wer=errors/words)
    normalized_matches = sum(row['hexBatchApp']['normalized'] == row['hexStreamApp']['normalized']
        for row in source['perClip'].values())
    matching_tail = all(row['streamMatched']['text'] == row['streamAppTail']['text']
        for row in source['perClip'].values())
    normalized_tail = all(row['streamMatched']['normalized'] == row['streamAppTail']['normalized']
        for row in source['perClip'].values())
    audit = dict(scores=scores, perClip=clips, primaryScores=source['scores'],
        standardNormalizedBatchStreamMatches=normalized_matches, speechClips=len(clips),
        stream80msAndMatched200msTextsIdentical=matching_tail,
        stream80msAndMatched200msNormalizedTextsIdentical=normalized_tail,
        interpretation='Post-hoc diagnostic audit, not a new independent benchmark or a replacement for standard WER.',
        rules=['Expand literal config.json to config dot json before scoring.',
               'Expand literal example.com to example dot com before scoring.',
               'Treat equivalent colon/dot clock notation and spoken time alike.',
               'Treat cardinal/ordinal day numbers after a month alike.'],
        retainedDifferences=['Names, missing currency markers, word fusions, articles, and other word changes.'],
        remainingLimits=['The base scorer ignores URL punctuation; malformed output URLs still need product review.',
            'TTS intended-text references are not human phonetic ground truth.',
            'Two long passages recur in quiet/noisy variants, so these are correlated errors.'])
    save('format-audit.json', audit)
    print(json.dumps({key: value for key, value in audit.items() if key != 'perClip'}, indent=2))


if __name__ == '__main__':
    main()
