#!/usr/bin/env python3
"""Freeze a second, independently selected public conversational holdout."""
import hashlib
import io
import json
from pathlib import Path
import random
import urllib.request
import pyarrow.parquet as pq
import soundfile as sf
ROOT=Path(__file__).resolve().parents[2]/'.build/expanded-eval'
AUDIO=ROOT/'conversation-audio';AUDIO.mkdir(exist_ok=True)
revision='3fe50170d520c951957b86996ef082a6ab87b394'
url=f'https://huggingface.co/datasets/pipecat-ai/stt-benchmark-data/resolve/{revision}/data/train-00000-of-00001.parquet'
meta=json.load(urllib.request.urlopen(f'https://huggingface.co/api/datasets/pipecat-ai/stt-benchmark-data/tree/{revision}/data'))[0]
checksum=hashlib.sha256((ROOT/'pipecat.parquet').read_bytes()).hexdigest();assert checksum==meta['lfs']['oid']
rows=sorted(pq.read_table(ROOT/'pipecat.parquet').to_pylist(),key=lambda r:r['sample_id'])
selected=random.Random(20260916).sample(rows,50)
fixtures=[]
for row in selected:
    name='conversation-'+row['sample_id'];path=AUDIO/(name+'.wav')
    audio,rate=sf.read(io.BytesIO(row['audio']['bytes']),dtype='float32');assert rate==16000
    sf.write(path,audio,rate,subtype='PCM_16')
    fixtures.append(dict(name=name,path=path.name,reference=row['transcription'],category='conversation',duration=len(audio)/rate,source=url,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
(AUDIO/'manifest.json').write_text(json.dumps(fixtures,indent=2)+'\n')
(ROOT/'conversation-provenance.json').write_text(json.dumps(dict(revision=revision,source=url,sha256=checksum,selection='50 seeded random samples from sample_id-sorted 1000 rows; seed 20260916',referenceLimit='Publisher-provided ground truth; not independently human-transcribed here'),indent=2)+'\n')
print(len(fixtures),min(r['duration'] for r in fixtures),max(r['duration'] for r in fixtures))
