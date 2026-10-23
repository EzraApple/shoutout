import Foundation
import Darwin

@MainActor
final class SystemAudioDucker {
    private enum DefaultsKey {
        static let savedVolume = "audioDucker.savedOutputVolume"
    }

    private var savedVolume: Int?
    private var isDucking = false
    private var duckingGeneration = 0
    private var volumeTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let readVolume: @Sendable () async -> Int?
    private let setVolume: @Sendable (Int) async -> Bool

    init(
        defaults: UserDefaults = .standard,
        readVolume: @escaping @Sendable () async -> Int? = { await readOutputVolume() },
        setVolume: @escaping @Sendable (Int) async -> Bool = { await setOutputVolume($0) }
    ) {
        self.defaults = defaults
        self.readVolume = readVolume
        self.setVolume = setVolume
        enqueueVolumeOperation { [self] in
            await restorePersistedVolumeIfNeeded()
        }
    }

    func beginDuckingIfEnabled() {
        guard defaults.bool(forKey: Defaults.dimSystemAudio), !isDucking else {
            return
        }

        duckingGeneration += 1
        let generation = duckingGeneration
        isDucking = true
        enqueueVolumeOperation { [self] in
            await beginDucking(generation: generation)
        }
    }

    func endDucking() {
        guard isDucking || savedVolume != nil || persistedSavedVolume != nil else {
            return
        }

        duckingGeneration += 1
        isDucking = false
        enqueueVolumeOperation { [self] in
            if let savedVolume {
                await restoreVolume(savedVolume)
            } else {
                await restorePersistedVolumeIfNeeded()
            }
        }
    }

    func waitForPendingOperations() async {
        await volumeTask?.value
    }

    private var persistedSavedVolume: Int? {
        defaults.object(forKey: DefaultsKey.savedVolume) as? Int
    }

    private func enqueueVolumeOperation(_ operation: @escaping @MainActor () async -> Void) {
        let previousTask = volumeTask
        volumeTask = Task {
            await previousTask?.value
            await operation()
        }
    }

    private func beginDucking(generation: Int) async {
        guard generation == duckingGeneration, isDucking else { return }
        await restorePersistedVolumeIfNeeded()
        guard generation == duckingGeneration, isDucking else { return }
        guard persistedSavedVolume == nil else {
            isDucking = false
            return
        }

        guard let currentVolume = await readVolume() else {
            if generation == duckingGeneration { isDucking = false }
            return
        }
        guard generation == duckingGeneration, isDucking else { return }

        let duckedVolume = min(currentVolume, 10)
        guard duckedVolume < currentVolume else { return }
        savedVolume = currentVolume
        defaults.set(currentVolume, forKey: DefaultsKey.savedVolume)
        if !(await setVolume(duckedVolume)) {
            await restoreVolume(currentVolume)
            if generation == duckingGeneration { isDucking = false }
        }
    }

    private func restoreVolume(_ volume: Int) async {
        guard await setVolume(volume) else { return }
        savedVolume = nil
        defaults.removeObject(forKey: DefaultsKey.savedVolume)
    }

    private func restorePersistedVolumeIfNeeded() async {
        guard let volume = persistedSavedVolume else { return }
        // Include the previous 25% cap when recovering an interrupted recording.
        guard let currentVolume = await readVolume() else { return }
        guard currentVolume <= 25 else {
            savedVolume = nil
            defaults.removeObject(forKey: DefaultsKey.savedVolume)
            return
        }

        if await setVolume(volume) {
            savedVolume = nil
            defaults.removeObject(forKey: DefaultsKey.savedVolume)
            RuntimeLog.write("audio ducking restored persisted volume=\(volume)")
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
                    let terminationDeadline = Date().addingTimeInterval(0.25)
                    while process.isRunning, Date() < terminationDeadline {
                        Thread.sleep(forTimeInterval: 0.02)
                    }
                    if process.isRunning {
                        Darwin.kill(process.processIdentifier, SIGKILL)
                    }
                    process.waitUntilExit()
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
