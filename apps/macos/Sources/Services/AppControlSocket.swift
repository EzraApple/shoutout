import Darwin
import Foundation

@_silgen_name("flock")
private func lockSocketFile(_ fd: Int32, _ operation: Int32) -> Int32

struct AppControlRequest: Codable, Sendable {
    let command: String
    let key: String?
    let value: String?
    let path: String?

    init(command: String, key: String? = nil, value: String? = nil, path: String? = nil) {
        self.command = command
        self.key = key
        self.value = value
        self.path = path
    }
}

struct AppControlResponse: Codable, Sendable {
    let ok: Bool
    let message: String?
    let values: [String: String]
    let text: String?
    let rawText: String?

    init(
        ok: Bool, message: String? = nil, values: [String: String] = [:],
        text: String? = nil, rawText: String? = nil
    ) {
        self.ok = ok
        self.message = message
        self.values = values
        self.text = text
        self.rawText = rawText
    }
}

enum AppControlSocketError: LocalizedError {
    case notRunning
    case unavailable(String)
    case alreadyRunning
    case pathTooLong
    case timedOut
    case oversizedMessage
    case invalidMessage

    var errorDescription: String? {
        switch self {
        case .notRunning: return "The ShoutOut app control server is not running."
        case .unavailable(let detail): return detail
        case .alreadyRunning: return "An app control server is already using this socket."
        case .pathTooLong: return "The app control socket path is too long."
        case .timedOut: return "The app control socket timed out."
        case .oversizedMessage: return "The app control socket message is too large."
        case .invalidMessage: return "The app control socket sent invalid JSON."
        }
    }
}

