import Foundation

@MainActor
enum AppCommandLine {
    static func run(arguments: [String]) async throws {
        guard let command = arguments.first, command != "help", command != "--help" else {
            print("""
            ShoutOut headless commands:
              --cli status
              --cli settings get [streaming|cleanup|style|shortcut|indicator|color]
              --cli settings set KEY VALUE
              --cli models prepare
              --cli transcribe /absolute/mono-16k.wav
              --cli replay /absolute/manifest.json --output /absolute/results.json [--paced]
              --cli serve

            Settings: streaming/cleanup on|off; style normal|casual|formal;
            indicator crab|classic|glass; shortcut/color accept the app's stored IDs.
            Commands use the running app when available. Otherwise settings persist
            for its next launch and audio commands run without windows or text insertion.
            serve hosts the same commands headlessly; use it while the GUI app is closed.
            """)
            return
        }
        if command == "replay" {
            guard arguments.count >= 4, let outputIndex = arguments.firstIndex(of: "--output"),
                arguments.indices.contains(outputIndex + 1) else {
                throw invalid("Use replay MANIFEST --output RESULTS [--paced].")
            }
            setenv("SHOUTOUT_REPLAY_OUTPUT", arguments[outputIndex + 1], 1)
            setenv("SHOUTOUT_REPLAY_MANIFEST", arguments[1], 1)
            setenv("SHOUTOUT_REPLAY_PACING", arguments.contains("--paced") ? "1" : "0", 1)
            let defaults = controlDefaults()
            setenv("SHOUTOUT_REPLAY_ENGINE", defaults.bool(forKey: "streamingTranscriptionEnabled") ? "hexStreaming" : "parakeet", 1)
            try await DictationReplay.run(manifest: URL(fileURLWithPath: arguments[1]), profile: defaults,
                                         modelsDirectory: modelsDirectory, languageModelsDirectory: languageModelsDirectory)
            return
        }
        let router = makeRouter()
        let path = ProcessInfo.processInfo.environment["SHOUTOUT_CONTROL_SOCKET"]
            .map { URL(fileURLWithPath: $0) } ?? AppControlSocket.defaultPath
        let canUseSocket = ProcessInfo.processInfo.environment["SHOUTOUT_CLI_SUITE"] == nil
            || ProcessInfo.processInfo.environment["SHOUTOUT_CONTROL_SOCKET"] != nil
        if command == "serve" {
            guard canUseSocket else { throw invalid("Set SHOUTOUT_CONTROL_SOCKET for an isolated headless host.") }
            let server = AppControlSocket(path: path) { request in await router.handle(request) }
            try server.start()
            defer { server.stop() }
            try printResponse(AppControlResponse(ok: true, message: "Headless control ready", values: ["socket": path.path], text: nil, rawText: nil))
            while !Task.isCancelled { try await Task.sleep(for: .seconds(3600)) }
            return
        }
        let request = try parse(arguments)
        let response: AppControlResponse
        // A private socket is present only while a live app or headless host owns it.
        if canUseSocket && FileManager.default.fileExists(atPath: path.path) {
            do {
                response = try await AppControlSocket.request(request, at: path)
            } catch {
                // A socket left by an exited process must not prevent offline commands.
                if AppControlSocket.isConnectionUnavailable(error) {
                    response = await router.handle(request)
                } else { throw error }
            }
        } else {
            response = await router.handle(request)
        }
        try printResponse(response)
        guard response.ok else { throw invalid(response.message ?? "Command failed.") }
    }

    private static func parse(_ arguments: [String]) throws -> AppControlRequest {
        switch arguments.first {
        case "status" where arguments.count == 1:
            return AppControlRequest(command: "status", key: nil, value: nil, path: nil)
        case "settings" where arguments.count >= 2:
            if arguments[1] == "get", arguments.count <= 3 {
                return AppControlRequest(command: "settings.get", key: arguments.count == 3 ? arguments[2] : nil, value: nil, path: nil)
            }
            if arguments[1] == "set", arguments.count == 4 {
                return AppControlRequest(command: "settings.set", key: arguments[2], value: arguments[3], path: nil)
            }
        case "models" where arguments == ["models", "prepare"]:
            return AppControlRequest(command: "models.prepare", key: nil, value: nil, path: nil)
        case "transcribe" where arguments.count == 2:
            return AppControlRequest(command: "transcribe", key: nil, value: nil, path: URL(fileURLWithPath: arguments[1]).path)
        default: break
        }
        throw invalid("Unknown command. Use --cli help.")
    }

    private static func makeRouter() -> AppControlRouter {
        AppControlRouter(defaults: controlDefaults(), modelsDirectory: modelsDirectory,
                         languageModelsDirectory: languageModelsDirectory)
    }

    private static var modelsDirectory: URL {
        ProcessInfo.processInfo.environment["SHOUTOUT_CLI_MODELS_DIRECTORY"]
            .map { URL(fileURLWithPath: $0) } ?? TranscriptionService.modelsDirectory
    }

    private static var languageModelsDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["SHOUTOUT_CLI_LANGUAGE_MODELS_DIRECTORY"] {
            return URL(fileURLWithPath: path)
        }
        if ProcessInfo.processInfo.environment["SHOUTOUT_CLI_MODELS_DIRECTORY"] != nil {
            return modelsDirectory.appendingPathComponent("LanguageModels")
        }
        return LanguagePassService.modelsDirectory
    }

    private static func controlDefaults() -> UserDefaults {
        if let suite = ProcessInfo.processInfo.environment["SHOUTOUT_CLI_SUITE"],
            let defaults = UserDefaults(suiteName: suite) {
            defaults.register(defaults: [Defaults.languagePassModelCleanupVersion: 1])
            return defaults
        }
        return .standard
    }

    private static func printResponse(_ response: AppControlResponse) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(response)
        try FileHandle.standardOutput.write(contentsOf: data + Data([0x0A]))
    }

    private static func invalid(_ message: String) -> NSError {
        NSError(domain: "ShoutOut.CLI", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
