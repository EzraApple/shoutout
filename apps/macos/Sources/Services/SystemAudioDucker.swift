import Foundation

@MainActor
final class SystemAudioDucker {
    private enum DefaultsKey {
        static let savedVolume = "audioDucker.savedOutputVolume"
    }

    private var savedVolume: Int?
    private var isDucking = false
    private var duckingGeneration = 0
    private var duckingTask: Task<Void, Never>?

    init() {
        restorePersistedVolumeIfNeeded()
    }

    func beginDuckingIfEnabled() {
        guard UserDefaults.standard.bool(forKey: Defaults.dimSystemAudio), !isDucking else {
            return
        }

        duckingGeneration += 1
        let generation = duckingGeneration
        isDucking = true
        duckingTask?.cancel()

        duckingTask = Task { [weak self] in
            guard let currentVolume = await Self.readOutputVolume() else {
                self?.clearDuckingState(generation: generation)
                return
            }

            guard self?.storeSavedVolume(currentVolume, generation: generation) == true else {
                return
            }

            let duckedVolume = min(currentVolume, 25)
            guard duckedVolume < currentVolume else {
                return
            }

            let didSetVolume = await Self.setOutputVolume(duckedVolume)
            if !didSetVolume {
                self?.clearDuckingState(generation: generation)
            }
        }
    }

    func endDucking() {
        guard isDucking else {
            return
        }

        duckingGeneration += 1
        duckingTask?.cancel()
        duckingTask = nil

        if let savedVolume {
            Task {
                _ = await Self.setOutputVolume(savedVolume)
            }
        }
        self.savedVolume = nil
        isDucking = false
        UserDefaults.standard.removeObject(forKey: DefaultsKey.savedVolume)
    }

    private func storeSavedVolume(_ volume: Int, generation: Int) -> Bool {
        guard generation == duckingGeneration, isDucking else {
            return false
        }

        savedVolume = volume
        UserDefaults.standard.set(volume, forKey: DefaultsKey.savedVolume)
        return true
    }

    private func clearDuckingState(generation: Int) {
        guard generation == duckingGeneration else {
            return
        }

        savedVolume = nil
        isDucking = false
        duckingTask = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.savedVolume)
    }

    private func restorePersistedVolumeIfNeeded() {
        guard let savedVolume = UserDefaults.standard.object(forKey: DefaultsKey.savedVolume) as? Int else {
            return
        }

        UserDefaults.standard.removeObject(forKey: DefaultsKey.savedVolume)
        Task {
            guard let currentVolume = await Self.readOutputVolume(),
                currentVolume <= 25
            else {
                return
            }

            _ = await Self.setOutputVolume(savedVolume)
            RuntimeLog.write("audio ducking restored persisted volume=\(savedVolume)")
        }
    }

    private nonisolated static func readOutputVolume() async -> Int? {
        let output = await runAppleScript("output volume of (get volume settings)")
        return output.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    @discardableResult
    private nonisolated static func setOutputVolume(_ volume: Int) async -> Bool {
        let outputVolume = max(0, min(volume, 100))
        return await runAppleScript("set volume output volume \(outputVolume)") != nil
    }

    private nonisolated static func runAppleScript(
        _ source: String,
        timeoutSeconds: TimeInterval = 1.5
    ) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", source]

                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = Pipe()

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let deadline = Date().addingTimeInterval(timeoutSeconds)
                while process.isRunning, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.02)
                }

                guard !process.isRunning else {
                    process.terminate()
                    RuntimeLog.write("audio ducking osascript timed out")
                    continuation.resume(returning: nil)
                    return
                }

                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: output, encoding: .utf8))
            }
        }
    }
}
