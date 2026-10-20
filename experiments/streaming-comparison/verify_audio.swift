import AVFoundation
import Foundation

struct Fixture: Decodable {
    let name: String
    let path: String
    let source_path: String
    let category: String
}

@main
struct VerifyAudio {
    static func main() throws {
        let manifest = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: manifest))
        for fixture in fixtures {
            let source = try load(fixture.category == "quiet" ? fixture.path : fixture.source_path)
            let prepared = try load(fixture.path)
            let trimmed = AudioSignalAnalysis.trimmingTrailingSilence(from: source, sampleRate: 16000)
            precondition(trimmed == prepared, "Audio mismatch: \(fixture.name)")
            precondition(AudioSignalAnalysis.analyze(samples: prepared)
                .hasSustainedSpeechLikeAudio(sampleRate: 16000), fixture.name)
        }
        print("Verified identical PCM, production trimming, and production speech gate for \(fixtures.count) recordings.")
    }

    static func load(_ path: String) throws -> [Float] {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        precondition(file.processingFormat.sampleRate == 16000 && file.processingFormat.channelCount == 1)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                     frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}
