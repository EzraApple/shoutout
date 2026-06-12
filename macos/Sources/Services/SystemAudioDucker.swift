import Foundation

@MainActor
final class SystemAudioDucker {
    private var savedVolume: Int?
    private var isDucking = false

    func beginDuckingIfEnabled() {
        guard UserDefaults.standard.bool(forKey: Defaults.dimSystemAudio), !isDucking else {
            return
        }
        guard let currentVolume = readOutputVolume() else {
            return
        }

        savedVolume = currentVolume
        isDucking = true

        let duckedVolume = min(currentVolume, 25)
        guard duckedVolume < currentVolume else {
            return
        }
        setOutputVolume(duckedVolume)
    }

    func endDucking() {
        guard isDucking else {
            return
        }

        if let savedVolume {
            setOutputVolume(savedVolume)
        }
        self.savedVolume = nil
        isDucking = false
    }

    private func readOutputVolume() -> Int? {
        let output = runAppleScript("output volume of (get volume settings)")
        return output.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func setOutputVolume(_ volume: Int) {
        _ = runAppleScript("set volume output volume \(max(0, min(volume, 100)))")
    }

    private func runAppleScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: output, encoding: .utf8)
    }
}
