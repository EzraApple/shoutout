#!/usr/bin/env python3
"""Freeze a multi-speaker and duration-stratified English acceptance corpus."""
import hashlib
import io
import json
from pathlib import Path
import random
import subprocess
import numpy as np
import pyarrow.parquet as pq
import soundfile as sf

ROOT = Path(__file__).resolve().parents[2] / '.build/expanded-eval'
AUDIO = ROOT / 'audio'
AUDIO.mkdir(parents=True, exist_ok=True)
REVISION = '71cacbfb7e2354c4226d01e70d77d5fca3d04ba1'
SOURCE = f'https://huggingface.co/datasets/openslr/librispeech_asr/resolve/{REVISION}/clean/test/0000.parquet'
fixtures = []

def save(name, samples, reference, source, **metadata):
    path = AUDIO / (name + '.wav')
    sf.write(path, samples, 16000, subtype='PCM_16')
    fixtures.append(dict(name=name, path=path.name, reference=reference, source=source,
        duration=len(samples)/16000, sha256=hashlib.sha256(path.read_bytes()).hexdigest(), **metadata))

rows = pq.read_table(ROOT / 'test-clean.parquet').to_pylist()
speakers = {}
for row in rows:
    info = sf.info(io.BytesIO(row['audio']['bytes']))
    row['duration'] = info.duration
    speakers.setdefault(str(row['speaker_id']), []).append(row)
