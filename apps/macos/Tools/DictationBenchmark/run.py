#!/usr/bin/env python3
"""Build an isolated CLI from production services; never launch or configure the app."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
MACOS = HERE.parents[1]
STAGE = MACOS / ".build/dictation-benchmark-package"


def run(*args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


def stage_package(fluid_audio=None, mlx_audio=None):
    sources = STAGE / "Sources/DictationBenchmark"
    sources.mkdir(parents=True, exist_ok=True)
    for generated in sources.glob("*.swift"):
        generated.unlink()
    core = STAGE / "Sources/ShoutOutCore"
    if not core.exists():
        core.symlink_to(MACOS / "Sources/Core", target_is_directory=True)
    services = [
        "LanguagePassService", "TranscriptionService", "TranscriptionBackend",
        "TranscriptionModelOption", "WhisperKitTranscriptionEngine",
        "AppleSpeechTranscriptionEngine", "AppleDictationTranscriptionEngine",
        "ParakeetTranscriptionEngine",
        "SpeechAuthorization", "AudioConverterInputProvider", "AudioRecorder",
    ]
    hashes = {}
    for name in services:
        source = MACOS / f"Sources/Services/{name}.swift"
        shutil.copy2(source, sources / source.name)
        hashes[name] = hashlib.sha256(source.read_bytes()).hexdigest()
    for source in sorted((MACOS / "Sources/Core").glob("*.swift")):
        hashes["Core/" + source.name] = hashlib.sha256(source.read_bytes()).hexdigest()
    hashes["Package.resolved"] = hashlib.sha256((MACOS / "Package.resolved").read_bytes()).hexdigest()
    # Isolate tokenizer storage from Documents (which may be cloud-backed).
    # Compute placement is the explicit ASR experiment; decoding options are unchanged.
    engine = sources / "WhisperKitTranscriptionEngine.swift"
    text = engine.read_text()
    needle = "            modelFolder: modelFolder.path,\n"
    assert text.count(needle) == 1
    engine.write_text(text.replace(needle, needle +
        '            tokenizerFolder: URL(fileURLWithPath: ProcessInfo.processInfo.environment["BENCH_TOKENIZERS"]!),\n'
        '            computeOptions: BenchmarkConfiguration.computeOptions,\n'))
    language = sources / "LanguagePassService.swift"
    text = language.read_text()
    text = text.replace('id: modelID,\n                extraEOSTokens:',
        'directory: BenchmarkLanguageConfiguration.modelDirectory(modelID),\n                extraEOSTokens:')
    text = text.replace('instructions: LanguagePassPrompt.systemInstructions(for: style)',
        'instructions: BenchmarkLanguageConfiguration.instructions(for: style)')
    needle = '                topP: 1.0\n            )\n'
    assert text.count(needle) == 2
    text = text.replace(needle, '                topP: 1.0\n            ),\n'
        '            additionalContext: BenchmarkLanguageConfiguration.context\n')
    language.write_text(text)
    shutil.copy2(HERE / "ModelConfiguration.swift", sources / "ModelConfiguration.swift")
    shutil.copy2(HERE / "PythonASREngine.swift", sources / "PythonASREngine.swift")
    service = sources / "TranscriptionService.swift"
    text = service.read_text()
    root_needle = '    static let modelsDirectory: URL = {\n'
    assert text.count(root_needle) == 1
    text = text.replace(root_needle, root_needle +
        '        if let path = ProcessInfo.processInfo.environment["BENCH_MODEL_ROOT"] {\n'
        '            return URL(fileURLWithPath: path)\n'
        '        }\n')
    needle = '            return WhisperKitTranscriptionEngine('
    assert text.count(needle) == 1
    service.write_text(text.replace(needle,
        '            if ProcessInfo.processInfo.environment["BENCH_ASR"] == "python" {\n'
        '                return BenchmarkPythonASREngine()\n'
        '            }\n' + needle))
    if fluid_audio:
        shutil.copy2(HERE / "ParakeetEngine.swift", sources / "ParakeetEngine.swift")
        service = sources / "TranscriptionService.swift"
        text = service.read_text()
        needle = '            return WhisperKitTranscriptionEngine('
        assert text.count(needle) == 1
        service.write_text(text.replace(needle,
            '            if ProcessInfo.processInfo.environment["BENCH_ASR"] == "parakeet" {\n'
            '                return BenchmarkParakeetEngine()\n'
            '            }\n' + needle))
        hashes["FluidAudioRevision"] = subprocess.check_output(
            ["git", "-C", str(fluid_audio), "rev-parse", "HEAD"], text=True).strip()
    if mlx_audio:
        shutil.copy2(HERE / "SwiftParakeetEngine.swift", sources / "SwiftParakeetEngine.swift")
        text = service.read_text()
        needle = '            return WhisperKitTranscriptionEngine('
        assert text.count(needle) == 1
        service.write_text(text.replace(needle,
            '            if ProcessInfo.processInfo.environment["BENCH_ASR"] == "swift-parakeet" {\n'
            '                return BenchmarkSwiftParakeetEngine()\n'
            '            }\n' + needle))
        hashes["MLXAudioRevision"] = subprocess.check_output(
            ["git", "-C", str(mlx_audio), "rev-parse", "HEAD"], text=True).strip()
    shutil.copy2(HERE / "main.swift", sources / "BenchmarkMain.swift")
    app_delegate = (MACOS / "Sources/AppDelegate.swift").read_text()
    defaults = app_delegate.split("enum Defaults {", 1)[1].split("\n}", 1)[0]
    (sources / "Support.swift").write_text(
        'import Foundation\n@preconcurrency import WhisperKit\n'
        '@MainActor enum BenchmarkConfiguration {\n'
        ' static var profile = "default"\n'
        ' static var computeOptions: ModelComputeOptions {\n'
        '  ModelComputeOptions(audioEncoderCompute: profile.contains("encoder") ? .cpuAndGPU : .cpuAndNeuralEngine,\n'
        '   textDecoderCompute: profile.contains("decoder") ? .cpuAndGPU : .cpuAndNeuralEngine)\n'
        ' }\n}\n'
        'enum Defaults {' + defaults + '\n}\n'
        '// Keep benchmark diagnostics out of the installed app runtime log.\n'
        'enum RuntimeLog { static func write(_ message: String) {\n'
        ' if message.contains("load") || message.contains("model ready") || message.contains("verification") {\n'
        '  try? FileHandle.standardError.write(contentsOf: Data((message + "\\n").utf8))\n'
        ' }\n} }\n'
    )
    smoke = (MACOS / "Tools/LanguagePassSmoke/main.swift").read_text()
    corpus = smoke.split("    static func main()", 1)[0]
    corpus = corpus.replace("@main\n", "").replace("struct LanguagePassSmoke", "struct SmokeCorpus")
    (sources / "SmokeCorpus.swift").write_text(corpus + "}\n")
    original = (MACOS / "Package.swift").read_text()
    manifest = original.split("    targets: [", 1)[0] + '''    targets: [
        .target(name: "ShoutOutCore"),
        .executableTarget(name: "DictationBenchmark", dependencies: [
            "ShoutOutCore",
            .product(name: "WhisperKit", package: "WhisperKit"),
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            .product(name: "Hub", package: "swift-transformers"),
            .product(name: "Tokenizers", package: "swift-transformers")
        ])
    ]
)
'''
    if fluid_audio:
        manifest = manifest.replace('    dependencies: [',
            '    dependencies: [\n        .package(path: ' + json.dumps(str(fluid_audio.resolve())) + '),', 1)
        manifest = manifest.replace('            "ShoutOutCore",',
            '            "ShoutOutCore",\n            .product(name: "FluidAudio", package: ' +
            json.dumps(fluid_audio.name) + '),')
    if mlx_audio:
        manifest = re.sub(r'        \.package\(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "[^"]+"\),\n', '', manifest)
        manifest = manifest.replace('    dependencies: [',
            '    dependencies: [\n        .package(path: ' + json.dumps(str(mlx_audio.resolve())) + '),', 1)
        manifest = manifest.replace('            "ShoutOutCore",',
            '            "ShoutOutCore",\n            .product(name: "MLXAudioSTT", package: ' +
            json.dumps(mlx_audio.name) + '),')
    else:
        manifest = manifest.replace('            "ShoutOutCore",',
            '            "ShoutOutCore",\n            .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),')
    (STAGE / "Package.swift").write_text(manifest)
    shutil.copy2(MACOS / "Package.resolved", STAGE / "Package.resolved")
    for source in sorted(sources.glob("*.swift")):
        hashes["Staged/" + source.name] = hashlib.sha256(source.read_bytes()).hexdigest()
    for source in sorted(HERE.glob("*")):
        if source.is_file():
            hashes["Harness/" + source.name] = hashlib.sha256(source.read_bytes()).hexdigest()
    (STAGE / "source-hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--audio-manifest", type=Path)
    parser.add_argument("--repetitions", type=int, default=5)
    parser.add_argument("--cache-mib", default="0,2,8,32")
    parser.add_argument("--compute-profiles", default="default")
    parser.add_argument("--audio-only", action="store_true")
    parser.add_argument("--model", default="large-v3-v20240930_turbo_632MB")
    parser.add_argument("--model-root", type=Path)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--reverse-odd-rounds", action="store_true")
    parser.add_argument("--measure-first-pass", action="store_true")
    parser.add_argument("--pipeline-style", choices=["standard", "casual", "formal"])
    parser.add_argument("--lm-model", default="mlx-community/Llama-3.2-1B-Instruct-4bit")
    parser.add_argument("--lm-directory", type=Path)
    parser.add_argument("--lm-inputs", type=Path, help="Additional frozen inputs; skips ASR when used alone")
    parser.add_argument("--fluid-audio", type=Path, help="Pinned local FluidAudio checkout")
    parser.add_argument("--mlx-audio", type=Path, help="Pinned local MLX Audio Swift checkout")
    parser.add_argument("--asr", choices=["whisper", "parakeet", "python", "swift-parakeet", "production-parakeet"], default="whisper")
    parser.add_argument("--parakeet-encoder", choices=["int8", "int8-v2"], default="int8")
    parser.add_argument("--parakeet-version", choices=["v2", "v3"], default="v3")
    parser.add_argument("--python-model", choices=["parakeet-1.1b", "parakeet-1.1b-nemo-mel", "qwen-asr-1.7b", "canary-1b", "canary-1b-chunked"])
    args = parser.parse_args()
    if args.asr == "python" and not args.python_model:
        parser.error("--asr python requires --python-model")
    if args.asr == "swift-parakeet":
        if not args.skip_build and not args.mlx_audio:
            parser.error("Swift Parakeet builds require --mlx-audio")
        if args.skip_build and "MLXAudioRevision" not in json.loads((STAGE / "source-hashes.json").read_text()):
            parser.error("Rebuild with --mlx-audio before running Swift Parakeet")
    if args.repetitions < 1:
        parser.error("--repetitions must be positive")
    profiles = args.compute_profiles.split(",")
    if any(profile not in {"default", "encoder-gpu", "decoder-gpu", "encoder-decoder-gpu"} for profile in profiles):
        parser.error("unknown compute profile")
    try:
        if not all(int(value) >= 0 for value in args.cache_mib.split(",")):
            raise ValueError()
    except ValueError:
        parser.error("--cache-mib must contain nonnegative integer MiB limits")
    if args.audio_only and not args.audio_manifest:
        parser.error("--audio-only requires --audio-manifest")
    if args.pipeline_style and (args.audio_only or not args.audio_manifest):
        parser.error("--pipeline-style requires --audio-manifest and cannot use --audio-only")
    if args.asr != "whisper" and profiles != ["default"]:
        parser.error("Whisper compute profiles only apply to Whisper")
    if args.asr == "parakeet":
        if not args.skip_build and not args.fluid_audio:
            parser.error("Parakeet builds require --fluid-audio pointing to a pinned checkout")
        if args.skip_build:
            hashes = json.loads((STAGE / "source-hashes.json").read_text())
            if "FluidAudioRevision" not in hashes:
                parser.error("Rebuild with --fluid-audio before running Parakeet")
    if not args.skip_build:
        stage_package(args.fluid_audio, args.mlx_audio)
        run("swift", "build", "-c", "release", "--package-path", str(STAGE),
            "--scratch-path", str(MACOS / ".build"), "--product", "DictationBenchmark")
    binary = MACOS / ".build/release/DictationBenchmark"
    if not (binary.parent / "mlx.metallib").exists():
        raise SystemExit("Run scripts/run-language-pass-smoke.sh first to build the Metal runtime.")
    env = dict(os.environ, BENCH_OUTPUT=str(args.output.resolve()),
               BENCH_REPETITIONS=str(args.repetitions), BENCH_CACHE_MIB=args.cache_mib,
               BENCH_REVERSE_ODD_ROUNDS="1" if args.reverse_odd_rounds else "0",
               BENCH_MEASURE_FIRST_PASS="1" if args.measure_first_pass else "0",
               BENCH_PIPELINE_STYLE=args.pipeline_style or "",
               BENCH_COMPUTE_PROFILES=args.compute_profiles,
               BENCH_AUDIO_ONLY="1" if args.audio_only else "0", BENCH_MODEL_ID=args.model,
               BENCH_LM_MODEL=args.lm_model, BENCH_ASR=args.asr,
               BENCH_PARAKEET_ENCODER=args.parakeet_encoder,
               BENCH_PARAKEET_VERSION=args.parakeet_version,
               BENCH_PYTHON_MODEL=args.python_model or "",
               BENCH_SWIFT_PARAKEET_DIRECTORY=str(MACOS / ".build/large-asr-models/parakeet-1.1b"),
               BENCH_PYTHON=str(MACOS / ".build/asr-python-env/bin/python"),
               BENCH_PYTHON_WORKER=str(HERE / "python-asr-worker.py"),
               BENCH_PYTHON_METRICS=str(args.output.resolve().with_suffix(".worker.jsonl")),
               BENCH_PARAKEET_CACHE=str(MACOS / f".build/parakeet-tdt-0.6b-{args.parakeet_version}"),
               BENCH_TOKENIZERS=str(MACOS / ".build/benchmark-tokenizers"))
    if args.lm_directory:
        env["BENCH_LM_DIRECTORY"] = str(args.lm_directory.resolve())
    if args.model_root:
        env["BENCH_MODEL_ROOT"] = str(args.model_root.resolve())
    if args.lm_inputs:
        env["BENCH_LM_INPUTS"] = str(args.lm_inputs.resolve())
    if args.audio_manifest:
        env["BENCH_AUDIO_MANIFEST"] = str(args.audio_manifest.resolve())
    hashes = json.loads((STAGE / "source-hashes.json").read_text())
    resolved = STAGE / "Package.resolved"
    hashes["Resolved/Package.resolved"] = hashlib.sha256(resolved.read_bytes()).hexdigest()
    args.output.with_suffix(".dependencies.json").write_bytes(resolved.read_bytes())
    for name in ["run.py", "python-asr-worker.py", "large-asr-requirements.txt"]:
        hashes["RuntimeHarness/" + name] = hashlib.sha256((HERE / name).read_bytes()).hexdigest()
    run(str(binary), env=env)
    args.output.with_suffix(".sources.json").write_text(json.dumps(hashes, indent=2) + "\n")


if __name__ == "__main__":
    main()