/// One JSON request and one JSON response per private local connection.
final class AppControlSocket: @unchecked Sendable {
    static let requestLimit = 64 * 1_024
    static let responseLimit = 512 * 1_024
    static let defaultPath = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0]
    .appendingPathComponent("com.ezraapple.shoutout/Control/app.sock")

    private let path: URL
    private let handler: @MainActor @Sendable (AppControlRequest) async -> AppControlResponse
    private let lock = NSLock()
    private var listeningFD: Int32 = -1
    private var ownershipLockFD: Int32 = -1
    private var starting = false
    private var generation = 0
    private var activeClients: Set<Int32> = []
    private var ownedDevice: dev_t?
    private var ownedInode: ino_t?

    init(
        path: URL,
        handler: @escaping @MainActor @Sendable (AppControlRequest) async -> AppControlResponse
    ) {
        self.path = path
        self.handler = handler
    }

    func start() throws {
        let state = lock.withLock { () -> Int in
            if listeningFD >= 0 { return 0 }
            if starting { return 1 }
            starting = true
            return 2
        }
        if state == 0 { return }
        if state == 1 { throw AppControlSocketError.alreadyRunning }
        defer { lock.withLock { starting = false } }
        let directory = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard directory.path.withCString({ Darwin.chmod($0, 0o700) }) == 0 else {
            throw Self.systemError("Cannot protect app control directory")
        }
        let lockPath = path.path + ".lock"
        let lockFD = lockPath.withCString { Darwin.open($0, O_CREAT | O_RDWR | O_CLOEXEC, 0o600) }
        guard lockFD >= 0 else { throw Self.systemError("Cannot open app control lock") }
        var retainLock = false
        defer { if !retainLock { Darwin.close(lockFD) } }
        guard lockPath.withCString({ Darwin.chmod($0, 0o600) }) == 0 else {
            throw Self.systemError("Cannot protect app control lock")
        }
        guard lockSocketFile(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            throw AppControlSocketError.alreadyRunning
        }
        var address = try Self.address(for: path)
        try Self.removeStaleSocket(at: path, address: &address)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Self.systemError("Cannot create app control socket") }
        var boundOwnership: (dev_t, ino_t)?
        do {
            try Self.protectWrites(fd)
            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bindResult == 0 else { throw Self.systemError("Cannot bind app control socket") }
            var metadata = stat()
            guard path.path.withCString({ Darwin.lstat($0, &metadata) }) == 0 else {
                throw Self.systemError("Cannot inspect app control socket")
            }
            boundOwnership = (metadata.st_dev, metadata.st_ino)
            guard path.path.withCString({ Darwin.chmod($0, 0o600) }) == 0 else {
                throw Self.systemError("Cannot protect app control socket")
            }
            guard Darwin.listen(fd, 16) == 0 else {
                throw Self.systemError("Cannot listen on app control socket")
            }
            let acceptedGeneration = lock.withLock { () -> Int? in
                guard listeningFD < 0 else { return nil }
                listeningFD = fd
                ownershipLockFD = lockFD
                ownedDevice = metadata.st_dev
                ownedInode = metadata.st_ino
                generation += 1
                return generation
            }
            guard let acceptedGeneration else {
                throw AppControlSocketError.alreadyRunning
            }
            retainLock = true
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.acceptConnections(on: fd, generation: acceptedGeneration)
            }
        } catch {
            Darwin.close(fd)
            if let boundOwnership {
                Self.removeSocket(at: path, device: boundOwnership.0, inode: boundOwnership.1)
            }
            throw error
        }
    }

    func stop() {
        let ownership = lock.withLock { () -> (Int32, Int32, dev_t?, ino_t?) in
            let current = (listeningFD, ownershipLockFD, ownedDevice, ownedInode)
            listeningFD = -1
            ownershipLockFD = -1
            ownedDevice = nil
            ownedInode = nil
            generation += 1
            for clientFD in activeClients { Darwin.shutdown(clientFD, SHUT_RDWR) }
            return current
        }
        guard ownership.0 >= 0 else { return }
        Darwin.shutdown(ownership.0, SHUT_RDWR)
        Darwin.close(ownership.0)
        if let device = ownership.2, let inode = ownership.3 {
            Self.removeSocket(at: path, device: device, inode: inode)
        }
        if ownership.1 >= 0 { Darwin.close(ownership.1) }
    }

    static func request(
        _ request: AppControlRequest, at path: URL, timeout: TimeInterval = 120
    ) async throws -> AppControlResponse {
        try await blocking {
            var address = try Self.address(for: path)
            let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw systemError("Cannot create app control client") }
            defer { Darwin.close(fd) }
            try protectWrites(fd)
            let connected = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connected == 0 else {
                if errno == ENOENT || errno == ECONNREFUSED {
                    throw AppControlSocketError.notRunning
                }
                throw systemError("Cannot connect to app control server")
            }
            let deadline = Date.timeIntervalSinceReferenceDate + max(timeout, 0.001)
            try write(request, to: fd, limit: requestLimit, deadline: deadline)
            return try read(AppControlResponse.self, from: fd, limit: responseLimit, deadline: deadline)
        }
    }

    static func isConnectionUnavailable(_ error: Error) -> Bool {
        guard let socketError = error as? AppControlSocketError else { return false }
        if case .notRunning = socketError { return true }
        return false
    }

    private func acceptConnections(on fd: Int32, generation: Int) {
        while true {
            guard lock.withLock({ self.generation == generation }) else { return }
            let clientFD = Darwin.accept(fd, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                return
            }
            let accepted = lock.withLock { () -> Bool in
                guard self.generation == generation else { return false }
                activeClients.insert(clientFD)
                return true
            }
            guard accepted else {
                Darwin.close(clientFD)
                return
            }
            Task.detached(priority: .utility) { [weak self] in
                guard let self else { Darwin.close(clientFD); return }
                await self.serve(clientFD)
            }
        }
    }

    private func serve(_ fd: Int32) async {
        defer {
            _ = lock.withLock { activeClients.remove(fd) }
            Darwin.close(fd)
        }
        do {
            try Self.protectWrites(fd)
            let request = try await Self.blocking {
                try Self.read(
                    AppControlRequest.self, from: fd, limit: Self.requestLimit,
                    deadline: Date.timeIntervalSinceReferenceDate + 10
                )
            }
            let response = await handler(request)
            try await Self.blocking {
                try Self.write(
                    response, to: fd, limit: Self.responseLimit,
                    deadline: Date.timeIntervalSinceReferenceDate + 10
                )
            }
        } catch {
            let response = AppControlResponse(ok: false, message: error.localizedDescription)
            try? await Self.blocking {
                try Self.write(
                    response, to: fd, limit: Self.responseLimit,
                    deadline: Date.timeIntervalSinceReferenceDate + 2
                )
            }
        }
    }

    private static func removeStaleSocket(at path: URL, address: inout sockaddr_un) throws {
        var metadata = stat()
        guard path.path.withCString({ Darwin.lstat($0, &metadata) }) == 0 else {
            if errno == ENOENT { return }
            throw systemError("Cannot inspect app control socket path")
        }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK) else {
            throw AppControlSocketError.unavailable("The app control path is occupied by another file.")
        }
        let probe = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { throw systemError("Cannot probe app control socket") }
        defer { Darwin.close(probe) }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected == 0 { throw AppControlSocketError.alreadyRunning }
        guard errno == ECONNREFUSED else {
            throw AppControlSocketError.unavailable("The app control socket path is unavailable.")
        }
        var current = stat()
        guard path.path.withCString({ Darwin.lstat($0, &current) }) == 0,
              current.st_dev == metadata.st_dev, current.st_ino == metadata.st_ino else {
            throw AppControlSocketError.unavailable("The app control socket changed during startup.")
        }
        guard path.path.withCString({ Darwin.unlink($0) }) == 0 else {
            throw systemError("Cannot remove stale app control socket")
        }
    }

    private static func removeSocket(at path: URL, device: dev_t, inode: ino_t) {
        var metadata = stat()
        if path.path.withCString({ Darwin.lstat($0, &metadata) }) == 0,
           metadata.st_dev == device, metadata.st_ino == inode {
            path.path.withCString { _ = Darwin.unlink($0) }
        }
    }

    private static func address(for path: URL) throws -> sockaddr_un {
        let bytes = Array(path.path.utf8)
        var address = sockaddr_un()
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw AppControlSocketError.pathTooLong
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: bytes)
            destination[bytes.count] = 0
        }
        return address
    }

    private static func protectWrites(_ fd: Int32) throws {
        var enabled: Int32 = 1
        guard Darwin.setsockopt(
            fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw systemError("Cannot configure app control socket")
        }
    }

    private static func read<Value: Decodable>(
        _ type: Value.Type, from fd: Int32, limit: Int, deadline: TimeInterval
    ) throws -> Value {
        var message = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            try setTimeout(fd, option: SO_RCVTIMEO, deadline: deadline)
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.recv(fd, bytes.baseAddress, bytes.count, 0)
            }
            if count == 0 { throw AppControlSocketError.unavailable("The app control connection closed.") }
            if count < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { throw AppControlSocketError.timedOut }
                throw systemError("Cannot read app control response")
            }
            message.append(contentsOf: buffer.prefix(count))
            if let newline = message.firstIndex(of: 0x0A) {
                guard newline <= limit else { throw AppControlSocketError.oversizedMessage }
                do { return try JSONDecoder().decode(type, from: message.prefix(upTo: newline)) }
                catch { throw AppControlSocketError.invalidMessage }
            }
            guard message.count <= limit else { throw AppControlSocketError.oversizedMessage }
        }
    }

    private static func write<Value: Encodable>(
        _ value: Value, to fd: Int32, limit: Int, deadline: TimeInterval
    ) throws {
        var data = try JSONEncoder().encode(value)
        guard data.count <= limit else { throw AppControlSocketError.oversizedMessage }
        data.append(0x0A)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try setTimeout(fd, option: SO_SNDTIMEO, deadline: deadline)
                let sent = Darwin.send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                if sent < 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN || errno == EWOULDBLOCK { throw AppControlSocketError.timedOut }
                    throw systemError("Cannot write app control message")
                }
                if sent == 0 { throw AppControlSocketError.unavailable("The app control connection closed.") }
                offset += sent
            }
        }
    }

    private static func setTimeout(_ fd: Int32, option: Int32, deadline: TimeInterval) throws {
        let remaining = deadline - Date.timeIntervalSinceReferenceDate
        guard remaining > 0 else { throw AppControlSocketError.timedOut }
        var interval = timeval(
            tv_sec: Int(remaining), tv_usec: Int32((remaining.truncatingRemainder(dividingBy: 1)) * 1_000_000)
        )
        guard Darwin.setsockopt(
            fd, SOL_SOCKET, option, &interval, socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else {
            throw systemError("Cannot set app control deadline")
        }
    }

    private static func blocking<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func systemError(_ action: String) -> AppControlSocketError {
        AppControlSocketError.unavailable("\(action): \(String(cString: strerror(errno)))")
    }
}
