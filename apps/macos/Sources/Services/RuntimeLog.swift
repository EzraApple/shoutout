import Foundation

enum RuntimeLog {
    private static let queue = DispatchQueue(label: "com.ezraapple.shoutout.runtime-log")

    static let logURL: URL = {
        if ProcessInfo.processInfo.environment["SHOUTOUT_REPLAY_MANIFEST"] != nil,
            let output = ProcessInfo.processInfo.environment["SHOUTOUT_REPLAY_OUTPUT"] {
            return URL(fileURLWithPath: output).appendingPathExtension("runtime.log")
        }
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return library
            .appendingPathComponent("Logs")
            .appendingPathComponent(MiniTrialConfiguration.isEnabled ? "ShoutOut Mini Trial" : "ShoutOut")
            .appendingPathComponent("runtime.log")
    }()

    static func write(_ message: String) {
        let line = "\(Date()) \(message)\n"
        queue.async {
            if ProcessInfo.processInfo.arguments.contains("--cli") {
                try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
            } else {
                print(line, terminator: "")
            }

            do {
                try FileManager.default.createDirectory(
                    at: logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if FileManager.default.fileExists(atPath: logURL.path) {
                    let handle = try FileHandle(forWritingTo: logURL)
                    try handle.seekToEnd()
                    if let data = line.data(using: .utf8) {
                        try handle.write(contentsOf: data)
                    }
                    try handle.close()
                } else {
                    try line.write(to: logURL, atomically: true, encoding: .utf8)
                }
            } catch {
                print("RuntimeLog failed: \(error)")
            }
        }
    }

    static func flush() {
        queue.sync {}
    }
}
