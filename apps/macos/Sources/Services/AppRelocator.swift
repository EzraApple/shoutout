import AppKit
import Foundation

enum AppRelocator {
    private static let appBundleName = "ShoutOut.app"
    private static let skipEnvironmentKey = "SHOUTOUT_SKIP_USER_INSTALL_RELOCATION"

    @MainActor
    static func installToUserApplicationsIfNeeded() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment[skipEnvironmentKey] == nil else {
            RuntimeLog.write("install relocation skipped reason=environment")
            return false
        }
        guard environment["SHOUTOUT_OVERLAY_PREVIEW"] == nil,
            environment["SHOUTOUT_OVERLAY_SNAPSHOT_PATH"] == nil
        else {
            RuntimeLog.write("install relocation skipped reason=overlayPreview")
            return false
        }

        let bundleURL = Bundle.main.bundleURL
        let userApplicationsURL = userApplicationsDirectory()
        guard let reason = relocationReason(
            for: bundleURL,
            userApplicationsURL: userApplicationsURL
        ) else {
            RuntimeLog.write("install relocation skipped source=\(bundleURL.path)")
            return false
        }

        let destinationURL = userApplicationsURL.appendingPathComponent(appBundleName, isDirectory: true)
        RuntimeLog.write(
            "install relocation start reason=\(reason) source=\(bundleURL.path) destination=\(destinationURL.path)"
        )

        do {
            try copyBundle(from: bundleURL, to: destinationURL)
            try relaunchInstalledBundle(at: destinationURL)
            RuntimeLog.write("install relocation relaunched destination=\(destinationURL.path)")
            RuntimeLog.flush()
            NSApp.terminate(nil)
            return true
        } catch {
            RuntimeLog.write("install relocation failed error=\(error)")
            showFailureAlert(error: error, destinationURL: destinationURL)
            return false
        }
    }

    private static func relocationReason(
        for bundleURL: URL,
        userApplicationsURL: URL
    ) -> String? {
        guard bundleURL.pathExtension == "app" else { return nil }
        guard !isDescendant(bundleURL, of: userApplicationsURL) else { return nil }

        if bundleURL.path.contains("/AppTranslocation/") {
            return "appTranslocation"
        }
        if isDescendant(bundleURL, of: URL(fileURLWithPath: "/Volumes", isDirectory: true)) {
            return "diskImage"
        }
        if isDescendant(bundleURL, of: URL(fileURLWithPath: "/Applications", isDirectory: true)) {
            return "rootApplications"
        }
        if let downloadsURL = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first,
            isDescendant(bundleURL, of: downloadsURL)
        {
            return "downloads"
        }
        if hasQuarantineAttribute(bundleURL) {
            return "quarantined"
        }

        return nil
    }

    private static func userApplicationsDirectory() -> URL {
        FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                "Applications",
                isDirectory: true
            )
    }

    private static func copyBundle(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        let temporaryURL = destinationDirectory.appendingPathComponent(
            ".ShoutOut.installing-\(UUID().uuidString).app",
            isDirectory: true
        )
        var shouldRemoveTemporaryBundle = true
        defer {
            if shouldRemoveTemporaryBundle {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        removeQuarantineAttribute(from: temporaryURL)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        shouldRemoveTemporaryBundle = false
        removeQuarantineAttribute(from: destinationURL)
    }

    private static func relaunchInstalledBundle(at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", url.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RelocationError.relaunchFailed(url.path)
        }
    }

    private static func isDescendant(_ url: URL, of directoryURL: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let directoryPath = directoryURL.standardizedFileURL.resolvingSymlinksInPath().path
        return path == directoryPath || path.hasPrefix(directoryPath + "/")
    }

    private static func hasQuarantineAttribute(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-p", "com.apple.quarantine", url.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            RuntimeLog.write("install relocation quarantine check failed error=\(error)")
            return false
        }
    }

    private static func removeQuarantineAttribute(from url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            RuntimeLog.write("install relocation quarantine clear failed error=\(error)")
        }
    }

    @MainActor
    private static func showFailureAlert(error: Error, destinationURL: URL) {
        let alert = NSAlert()
        alert.messageText = "ShoutOut couldn't finish installing."
        alert.informativeText =
            "ShoutOut tried to install itself for this user at \(destinationURL.path), but macOS returned: \(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private enum RelocationError: LocalizedError {
        case relaunchFailed(String)

        var errorDescription: String? {
            switch self {
            case .relaunchFailed(let path):
                return "Could not relaunch ShoutOut from \(path)."
            }
        }
    }
}
