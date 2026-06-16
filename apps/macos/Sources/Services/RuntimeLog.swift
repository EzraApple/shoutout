import Foundation

enum RuntimeLog {
    private static let queue = DispatchQueue(label: "com.ezraapple.shoutout.runtime-log")

    static let logURL: URL = {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return library
            .appendingPathComponent("Logs")
            .appendingPathComponent("ShoutOut")
            .appendingPathComponent("runtime.log")
    }()

    static func write(_ message: String) {
        let line = "\(Date()) \(message)\n"
        queue.async {
            print(line, terminator: "")

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
