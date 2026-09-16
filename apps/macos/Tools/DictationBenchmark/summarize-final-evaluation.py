#!/usr/bin/env python3
"""Export measured stages, validator replays, and searchable per-clip evidence."""
from collections import Counter
import html
import gzip
import importlib.util
import json
from pathlib import Path
HERE=Path(__file__).resolve().parent
MACOS=HERE.parents[1]
ROOT=MACOS/'.build/expanded-eval'
DEST=MACOS.parents[1]/'docs/benchmarks'
spec=importlib.util.spec_from_file_location('metrics',HERE/'summarize-large-models.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def read(p):return json.loads(p.read_text())
def bucket(s):return '<5s' if s<5 else '5-30s' if s<30 else '30-90s' if s<90 else '90s+'
replay=read(ROOT/'validator-replay-all.json')
lookup={};lmobservations=[]
paths=[MACOS/'.build/large-model-comparison/lm-all-transcripts.json',ROOT/'lm-all-transcripts.json',ROOT/'conversation-lm.json',ROOT/'chunked-lm.json']
for path in paths:
 if not path.exists():continue
 rows=read(path)
 for change in replay['changes']:
  if Path(change['file']).name==path.name and ('expanded-eval' in change['file'])==('expanded-eval' in str(path)):
   row=rows[change['index']]
   assert row['candidate']==change['candidate']
   row.update(final=change['afterFinal'],accepted=change['afterAccepted'],fallback=change['afterFallback'],validatorReplayed=True)
 for row in rows:
  if row['kind']=='audio-lm':lookup[row['input'],row['style'],row['repetition']]=row
 lmobservations.extend(dict(row,source=path.name,corpus='expanded' if 'expanded-eval' in str(path) else 'previous') for row in rows)
expanded={'whisper':'whisper','parakeet-v2':'parakeet-v2','parakeet-1.1b-python':'parakeet-1.1b-nemo-mel','parakeet-1.1b-native':'native-expanded','canary-1b':'canary-1b','canary-1b-chunked':'canary-1b-chunked'}
conversation={'whisper':'conversation-whisper','parakeet-v2':'conversation-parakeet-v2','parakeet-1.1b-python':'conversation-parakeet-1.1b-nemo-mel','parakeet-1.1b-native':'conversation-parakeet-1.1b-swift','canary-1b':'conversation-canary-1b'}
models={};asr=[];outputs=[]
def stats(rows):
 warm=[x for x in rows if x['repetition']>0];first=[x for x in rows if x['repetition']==0]
 result=dict(clips=len(first),warmCalls=len(warm),rawWER=m.error_rate(warm,'input'),warmMs=m.distribution([x['wallMs'] for x in warm]),firstMs=m.distribution([x['wallMs'] for x in first]),empty=sorted({x['name'] for x in rows if not x['final']}),styles={})
 for style in ['standard','casual','formal']:
  pairs=[(x,lookup[x['final'],style,x['repetition']-1]) for x in warm if (x['final'],style,x['repetition']-1) in lookup]
  empty=[x for x in warm if not x['final']]
  result['styles'][style]=dict(matchedCalls=len(pairs),emptyASRCalls=len(empty),lmMs=m.distribution([l['wallMs'] for x,l in pairs]),reconstructedMs=m.distribution([x['wallMs']+l['wallMs'] for x,l in pairs]+[x['wallMs'] for x in empty]),fallbacks=dict(Counter(l.get('fallback') or 'none' for x,l in pairs)))
 return result
for corpus,configs,manifestpath in [('expanded',expanded,ROOT/'audio/manifest.json'),('conversation',conversation,ROOT/'conversation-audio/manifest.json')]:
 manifest={x['name']:x for x in read(manifestpath)};models[corpus]={}
 for label,filename in configs.items():
  path=ROOT/(filename+'.json')
  if not path.exists():continue
  allrows=read(path);rows=[x for x in allrows if x['kind']=='asr']
  for x in rows:x.update(label=label,corpus=corpus,category=manifest[x['name']].get('category','conversation'),duration=manifest[x['name']]['duration'])
  result=dict(overall=stats(rows),loadMs=rows[0]['modelLoadMs'],durations={},categories={})
  for key in sorted({bucket(x['duration']) for x in rows}):result['durations'][key]=stats([x for x in rows if bucket(x['duration'])==key])
  for key in sorted({x['category'] for x in rows}):result['categories'][key]=stats([x for x in rows if x['category']==key])
  models[corpus][label]=result;asr.extend(rows)
  for x in rows:
   if x['repetition']==0:continue
   for style in ['standard','casual','formal']:
    l=lookup.get((x['final'],style,x['repetition']-1))
    outputs.append(dict(corpus=corpus,label=label,name=x['name'],duration=x['duration'],reference=x['reference'],raw=x['input'],base=x['final'],style=style,repetition=x['repetition'],final=l['final'] if l else '',candidate=l.get('candidate') if l else None,decision=(l.get('fallback') or 'accepted') if l else ('asr_empty' if not x['final'] else 'unmeasured'),asrMs=x['wallMs'],lmMs=l['wallMs'] if l else 0,validatorReplayed=l.get('validatorReplayed',False) if l else False))
pipelines={}
for label in ['native','whisper']:
 rows=read(ROOT/(f'pipeline-{label}.json'));warm=[x for x in rows if x['kind']=='pipeline' and x['repetition']>0]
 pipelines[label]=dict(rows=rows,warmCalls=len(warm),totalMs=m.distribution([x['wallMs'] for x in warm]),asrMs=m.distribution([x['asrMs'] for x in warm]),lmMs=m.distribution([x['lmMs'] for x in warm]),modelLoadMs=rows[0]['modelLoadMs'],empty=sorted({x['name'] for x in warm if not x['final']}),verificationCalls=sum(bool(x.get('asrFallbacks')) for x in warm))
old={}
for label,path in [('whisper',MACOS/'.build/large-model-comparison/whisper.json'),('native',ROOT/'native-old.json')]:
 rows=[x for x in read(path) if x['kind']=='asr'];old[label]=dict(clips=len({x['name'] for x in rows}),rawWER=m.error_rate(rows,'input'),empty=sorted({x['name'] for x in rows if not x['final']}))
provenance={p.name:read(p) for pattern in ['*.sources.json','*.dependencies.json','*provenance.json'] for p in ROOT.glob(pattern)}
result=dict(models=models,pipeline=pipelines,oldCorpus=old,asrObservations=asr,outputs=outputs,lmObservations=lmobservations,validatorReplay=replay,provenance=provenance,fixtures=dict(expanded=read(ROOT/'audio/manifest.json'),conversation=read(ROOT/'conversation-audio/manifest.json'),pipeline=read(ROOT/'audio/pipeline-manifest.json')))
if (ROOT/'final-validation.json').exists():result['validation']=read(ROOT/'final-validation.json')
DEST.mkdir(parents=True,exist_ok=True)
encoded=(json.dumps(result,separators=(',',':'))+'\n').encode()
(DEST/'2026-09-15-expanded-models-observations.json.gz').write_bytes(gzip.compress(encoded,mtime=0))
summary={k:v for k,v in result.items() if k not in ['asrObservations','outputs','lmObservations']}
(DEST/'2026-09-15-expanded-models.json').write_text(json.dumps(summary,indent=2)+'\n')
cells=[]
for x in outputs:
 if x['repetition']!=1:continue
 values=[x['corpus'],x['name'],x['label'],x['style'],f"{x['duration']:.2f}",x['reference'],x['raw'],x['final'],f"{x['asrMs']:.1f}",f"{x['lmMs']:.1f}",x['decision']]
 cells.append('<tr>'+''.join('<td>'+html.escape(str(v)).replace('\n','&#10;').replace('\r','&#13;')+'</td>' for v in values)+'</tr>')
page='''<!doctype html><meta charset="utf-8"><title>Expanded English transcription evaluation</title><style>body{font:14px system-ui;margin:24px;color:#17202a}input{padding:10px;width:480px}table{border-collapse:collapse;margin-top:20px}td,th{border:1px solid #ddd;padding:10px;vertical-align:top;text-align:left}th{position:sticky;top:0;background:#edf2f7}td:nth-child(n+6):nth-child(-n+8){min-width:280px;white-space:pre-wrap}tr:nth-child(even){background:#f7f9fb}</style><h1>English transcription: short and long recordings</h1><p>First warm repeat shown. ASR and LM timings below were measured separately; see the report for consecutive pipeline measurements. Old LM candidates were revalidated with the final guard; no new generation is implied. JSON retains every observation.</p><input id="filter" aria-label="Filter outputs" placeholder="Filter clip, model, style, or text"><span id="count"></span><table><thead><tr>'''+''.join('<th>'+x+'</th>' for x in ['Corpus','Clip','Model','Style','Audio seconds','Reference','Raw ASR','After LM','ASR ms','LM ms','Decision'])+'</tr></thead><tbody>'+''.join(cells)+'''</tbody></table><script>const rows=[...document.querySelectorAll('tbody tr')],f=document.querySelector('#filter');function update(){let n=0;for(const r of rows){r.hidden=!r.textContent.toLowerCase().includes(f.value.toLowerCase());if(!r.hidden)n++;}document.querySelector('#count').textContent=` ${n} rows`;}f.addEventListener('input',update);update();</script>'''
(DEST/'2026-09-15-expanded-models.html').write_text(page)
(ROOT/'final-summary.json').write_text(json.dumps(dict(models=models,pipeline={l:{k:v for k,v in p.items() if k!='rows'} for l,p in pipelines.items()},oldCorpus=old),indent=2)+'\n')
for corpus,configs in models.items():
 print(corpus)
 for label,v in configs.items():
  a=v['overall'];print(label,a['rawWER'],a['warmMs'],a['styles']['casual'], 'empty',a['empty'])
print('pipeline', {l:{k:v for k,v in p.items() if k!='rows'} for l,p in pipelines.items()})
print('old',old)
