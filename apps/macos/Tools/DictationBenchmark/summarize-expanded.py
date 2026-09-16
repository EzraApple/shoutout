#!/usr/bin/env python3
"""Duration/category comparisons and exact output evidence for the frozen gate."""
from collections import Counter
import hashlib
import html
import importlib.util
import json
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('metrics',HERE/'summarize-large-models.py')
metrics=importlib.util.module_from_spec(spec);spec.loader.exec_module(metrics)
ROOT=HERE.parents[1]/'.build/expanded-eval'
fixtures=json.loads((ROOT/'audio/manifest.json').read_text())
manifest={x['name']:x for x in fixtures}
labels=['whisper','parakeet-v2','parakeet-1.1b-nemo-mel','canary-1b']
models={label:json.loads((ROOT/(label+'.json')).read_text()) for label in labels if (ROOT/(label+'.json')).exists()}
base={(r['name'],r['repetition']):r for r in models.get('whisper',[]) if r['kind']=='asr'}
lmfile=ROOT/'lm-all-transcripts.json'
lmrows=json.loads(lmfile.read_text()) if lmfile.exists() else []
lm={(r['input'],r['style'],r['repetition']):r for r in lmrows if r['kind']=='audio-lm'}

def bucket(seconds):
    return '<5s' if seconds<5 else '5-30s' if seconds<30 else '30-90s' if seconds<90 else '90s+'

def summarize(rows):
    if not rows:return None
    warm=[r for r in rows if r['repetition']>0]
    first=[r for r in rows if r['repetition']==0]
    output=dict(clips=len(first),warmCalls=len(warm),rawWER=metrics.error_rate(warm,'input') if warm else None,
        warmMs=metrics.distribution([r['wallMs'] for r in warm]),firstMs=metrics.distribution([r['wallMs'] for r in first]),
        empty=[r['name'] for r in rows if not r['final']],
        unstable=[name for name in sorted({r['name'] for r in rows}) if len({r['input'] for r in rows if r['name']==name})>1],styles={})
    for style in ['standard','casual','formal']:
        pairs=[(r,lm[r['final'],style,r['repetition']-1]) for r in warm if (r['final'],style,r['repetition']-1) in lm]
        if pairs:
            output['styles'][style]=dict(matchedCalls=len(pairs),lmMs=metrics.distribution([l['wallMs'] for r,l in pairs]),
                reconstructedMs=metrics.distribution([r['wallMs']+l['wallMs'] for r,l in pairs]),
                fallbacks=dict(Counter(l.get('fallback','none') for r,l in pairs)))
    return output

summary={};details=[]
for label,allrows in models.items():
    rows=[r for r in allrows if r['kind']=='asr']
    summary[label]=dict(overall=summarize(rows),categories={},durations={},modelLoadMs=rows[0].get('modelLoadMs'))
    for category in sorted({manifest[r['name']]['category'] for r in rows}):
        summary[label]['categories'][category]=summarize([r for r in rows if manifest[r['name']]['category']==category])
    for duration in ['<5s','5-30s','30-90s','90s+']:
        summary[label]['durations'][duration]=summarize([r for r in rows if bucket(manifest[r['name']]['duration'])==duration])
    for r in rows:
        ref=metrics.words(r['reference']);original=base.get((r['name'],r['repetition']))
        record=dict(r,label=label,category=manifest[r['name']]['category'],duration=manifest[r['name']]['duration'],
                    rawErrors=metrics.distance(ref,metrics.words(r['input'])),referenceWords=len(ref))
        if original:
            record['whisperRaw']=original['input'];record['errorDelta']=record['rawErrors']-metrics.distance(ref,metrics.words(original['input']))
        details.append(record)
joined=[]
for r in details:
    if r['repetition']==0:continue
    for style in ['standard','casual','formal']:
        l=lm.get((r['final'],style,r['repetition']-1))
        if l: joined.append(dict(name=r['name'],label=r['label'],category=r['category'],duration=r['duration'],repetition=r['repetition'],style=style,
            reference=r['reference'],raw=r['input'],postprocessed=r['final'],final=l['final'],candidate=l.get('candidate'),
            accepted=l['accepted'],fallback=l.get('fallback'),asrMs=r['wallMs'],lmMs=l['wallMs']))
output=dict(models=summary,asrOutputs=details,outputs=joined,lmCalls=len(lmrows),
    smokeFailures=[r for r in lmrows if r['kind']=='smoke-lm' and r.get('failure')],
    fixtureManifest=fixtures,datasetProvenance=json.loads((ROOT/'dataset-provenance.json').read_text()),
    sources={p.name:json.loads(p.read_text()) for p in ROOT.glob('*.sources.json')})
(ROOT/'summary.json').write_text(json.dumps(output,indent=2)+'\n')
for label,m in summary.items():
    print(label,json.dumps({k:{'WER':v['rawWER']['percent'],'warm':v['warmMs'],'first':v['firstMs'],'empty':v['empty'],'unstable':v['unstable']} for k,v in m['categories'].items()}))
if joined:
    cells=[]
    for r in joined:
        if r['repetition']!=1:continue
        values=[r['name'],r['label'],r['style'],f"{r['duration']:.1f}",r['reference'],r['raw'],r['postprocessed'],r['final'],f"{r['asrMs']:.1f}",f"{r['lmMs']:.1f}",r['fallback'] or 'accepted']
        cells.append('<tr>'+''.join('<td>'+html.escape(str(v))+'</td>' for v in values)+'</tr>')
    page='''<!doctype html><meta charset="utf-8"><title>Expanded English model comparison</title>
<style>body{font:14px system-ui;margin:24px;color:#17202a}input{padding:10px;width:420px;max-width:90%}table{border-collapse:collapse;margin-top:20px}td,th{border:1px solid #ddd;padding:10px;vertical-align:top;text-align:left}th{position:sticky;top:0;background:#edf2f7}td:nth-child(n+5):nth-child(-n+8){min-width:250px;white-space:pre-wrap}tr:nth-child(even){background:#f7f9fb}</style>
<h1>Expanded English transcription comparison</h1><p>First warm repeat shown; JSON retains all ASR and LM observations. Stage times are measured separately. Long natural clips concatenate source utterances.</p><input id="filter" aria-label="Filter outputs" placeholder="Filter model, clip, style, or text"><span id="count"></span><table><thead><tr>'''+''.join('<th>'+v+'</th>' for v in ['Clip','Model','Style','Audio seconds','Reference','Raw ASR','App processing','After LM','ASR ms','LM ms','Decision'])+'</tr></thead><tbody>'+''.join(cells)+'''</tbody></table><script>const rows=[...document.querySelectorAll('tbody tr')];const f=document.querySelector('#filter');function update(){let n=0;for(const r of rows){r.hidden=!r.textContent.toLowerCase().includes(f.value.toLowerCase());if(!r.hidden)n++;}document.querySelector('#count').textContent=` ${n} rows`;}f.addEventListener('input',update);update();</script>'''
    (ROOT/'outputs.html').write_text(page)
