"""Bound hardware checks and restore the original system input even after a native hang."""
import os
import pathlib
import subprocess
import sys

output = pathlib.Path(sys.argv[1])
control = output / "AudioDeviceControl"
original = subprocess.check_output([str(control)], text=True).strip()
code = 1
try:
    with (output / "results.jsonl").open("w") as results, (output / "stderr.log").open("w") as errors:
        process = subprocess.Popen([str(output / "VerifyProductionRecorder")], stdout=results, stderr=errors)
        try:
            code = process.wait(timeout=int(os.environ.get("VERIFY_TIMEOUT_SECONDS", "45")))
        except subprocess.TimeoutExpired:
            subprocess.run(["/usr/bin/sample", str(process.pid), "2", "-file", str(output / "hang.sample.txt")],
                           stdout=subprocess.DEVNULL, stderr=errors, timeout=10)
            subprocess.run([str(control), original], stdout=subprocess.DEVNULL, check=True, timeout=5)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            print("Hardware verification timed out; input restored and stack saved.", file=sys.stderr)
            code = 124
finally:
    current = subprocess.check_output([str(control)], text=True).strip()
    if current != original:
        subprocess.run([str(control), original], check=True, stdout=subprocess.DEVNULL, timeout=5)
sys.exit(code)
