#!/usr/bin/env python3
"""Narrow authored-fact checks; complements WER and manual output review."""
import json
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[2]/'.build/expanded-eval'

def normalize(text):
    text=text.lower().replace('’',"'")
    replacements={
        'do not': "don't", 'does not': "doesn't", 'cannot': "can't",
        'two point zero':'2.0','eight thousand eighty':'8080','eight thousand':'8000',
        'user underscore i d':'user_id','user underscore id':'user_id',
        'config dot j s o n':'config.json',
        'one thousand two hundred fifty dollars and fifty cents':'1250.50',
        '$1,250.50':'1250.50', '$1250.50':'1250.50',
    }
    for a,b in replacements.items():text=text.replace(a,b)
    return re.sub(r'\s+',' ',text).strip()

checks={
 'negation': ["don't merge", "don't delete", 'only check'],
 'version': ['2.0','8080','not 8000'],
 'amount': ['1250.50',"don't round"],
 'localhost': ['localhost','8080','pull request'],
 'identifier': ['user_id','config.json'],
 'contrast': ['allowed in staging','forbidden in production'],
 'tiny-no': ['no','not yet'],
 'tiny-stop': ['stop','recording'],
 'tiny-name': ['maya','tomorrow'],
 'self-correction': ['green','red',"don't change"],
 'tail': ['final words','last sentence'],
}

def missing(name,text):
    # Only fixture names explicitly defined above; no inferred semantic labels.
    key=next((k for k in sorted(checks,key=len,reverse=True) if name.endswith('-'+k)),None)
    if key is None:return []
    normalized=normalize(text)
    return [x for x in checks[key] if x not in normalized]

if __name__=='__main__':
    data=json.loads((ROOT/'summary.json').read_text());failures=[]
    for r in data['asrOutputs']:
        if r['repetition']!=1:continue
        absent=missing(r['name'],r['input'])
        if absent:failures.append(dict(stage='raw',name=r['name'],label=r['label'],missing=absent,text=r['input']))
    for r in data['outputs']:
        if r['repetition']!=1:continue
        absent=missing(r['name'],r['final'])
        if absent:failures.append(dict(stage=r['style'],name=r['name'],label=r['label'],missing=absent,text=r['final']))
    (ROOT/'fact-audit.json').write_text(json.dumps({'limitations':'Phrase-preservation diagnostic, not a general semantic scorer. Equivalent unlisted paraphrases require manual review.','failures':failures},indent=2)+'\n')
    print(json.dumps(failures,indent=2))