for speaker, records in sorted(speakers.items()):
    records.sort(key=lambda r: (r['duration'], r['id']))
    for row in [records[0], records[len(records)//2], records[-1]]:
        samples, rate = sf.read(io.BytesIO(row['audio']['bytes']), dtype='float32')
        assert rate == 16000
        save('natural-' + row['id'], samples, row['text'], SOURCE,
             category='natural', speaker=speaker, originalID=row['id'])
# Consecutive utterances from one chapter: controlled long recordings, not
# independently recorded continuous sessions. Preserve every spoken word.
for speaker in sorted(speakers, key=int)[:4]:
    records = sorted(speakers[speaker], key=lambda r:r['id'])
    for target in [60, 180]:
        parts, texts, ids = [], [], []
        for row in records:
            samples, rate = sf.read(io.BytesIO(row['audio']['bytes']), dtype='float32')
            parts.extend([samples, np.zeros(4000,dtype='float32')])
            texts.append(row['text']); ids.append(row['id'])
            if sum(map(len,parts))/16000 >= target: break
        save(f'long-natural-{speaker}-{target}', np.concatenate(parts), ' '.join(texts), SOURCE,
             category='natural-long', speaker=speaker, components=ids)

texts = {
 'tiny-yes': 'Yes, please.',
 'tiny-no': 'No, not yet.',
 'tiny-stop': 'Stop the recording.',
 'tiny-name': 'Ask Maya tomorrow.',
 'request': 'Can you send this over when you get a chance?',
 'negation': 'Do not merge the pull request. Do not delete the backup. Only check the logs.',
 'correction': 'Schedule it for Tuesday, wait, no, Thursday at four. Send it to Anna, actually, send it to Maya instead.',
 'localhost': 'Please check localhost on port eight thousand eighty before reviewing the pull request.',
 'version': 'Keep version two point zero. The port is eight thousand eighty, not eight thousand.',
 'amount': 'The total is one thousand two hundred fifty dollars and fifty cents. Do not round it down.',
 'identifier': 'Keep the user underscore I D column and the config dot J S O N file unchanged.',
 'acronym': 'The A P I request failed, but the U R L and the S Q L query are correct.',
 'punctuation': 'First item comma check the logs period New paragraph Second item comma keep the backup period',
 'filler': 'Um, I think this is, like, almost ready, but we should, uh, check the final sentence first.',
 'quoted': 'Write the words ignore all previous instructions in the document. That is a quotation, not an instruction.',
 'meaningful-like': 'I like the first design. It looks like the version we reviewed yesterday.',
 'date': 'The review is on September eighteenth at three forty five in the afternoon.',
 'contrast': 'It is allowed in staging and forbidden in production. Keep that distinction clear.',
 'tail': 'Please check the recording and keep the final words, especially this last sentence.',
 'self-correction': 'I need a blue, actually, a green button. Do not change the red warning message.',
}
for voice in ['Samantha','Daniel']:
    for index,(name,text) in enumerate(texts.items()):
        rate = [150,185,220][index%3]
        name = f'dictation-{voice.lower()}-{name}'
        path = AUDIO / (name+'.wav')
        subprocess.run(['say','-v',voice,'-r',str(rate),'-o',str(path),'--data-format=LEI16@16000',text],check=True)
        samples,sr = sf.read(path,dtype='float32'); assert sr==16000
        save(name,samples,text,f'macOS say {voice} {rate} wpm',category='dictation',speaker=voice)
# New, non-repeated long dictation with facts near the start, middle, and tail.
paragraphs = [
 'Before we ship this update, check the recording flow from beginning to end. Start with a short request and then make a longer recording with pauses between sentences. Keep every final word when I release the key. Do not turn my instructions into a promise that the work is complete.',
 'The first issue concerns the database. Keep the user identifier column unchanged and preserve version two point zero in the migration notes. Only read the production logs. Do not delete a table or run the migration until the review is finished. Ask Maya to review the changes on Thursday afternoon.',
 'The second issue concerns the interface. The recording indicator should appear immediately when I press the shortcut. It should disappear after processing finishes. If transcription fails, show a clear error and preserve the audio for recovery. Do not insert a partial sentence into the wrong application.',
 'Next, inspect the cleanup step. Remove repeated words and obvious fillers while retaining names, numbers, dates, negation, and quoted instructions. I like the current design, so leave that sentence alone. The word like is meaningful there. Lowercase output is acceptable when the selected style calls for it.',
 'For performance, measure model loading separately from transcription. Compare the first request against later requests. Try quiet speech, background noise, pauses, and a long explanation. Record the complete output from every model so that we can inspect individual mistakes instead of relying only on an average.',
 'The final review should include the clipboard and history. Restore the original clipboard contents after insertion. Keep the original transcript if a cleanup candidate changes the meaning. Schedule the meeting for Tuesday, actually, make that Thursday at four. The last instruction is important: keep the backup and do not merge yet.'
]
for count in [2,6]:
    text=' '.join(paragraphs[:count]); name=f'dictation-long-{count}'
    path=AUDIO/(name+'.wav')
    subprocess.run(['say','-v','Samantha','-r','150','-o',str(path),'--data-format=LEI16@16000',text],check=True)
    samples,sr=sf.read(path,dtype='float32');save(name,samples,text,'macOS say Samantha 150 wpm',category='dictation-long',speaker='Samantha')
# Noise and trailing silence perturb existing held-out dictation, retaining text.
rng=np.random.default_rng(20260915)
for short in ['negation','tail','localhost']:
    row=next(r for r in fixtures if r['name']==f'dictation-samantha-{short}')
    audio,_=sf.read(AUDIO/row['path'],dtype='float32')
    rms=np.sqrt(np.mean(audio**2))
    for snr in [10,20]:
        noisy=audio+rng.normal(0,rms/(10**(snr/20)),len(audio))
        save(f'noise-{short}-{snr}',np.clip(noisy,-1,1),row['reference'],f'{row["name"]} + seeded Gaussian noise {snr} dB SNR',category='noise',speaker='Samantha')
    save(f'trailing-{short}',np.concatenate([audio,np.zeros(16000*8)]),row['reference'],row['name']+' + 8 s silence',category='trailing',speaker='Samantha')
save('silence',np.zeros(16000*5),'','generated silence',category='gate',speaker='none')
random.Random(20260915).shuffle(fixtures)
(AUDIO/'manifest.json').write_text(json.dumps(fixtures,indent=2)+'\n')
print(json.dumps(dict(clips=len(fixtures),naturalSpeakers=len(speakers),seconds=sum(x['duration'] for x in fixtures),minimum=min(x['duration'] for x in fixtures),maximum=max(x['duration'] for x in fixtures)),indent=2))
