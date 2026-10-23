"""Add timing probes to a build-only copy of the production recorder."""
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
replacements = {
    'let engine = AVAudioEngine()':
        'let engine = BenchTrace.measure("engineCreateMs") { AVAudioEngine() }',
    'let inputNode = engine.inputNode':
        'let inputNode = BenchTrace.measure("inputNodeMs") { engine.inputNode }',
    'let inputFormat = inputNode.outputFormat(forBus: 0)':
        'let inputFormat = BenchTrace.measure("inputFormatMs") { inputNode.outputFormat(forBus: 0) }',
    'let targetFormat = AVAudioFormat(\n':
        'let targetFormat = BenchTrace.measure("targetFormatMs", { AVAudioFormat(\n',
    'interleaved: false\n            )':
        'interleaved: false\n            ) })',
    'let converter = AVAudioConverter(from: inputFormat, to: targetFormat)':
        'let converter = BenchTrace.measure("converterCreateMs", { AVAudioConverter(from: inputFormat, to: targetFormat) })',
    '        Self.installAudioTap(\n':
        '        BenchTrace.measure("tapInstallMs") { Self.installAudioTap(\n',
    '            collector: collector\n        )':
        '            collector: collector\n        ) }',
    '        engine.prepare()':
        '        BenchTrace.measure("prepareMs") { engine.prepare() }',
    '            try engine.start()':
        '            try BenchTrace.measure("engineStartMs") { try engine.start() }',
    '        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) {\n            buffer, _ in':
        '        let probe = BenchTrace.probe\n        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) {\n            buffer, time in\n            probe?.observeRaw(buffer, time: time)',
    '            collector.append(samples, level: min(level * 5, 1.0))':
        '            collector.append(samples, level: min(level * 5, 1.0))\n            probe?.observeConverted(samples.count)',
    '            guard frameCount > 0 else { return }':
        '            guard frameCount > 0 else { probe?.observeError(); return }',
    '                    pcmFormat: targetFormat, frameCapacity: frameCount)\n            else { return }':
        '                    pcmFormat: targetFormat, frameCapacity: frameCount)\n            else { probe?.observeError(); return }',
    '                let channelData = convertedBuffer.floatChannelData\n            else { return }':
        '                let channelData = convertedBuffer.floatChannelData\n            else { probe?.observeError(); return }',
}
for original, replacement in replacements.items():
    assert source.count(original) == 1, repr(original)
    source = source.replace(original, replacement)
pathlib.Path(sys.argv[2]).write_text(source)
