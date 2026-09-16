#!/usr/bin/env python3
"""Confidence diagnostics and a separately frozen conversational holdout."""
import json
import os
from pathlib import Path
import random
import subprocess
import sys
HERE=Path(__file__).resolve().parent
MACOS=HERE.parents[1]
ROOT=MACOS/'.build/expanded-eval'

def run(label,args,expected,metrics=False):
    output=ROOT/(label+'.json')
    if output.exists() and len(json.loads(output.read_text()))==expected:
        print('Reuse '+label,flush=True);return json.loads(output.read_text())
    env=dict(os.environ)
    if metrics:
        path=ROOT/(label+'.confidence.jsonl');path.write_text('')
        env['BENCH_PARAKEET_METRICS']=str(path)
    print('Start '+label,flush=True)
    with (ROOT/(label+'.log')).open('w') as log:
        subprocess.run([sys.executable,str(HERE/'run.py'),'--output',str(output),'--cache-mib','0',*args],env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
    rows=json.loads(output.read_text());assert len(rows)==expected,(label,len(rows),expected)
    print('Finished '+label,flush=True);return rows

if __name__=='__main__':
    native_rows=[]
    for index,(label,manifest) in enumerate([
        ('native-pilot',ROOT/'audio/native-pilot.json'),
        ('native-expanded',ROOT/'audio/manifest.json'),
        ('native-old',MACOS/'.build/dictation-audio/model-manifest.json')]):
        build=['--fluid-audio',str(MACOS/'.build/FluidAudio-model-benchmark'),
               '--mlx-audio',str(MACOS/'.build/mlx-audio-swift-benchmark')] if index==0 else ['--skip-build']
        fixtures=json.loads(manifest.read_text())
        expected=sum(3 if r['reference'] else 1 for r in fixtures)
        result=run(label,build+['--asr','swift-parakeet','--audio-only','--audio-manifest',str(manifest),
                   '--repetitions','3','--measure-first-pass'],expected)
        native_rows.extend(result)
        assert all(r['final'] for r in result if r['kind']=='asr'), 'Native runtime returned empty speech; inspect before proceeding'
    for index,(label,manifest) in enumerate([
        ('confidence-old',MACOS/'.build/dictation-audio/model-manifest.json'),
        ('confidence-expanded',ROOT/'audio/manifest.json')]):
        args=['--skip-build']
        args+=['--asr','parakeet','--parakeet-version','v2','--audio-only','--audio-manifest',str(manifest),'--repetitions','1','--measure-first-pass']
        run(label,args,len(json.loads(manifest.read_text())),metrics=True)
    audio=['--skip-build','--audio-only','--audio-manifest',str(ROOT/'conversation-audio/manifest.json'),'--repetitions','3','--measure-first-pass']
    configurations=[('canary-1b',['--asr','python','--python-model','canary-1b']),
        ('parakeet-1.1b-nemo-mel',['--asr','python','--python-model','parakeet-1.1b-nemo-mel']),
        ('whisper',[]),('parakeet-v2',['--asr','parakeet','--parakeet-version','v2']),
        ('parakeet-1.1b-swift',['--asr','swift-parakeet'])]
    rows=[]
    for label,args in configurations:
        rows.extend(dict(r,label=label) for r in run('conversation-'+label,audio+args,150,metrics=label=='parakeet-v2'))
    (ROOT/'conversation-asr-combined.json').write_text(json.dumps(rows,indent=2)+'\n')
    existing=json.loads((ROOT/'lm-all-transcripts.json').read_text())
    existing+=json.loads((MACOS/'.build/large-model-comparison/lm-all-transcripts.json').read_text())
    previous={r['input'] for r in existing if r['kind']=='audio-lm'}
    texts=sorted({r['final'] for r in rows+native_rows if r['final']}-previous)
    random.Random(20260916).shuffle(texts)
    inputs=ROOT/'conversation-lm-inputs.json'
    inputs.write_text(json.dumps([dict(name=f'conversation-{i:04d}',input=t) for i,t in enumerate(texts)],indent=2)+'\n')
    run('conversation-lm',['--skip-build','--lm-inputs',str(inputs),'--repetitions','2','--reverse-odd-rounds'],len(texts)*6+46)
