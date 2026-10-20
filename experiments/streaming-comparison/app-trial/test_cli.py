#!/usr/bin/env python3
"""Exercise the packaged app through CLI/IPC without opening a window."""
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
APP_BUNDLE = Path(os.environ.get('SHOUTOUT_TEST_APP', str(ROOT / 'apps/macos/dist/ShoutOut.app')))
BINARY = APP_BUNDLE / 'Contents/MacOS/ShoutOut'


def main():
    suite = 'ShoutOut.CLI.Smoke.' + uuid.uuid4().hex
    directory = Path(tempfile.mkdtemp(prefix='so-cli-', dir='/tmp'))
    socket = directory / 'app.sock'
    environment = dict(os.environ, SHOUTOUT_CLI_SUITE=suite,
                       SHOUTOUT_CONTROL_SOCKET=str(socket))
    process = None

    def command(*arguments, success=True, env=environment):
        result = subprocess.run([str(BINARY), '--cli', *arguments], env=env,
                                capture_output=True, text=True, timeout=180)
        assert (result.returncode == 0) == success, (arguments, result.stderr[-3000:])
        response = json.loads(result.stdout)
        assert response['ok'] == success, response
        return response

    try:
        initial = command('status')
        assert initial['values']['engine'] == 'hexStreaming', initial
        assert initial['values']['streaming'] == 'true', initial
        assert command('settings', 'set', 'streaming', 'on')['values']['engine'] == 'hexStreaming'
        # A private suite without a socket must stay offline, even if the GUI owns its default socket.
        private_environment = dict(environment)
        private_environment.pop('SHOUTOUT_CONTROL_SOCKET')
        assert command('status', env=private_environment)['values']['streaming'] == 'true'
        assert command('settings', 'set', 'streaming', 'off')['values']['engine'] == 'parakeet'
        assert command('status')['values']['streaming'] == 'false'
        command('settings', 'set', 'style', 'normal')
        command('settings', 'set', 'style', 'invalid', success=False)
        assert command('settings', 'get', 'style')['values']['style'] == 'standard'
        command('settings', 'set', 'cleanup', 'on')
        for indicator, stored in [('crab', 'crab'), ('classic', 'capsule'), ('glass', 'glass')]:
            assert command('settings', 'set', 'indicator', indicator)['values']['indicator'] == stored
        assert not socket.exists()

        with (directory / 'host.log').open('w') as log:
            process = subprocess.Popen([str(BINARY), '--cli', 'serve'], env=environment,
                                       stdout=log, stderr=log)
            for _ in range(100):
                assert process.poll() is None, (directory / 'host.log').read_text()[-3000:]
                if socket.exists():
                    break
                time.sleep(.05)
            assert socket.exists(), 'Headless host did not bind its socket.'
            assert stat.S_IMODE(socket.stat().st_mode) == 0o600
            assert stat.S_IMODE(directory.stat().st_mode) == 0o700
            assert command('status')['values']['engine'] == 'parakeet'
            speech = HERE / 'fixtures/01-save-file.wav'
            silence = HERE / 'fixtures/control-silence.wav'
            engines = [('hexStreaming', 'on')]
            if os.environ.get('SHOUTOUT_TEST_LEGACY_ENGINES') == '1':
                engines.insert(0, ('parakeet', 'off'))
            for engine, enabled in engines:
                command('settings', 'set', 'streaming', enabled)
                ready = command('models', 'prepare')
                assert ready['values']['modelState'] == 'ready', ready
                assert ready['values']['engine'] == engine, ready
                transcript = command('transcribe', str(speech))
                assert transcript['values']['engine'] == engine, transcript
                assert 'save' in transcript['text'].lower() and 'notes' in transcript['text'].lower(), transcript
                assert command('transcribe', str(silence))['values']['status'] == 'silent'
                replay_manifest = directory / 'replay.json'
                replay_manifest.write_text(json.dumps([dict(name='cli-smoke', path=str(speech),
                    reference='Save the file as notes dot text.')]))
                output = directory / f'{engine}-replay.json'
                # Replay runs in its own headless process and retains the private profile.
                replay = subprocess.run([str(BINARY), '--cli', 'replay', str(replay_manifest),
                    '--output', str(output), '--paced'], env=environment,
                    capture_output=True, text=True, timeout=180)
                assert replay.returncode == 0, replay.stderr[-3000:]
                rows = json.loads(output.read_text())
                assert len(rows) == 1 and rows[0]['status'] == 'completed', rows
                assert rows[0]['paced'] and rows[0]['rawText'], rows
                print(engine, 'settings, model preparation, file transcription, silence and paced replay passed', flush=True)
            assert command('status')['values']['engine'] == 'hexStreaming'
        print('Isolated offline settings and private IPC passed; no GUI was launched.', flush=True)
    finally:
        if process is not None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
        subprocess.run(['/usr/bin/defaults', 'delete', suite], capture_output=True)
        shutil.rmtree(directory)


if __name__ == '__main__':
    main()
