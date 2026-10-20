#!/usr/bin/env python3
"""Compare one pinned Hex model in batch and stream modes, without any GUI."""
import array
import base64
import hashlib
import json
import os
from pathlib import Path
import selectors
import shutil
import socket
import subprocess
import tempfile
import time
import uuid
import wave

from summarize import distance, EnglishTextNormalizer

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BUNDLE = ROOT / 'apps/macos/dist/ShoutOut.app'
APP = BUNDLE / 'Contents/MacOS/ShoutOut'
WORKER = BUNDLE / 'Contents/Helpers/HexSpeechWorker'
RESULTS = HERE / 'results/hex-modes'
METADATA = json.loads((BUNDLE / 'Contents/Resources/HexSpeechWorker/ModelMetadata.json').read_text())
MODEL = (Path.home() / 'Library/Application Support/com.ezraapple.shoutout/Models'
         / ('hex-' + METADATA['revision']) / METADATA['fileName'])


def digest(data):
    return hashlib.sha256(data).hexdigest()


def save(name, data):
    (RESULTS / name).write_text(json.dumps(data, indent=2) + '\n')


def load_fixtures():
    rows = json.loads((HERE / 'fixtures/manifest.json').read_text())['fixtures']
    for row in rows:
        path = HERE / 'fixtures' / row['path']
        assert digest(path.read_bytes()) == row['sha256'], path
        with wave.open(str(path), 'rb') as audio:
            assert (audio.getnchannels(), audio.getframerate(), audio.getsampwidth()) == (1, 16000, 2)
            samples = array.array('h', audio.readframes(audio.getnframes()))
        row['pcm'] = array.array('f', (sample / 32768 for sample in samples)).tobytes()
        assert len(row['pcm']) == row['samples'] * 4
        row['absolute_path'] = str(path)
    return rows


class NativeWorker:
    def __init__(self):
        self.log = (RESULTS / 'native.log').open('w')
        self.process = subprocess.Popen([str(WORKER), '--model', str(MODEL)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.log, text=True, bufsize=1)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        ready = self.read()
        assert ready['status'] == 'ready' and ready['streamAvailable'], ready
        assert ready['modelSha256'] == METADATA['sha256'], ready
        self.ready = ready

    def read(self):
        assert self.selector.select(timeout=120), 'Native worker timed out.'
        line = self.process.stdout.readline()
        assert line, 'Native worker exited unexpectedly.'
        response = json.loads(line)
        assert response.get('status') != 'error', response
        return response

    def request(self, operation, identity, pcm=None):
        request = dict(op=operation, id=identity)
        if pcm is not None:
            request['audio'] = base64.b64encode(pcm).decode('ascii')
        self.process.stdin.write(json.dumps(request, separators=(',', ':')) + '\n')
        self.process.stdin.flush()
        response = self.read()
        assert response['id'] == identity, response
        return response

    def transcribe(self, pcm, mode):
        identity = uuid.uuid4().hex
        if mode == 'batch':
            return self.request('transcribe', identity, pcm)
        self.request('begin', identity)
        for offset in range(0, len(pcm), 2560 * 4):
            self.request('feed', identity, pcm[offset:offset + 2560 * 4])
        response = self.request('finish', identity)
        assert response['source'] == 'stream', response
        return response

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=10)
        self.selector.close()
        self.log.close()


