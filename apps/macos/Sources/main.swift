import AppKit
import ShoutOutCore

if CommandLine.arguments.dropFirst().first == "--cli" {
    Task { @MainActor in
        do {
            try await AppCommandLine.run(arguments: Array(CommandLine.arguments.dropFirst(2)))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("ShoutOut CLI: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    RunLoop.main.run()
    exit(0)
}

if let manifest = ProcessInfo.processInfo.environment["SHOUTOUT_REPLAY_MANIFEST"] {
    Task { @MainActor in
        do {
            try await DictationReplay.run(manifest: URL(fileURLWithPath: manifest))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Replay failed: \(error)\n".utf8))
            exit(1)
        }
    }
    RunLoop.main.run()
    exit(0)
}

SettingsMigration.removeRetiredOverrides(from: .standard)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
