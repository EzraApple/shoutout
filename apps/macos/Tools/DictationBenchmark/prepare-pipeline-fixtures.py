#!/usr/bin/env python3
"""Add spoken and unspoken terminal-phrase controls to the native pilot."""
import hashlib
import json
from pathlib import Path
import subprocess
import numpy as np
import soundfile as sf
ROOT=Path(__file__).resolve().parents[2]/'.build/expanded-eval'
AUDIO=ROOT/'audio'
parts={}
for name,text in [('prefix','Please keep the backup.'),('thanks','Thank you.'),('contiguous','Please keep the backup. Thank you.')]:
    path=AUDIO/(f'terminal-{name}-source.wav')
    subprocess.run(['say','-v','Samantha','-r','185','-o',str(path),'--data-format=LEI16@16000',text],check=True)
    parts[name],rate=sf.read(path,dtype='float32');assert rate==16000
rows=json.loads((AUDIO/'native-pilot.json').read_text())
for name,audio,text in [
    ('terminal-contiguous',parts['contiguous'],'Please keep the backup. Thank you.'),
    ('terminal-paused',np.concatenate([parts['prefix'],np.zeros(32000),parts['thanks']]),'Please keep the backup. Thank you.'),
    ('terminal-unspoken',np.concatenate([parts['prefix'],np.zeros(32000)]),'Please keep the backup.'),
]:
    path=AUDIO/(name+'.wav');sf.write(path,audio,16000,subtype='PCM_16')
    rows.append(dict(name=name,path=path.name,reference=text,source='macOS say Samantha 185 wpm, controlled silence',category='terminal-control',duration=len(audio)/16000,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
(AUDIO/'pipeline-manifest.json').write_text(json.dumps(rows,indent=2)+'\n')
print(len(rows),'pipeline cases')
