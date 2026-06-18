import Foundation

enum DiagnosticsExporter {
    struct ExportResult {
        let archiveURL: URL
        let includedCrashReportCount: Int
    }

    enum ExportError: LocalizedError {
        case zipFailed(String)

        var errorDescription: String? {
            switch self {
            case .zipFailed(let detail):
                return detail.isEmpty ? "Could not create diagnostics archive." : detail
            }
        }
    }

    @MainActor
    static func export(
        transcription: TranscriptionService,
        permissions: PermissionManager
    ) throws -> ExportResult {
        RuntimeLog.write("diagnostics export requested")
        RuntimeLog.flush()

        let fileManager = FileManager.default
        let timestamp = archiveTimestamp()
        let stagingURL = fileManager.temporaryDirectory
            .appendingPathComponent("ShoutOut-Diagnostics-\(timestamp)-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = try diagnosticsArchiveURL(timestamp: timestamp)

        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: stagingURL)
        }

        try writeReadme(to: stagingURL)
        try writeMetadata(
            to: stagingURL,
            transcription: transcription,
            permissions: permissions
        )
        try copyRuntimeLog(to: stagingURL)
        let crashReportCount = try copyRecentCrashReports(to: stagingURL)

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        try zipContents(of: stagingURL, to: archiveURL)

