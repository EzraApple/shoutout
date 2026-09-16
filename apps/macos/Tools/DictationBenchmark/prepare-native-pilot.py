#!/usr/bin/env python3
"""Pin a native-runtime pilot spanning the duration and content risks already found."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]/'.build/expanded-eval'
source=json.loads((ROOT/'audio/manifest.json').read_text())
names={
 'dictation-samantha-request','dictation-samantha-version','dictation-samantha-localhost',
 'dictation-samantha-identifier','dictation-samantha-negation','dictation-daniel-tiny-stop',
 'natural-8224-274381-0006','natural-5105-28241-0015','long-natural-121-180',
 'dictation-long-6','noise-localhost-10','silence',
}
rows=[r for r in source if r['name'] in names];assert len(rows)==len(names)
(ROOT/'audio/native-pilot.json').write_text(json.dumps(rows,indent=2)+'\n')
print(len(rows))
