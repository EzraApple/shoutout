#!/usr/bin/env python3
"""Run the frozen expanded acceptance corpus, preserving every observation."""
import hashlib
import json
from pathlib import Path
import random
import subprocess
import sys

HERE=Path(__file__).resolve().parent
MACOS=HERE.parents[1]
ROOT=MACOS/'.build/expanded-eval'
MANIFEST=ROOT/'audio/manifest.json'

def run(label, arguments, expected):
    output=ROOT/(label+'.json')
    if output.exists():
        rows=json.loads(output.read_text())
        if len(rows)==expected:
            print('Reuse '+label,flush=True);return rows
        output.replace(output.with_suffix('.incomplete.json'))
    print('Start '+label,flush=True)
    with (ROOT/(label+'.log')).open('w') as log:
        subprocess.run([sys.executable,str(HERE/'run.py'),'--output',str(output),
            '--cache-mib','0',*arguments],stdout=log,stderr=subprocess.STDOUT,check=True)
    rows=json.loads(output.read_text());assert len(rows)==expected,(label,len(rows),expected)
    print('Finished '+label,flush=True);return rows

if __name__=='__main__':
    manifest=json.loads(MANIFEST.read_text())
    expected=sum(3 if r['reference'] else 1 for r in manifest)
    audio=['--audio-only','--audio-manifest',str(MANIFEST),'--repetitions','3','--measure-first-pass']
    configurations=[
        ('parakeet-v2',['--fluid-audio',str(MACOS/'.build/FluidAudio-model-benchmark'),'--asr','parakeet','--parakeet-version','v2']),
        ('whisper',['--skip-build']),
        ('parakeet-1.1b-nemo-mel',['--skip-build','--asr','python','--python-model','parakeet-1.1b-nemo-mel']),
        ('canary-1b',['--skip-build','--asr','python','--python-model','canary-1b']),
    ]
    combined=[]
    for label,args in configurations:
        combined.extend(dict(r,label=label) for r in run(label,audio+args,expected))
    (ROOT/'asr-combined.json').write_text(json.dumps(combined,indent=2)+'\n')
    # Hold one shared measurement set per exact transcript, with two passes per style.
    texts=sorted({r['final'] for r in combined if r['kind']=='asr' and r['final']})
    random.Random(20260915).shuffle(texts)
    inputs=[dict(name=f'expanded-{i:04d}',input=t) for i,t in enumerate(texts)]
    path=ROOT/'lm-inputs.json';path.write_text(json.dumps(inputs,indent=2)+'\n')
    print(f'Cleanup {len(inputs)} distinct texts',flush=True)
    run('lm-all-transcripts',['--skip-build','--lm-inputs',str(path),'--repetitions','2','--reverse-odd-rounds'],len(inputs)*6+46)