def run_native(fixtures):
    worker = NativeWorker()
    observations = []
    try:
        worker.transcribe(fixtures[0]['pcm'], 'batch')
        worker.transcribe(fixtures[0]['pcm'] + bytes(3200 * 4), 'stream')
        for round_index in range(2):
            rows = fixtures if round_index == 0 else list(reversed(fixtures))
            modes = ['batch', 'streamMatched', 'streamAppTail']
            if round_index:
                modes.reverse()
            for fixture in rows:
                if fixture['name'] == 'control-silence':
                    continue  # Compare speech; production speech gates reject this fixture.
                pcm = fixture['pcm']
                # Native batch pads to >=1.5 seconds then appends 200 ms of silence.
                batch_effective = pcm + bytes(max(24000 * 4 - len(pcm), 0) + 3200 * 4)
                for mode in modes:
                    supplied = pcm if mode == 'batch' else (
                        batch_effective if mode == 'streamMatched' else pcm + bytes(1280 * 4))
                    result = worker.transcribe(supplied, 'batch' if mode == 'batch' else 'stream')
                    effective = batch_effective if mode == 'batch' else supplied
                    observations.append(dict(name=fixture['name'], reference=fixture['reference'],
                        mode=mode, round=round_index, rawText=result['text'], source=result['source'],
                        wavSHA256=fixture['sha256'], suppliedSamples=len(supplied)//4,
                        effectiveSamples=len(effective)//4, effectivePCMSHA256=digest(effective)))
                    save('native.json', observations)
                print('native', round_index, fixture['name'], 'completed', flush=True)
        return observations, worker.ready
    finally:
        worker.close()


def run_app_batch(fixtures):
    suite = 'ShoutOut.HexBatch.' + uuid.uuid4().hex
    temporary = Path(tempfile.mkdtemp(prefix='so-hex-', dir='/tmp'))
    path = temporary / 'app.sock'
    environment = dict(os.environ, SHOUTOUT_CLI_SUITE=suite, SHOUTOUT_CONTROL_SOCKET=str(path))
    host = None
    observations = []

    def request(command, **arguments):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(180)
            connection.connect(str(path))
            connection.sendall((json.dumps(dict(command=command, **arguments)) + '\n').encode())
            with connection.makefile('rb') as response:
                result = json.loads(response.readline(512 * 1024))
        assert result['ok'], result
        return result

    try:
        with (RESULTS / 'app-batch.log').open('w') as log:
            host = subprocess.Popen([str(APP), '--cli', 'serve'], env=environment, stdout=log, stderr=log)
            for _ in range(200):
                assert host.poll() is None, 'Headless host exited.'
                if path.exists():
                    break
                time.sleep(.05)
            assert path.exists()
            request('settings.set', key='streaming', value='on')
            request('settings.set', key='cleanup', value='off')
            ready = request('models.prepare')
            assert ready['values']['engine'] == 'hexStreaming' and ready['values']['modelState'] == 'ready'
            request('transcribe', path=fixtures[0]['absolute_path'])
            for fixture in fixtures:
                result = request('transcribe', path=fixture['absolute_path'])
                observations.append(dict(name=fixture['name'], reference=fixture['reference'],
                    rawText=result.get('rawText', ''), status=result['values'].get('status', 'completed'),
                    wavSHA256=fixture['sha256']))
                save('app-batch.json', observations)
                print('app batch', fixture['name'], 'completed', flush=True)
        return observations
    finally:
        if host is not None:
            host.terminate()
            try:
                host.wait(timeout=10)
            except subprocess.TimeoutExpired:
                host.kill()
                host.wait(timeout=10)
        subprocess.run(['/usr/bin/defaults', 'delete', suite], capture_output=True)
        shutil.rmtree(temporary)


def summarize(fixtures, observations, app_batch):
    normalize = EnglishTextNormalizer()
    current = json.loads((HERE / 'results/parakeet-quality.json').read_text())
    app_stream = json.loads((HERE / 'results/hexStreaming-quality.json').read_text())
    panels = dict(current=current, hexBatchApp=app_batch, hexStreamApp=app_stream)
    for mode in ['batch', 'streamMatched', 'streamAppTail']:
        panels[mode] = [row for row in observations if row['round'] == 0 and row['mode'] == mode]
    scoring, per_clip = {}, {}
    for name, rows in panels.items():
        rows = [row for row in rows if row['name'] not in ['warmup-not-scored', 'control-silence']]
        assert len(rows) == 22
        errors = sum(distance(normalize(row['reference']).split(), normalize(row['rawText']).split()) for row in rows)
        words = sum(len(normalize(row['reference']).split()) for row in rows)
        scoring[name] = dict(errors=errors, words=words, wer=errors/words)
        for row in rows:
            per_clip.setdefault(row['name'], dict(reference=row['reference']))[name] = dict(
                text=row['rawText'], normalized=normalize(row['rawText']),
                errors=distance(normalize(row['reference']).split(), normalize(row['rawText']).split()))
    first = {(row['name'], row['mode']): row for row in observations if row['round'] == 0}
    repeated_changes = [dict(name=row['name'], mode=row['mode']) for row in observations
        if row['round'] == 1 and row['rawText'] != first[row['name'], row['mode']]['rawText']]
    for fixture in fixtures:
        if fixture['name'] == 'control-silence':
            continue
        batch = first[fixture['name'], 'batch']
        stream = first[fixture['name'], 'streamMatched']
        assert batch['effectivePCMSHA256'] == stream['effectivePCMSHA256']
        assert batch['effectiveSamples'] == stream['effectiveSamples']
    summary = dict(scores=scoring, perClip=per_clip, repeatedTranscriptChanges=repeated_changes,
        matchedNativeInput='Identical float32 PCM at native model input, including batch 200ms padding.',
        appComparison='Same WAVs and production trim/gates/ASR filters; cleanup disabled for batch raw-ASR audit.',
        latency='Unpaced quality test only; no new latency claim.')
    save('summary.json', summary)
    print(json.dumps(dict(scores=scoring, repeatedTranscriptChanges=repeated_changes), indent=2), flush=True)


def main():
    RESULTS.mkdir(parents=True, exist_ok=True)
    fixtures = load_fixtures()
    observations, ready = run_native(fixtures)
    app_batch = run_app_batch(fixtures)
    save('provenance.json', dict(appSHA256=digest(APP.read_bytes()), workerSHA256=digest(WORKER.read_bytes()),
        fixtureManifestSHA256=digest((HERE / 'fixtures/manifest.json').read_bytes()),
        baselineReplayBuild=json.loads((HERE / 'results/build.json').read_text()),
        metadata=METADATA, workerReady=ready, packetSamples=2560, nativeRounds=2,
        precision='float32 samples derived exactly from signed PCM16; little-endian host',
        date=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())))
    summarize(fixtures, observations, app_batch)


if __name__ == '__main__':
    main()