        RuntimeLog.write(
            "diagnostics export complete archive=\(archiveURL.path) crashReports=\(crashReportCount)"
        )
        return ExportResult(archiveURL: archiveURL, includedCrashReportCount: crashReportCount)
    }

    private static func writeReadme(to stagingURL: URL) throws {
        let text = """
        ShoutOut diagnostics bundle

        This bundle includes app metadata, the ShoutOut runtime log, and recent ShoutOut crash reports from this Mac.

        It does not include dictated text, clipboard contents, audio recordings, model files, or account credentials.
        """
        try text.write(
            to: stagingURL.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    @MainActor
    private static func writeMetadata(
        to stagingURL: URL,
        transcription: TranscriptionService,
        permissions: PermissionManager
    ) throws {
        let metadata = DiagnosticsMetadata(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            app: AppMetadata(
                bundleIdentifier: AppVersionInfo.bundleIdentifier,
                version: AppVersionInfo.version,
                build: AppVersionInfo.build,
                gitCommit: AppVersionInfo.gitCommit,
                builtAt: AppVersionInfo.builtAt
            ),
            system: SystemMetadata.current,
            transcription: TranscriptionMetadata(
                backend: transcription.selectedBackend.displayName,
                backendID: transcription.selectedBackend.rawValue,
                activeModelIdentifier: transcription.activeModelIdentifier,
                selectedModel: transcription.selectedModel,
                modelState: describeModelState(transcription.modelState),
                modelsDiskUsage: transcription.modelsDiskUsage
            ),
            permissions: PermissionMetadata(
                accessibility: permissions.hasAccessibility,
                inputMonitoring: permissions.hasInputMonitoring,
                microphone: permissions.hasMicrophone,
                speechRecognition: permissions.hasSpeechRecognition,
                status: permissions.statusText
            ),
            settings: SettingsMetadata.current,
            files: FileMetadata(
                runtimeLogPath: RuntimeLog.logURL.path,
                modelsDirectoryPath: TranscriptionService.modelsDirectory.path
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: stagingURL.appendingPathComponent("metadata.json"), options: .atomic)
    }

    private static func copyRuntimeLog(to stagingURL: URL) throws {
        let destinationURL = stagingURL.appendingPathComponent("runtime.log")
        if FileManager.default.fileExists(atPath: RuntimeLog.logURL.path) {
            try FileManager.default.copyItem(at: RuntimeLog.logURL, to: destinationURL)
            return
        }

        try "Runtime log was not present at export time.\n".write(
            to: stagingURL.appendingPathComponent("runtime-log-missing.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func copyRecentCrashReports(to stagingURL: URL) throws -> Int {
        let fileManager = FileManager.default
        let reportsURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("DiagnosticReports")

        guard fileManager.fileExists(atPath: reportsURL.path) else { return 0 }

        let reportURLs = try fileManager.contentsOfDirectory(
            at: reportsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let recentReports = reportURLs
            .filter { url in
                let name = url.lastPathComponent.lowercased()
                let ext = url.pathExtension.lowercased()
                return name.contains("shoutout")
                    && ["crash", "ips", "diag"].contains(ext)
            }
            .sorted { lhs, rhs in
                modificationDate(for: lhs) > modificationDate(for: rhs)
            }
            .prefix(8)

        guard !recentReports.isEmpty else { return 0 }

        let crashDirectoryURL = stagingURL.appendingPathComponent("crash-reports", isDirectory: true)
        try fileManager.createDirectory(at: crashDirectoryURL, withIntermediateDirectories: true)

        var copiedCount = 0
        for reportURL in recentReports {
            let destinationURL = crashDirectoryURL.appendingPathComponent(reportURL.lastPathComponent)
            try? fileManager.copyItem(at: reportURL, to: destinationURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                copiedCount += 1
            }
        }
        return copiedCount
    }

    private static func zipContents(of stagingURL: URL, to archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = stagingURL
        process.arguments = ["-qry", archiveURL.path, "."]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: errorData, encoding: .utf8) ?? ""
            throw ExportError.zipFailed(detail)
        }
    }

    private static func diagnosticsArchiveURL(timestamp: String) throws -> URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL.appendingPathComponent("ShoutOut-Diagnostics-\(timestamp).zip")
    }

    private static func archiveTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func modificationDate(for url: URL) -> Date {
        (
            try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        ) ?? .distantPast
    }

    private static func describeModelState(_ state: ModelState) -> String {
        switch state {
        case .unloaded:
            return "unloaded"
        case .downloading(let progress):
            return "downloading \(Int(progress * 100))%"
        case .loading:
            return "loading"
        case .ready:
            return "ready"
        case .error(let message):
            return "error: \(message)"
        }
    }
}

private struct DiagnosticsMetadata: Encodable {
    let generatedAt: String
    let app: AppMetadata
    let system: SystemMetadata
    let transcription: TranscriptionMetadata
    let permissions: PermissionMetadata
    let settings: SettingsMetadata
    let files: FileMetadata
}

private struct AppMetadata: Encodable {
    let bundleIdentifier: String
    let version: String
    let build: String
    let gitCommit: String?
    let builtAt: String?
}

private struct SystemMetadata: Encodable {
    let macOS: String
    let architecture: String
    let processorCount: Int
    let physicalMemory: UInt64

    static var current: SystemMetadata {
        SystemMetadata(
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: currentArchitecture,
            processorCount: ProcessInfo.processInfo.processorCount,
            physicalMemory: ProcessInfo.processInfo.physicalMemory
        )
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
            return "arm64"
        #elseif arch(x86_64)
            return "x86_64"
        #else
            return "unknown"
        #endif
    }
}

private struct TranscriptionMetadata: Encodable {
    let backend: String
    let backendID: String
    let activeModelIdentifier: String
    let selectedModel: String
    let modelState: String
    let modelsDiskUsage: String
}

private struct PermissionMetadata: Encodable {
    let accessibility: Bool
    let inputMonitoring: Bool
    let microphone: Bool
    let speechRecognition: Bool
    let status: String
}

private struct SettingsMetadata: Encodable {
    let hotkeyTrigger: String
    let overlayStyle: String
    let crabColorVariant: String
    let updaterConfigured: Bool
    let updaterFeedURL: String
    let boringMode: Bool
    let showInDock: Bool
    let dimSystemAudio: Bool
    let removeFillerWords: Bool
    let smartSpacing: Bool
    let appendTrailingSpace: Bool

    static var current: SettingsMetadata {
        let defaults = UserDefaults.standard
        return SettingsMetadata(
            hotkeyTrigger: defaults.string(forKey: Defaults.hotkeyTrigger)
                ?? HotkeyTrigger.defaultTrigger.rawValue,
            overlayStyle: defaults.string(forKey: Defaults.overlayStyle)
                ?? OverlayStyle.crab.rawValue,
            crabColorVariant: defaults.string(forKey: Defaults.crabColorVariant)
                ?? CrabColorVariant.ocean.rawValue,
            updaterConfigured: AppUpdaterConfiguration.isConfigured,
            updaterFeedURL: AppUpdaterConfiguration.feedURLString,
            boringMode: defaults.bool(forKey: Defaults.boringMode),
            showInDock: defaults.object(forKey: Defaults.showInDock) as? Bool ?? true,
            dimSystemAudio: defaults.object(forKey: Defaults.dimSystemAudio) as? Bool ?? true,
            removeFillerWords: defaults.object(forKey: "removeFillerWords") as? Bool ?? true,
            smartSpacing: defaults.object(forKey: Defaults.smartSpacing) as? Bool ?? true,
            appendTrailingSpace: defaults.object(forKey: Defaults.appendTrailingSpace) as? Bool ?? true
        )
    }
}

private struct FileMetadata: Encodable {
    let runtimeLogPath: String
    let modelsDirectoryPath: String
}
