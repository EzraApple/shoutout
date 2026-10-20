#!/usr/bin/env python3
"""Fetch the fixed, standard Whisper English scoring normalizer, not an ASR model."""
import hashlib
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

REVISION = '86098128c0b4f24f0e2aa2994de830614b474227'
root = Path(__file__).resolve().parent / '.build/scoring'
package = root / 'whisper_normalizer'
package.mkdir(parents=True, exist_ok=True)
hashes = {}
for name in ['english.py', 'basic.py', 'english.json']:
    url = f'https://raw.githubusercontent.com/openai/whisper/{REVISION}/whisper/normalizers/{name}'
    data = urllib.request.urlopen(url).read()
    (package / name).write_bytes(data)
    hashes[name] = hashlib.sha256(data).hexdigest()
(package / '__init__.py').write_text('from .english import EnglishTextNormalizer\n')
license_url = f'https://raw.githubusercontent.com/openai/whisper/{REVISION}/LICENSE'
(package / 'LICENSE').write_bytes(urllib.request.urlopen(license_url).read())
subprocess.run([sys.executable, '-m', 'pip', 'install', '--disable-pip-version-check', '--quiet',
                '--target', str(root), 'regex==2024.11.6', 'more-itertools==10.5.0'], check=True)
(root / 'provenance.json').write_text(json.dumps(dict(repository='openai/whisper', revision=REVISION,
    files=hashes, dependencies={'regex': '2024.11.6', 'more-itertools': '10.5.0'}), indent=2) + '\n')
print(root)
