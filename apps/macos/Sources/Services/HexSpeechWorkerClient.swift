import Foundation

enum HexSpeechWorkerError: LocalizedError {
    case unavailable(String)
    case timedOut(String)
    case protocolViolation(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail), .protocolViolation(let detail): return detail
        case .timedOut(let operation): return "Hex speech worker timed out during \(operation)."
        }
    }
}

/// Owns one native model process. All pipe operations happen outside the main actor.
actor HexSpeechWorkerClient {
    private struct Command: Encodable {
        let op: String
        let id: String
        let audio: String?
    }

    private struct Response: Decodable {
        let event: String
        let id: String?
        let text: String?
        let source: String?
        let message: String?
        let modelSha256: String?
        let streamAvailable: Bool?
    }

    private struct QueuedCommand {
        let command: Command
        let expectedEvent: String
        let timeout: Duration
        let continuation: CheckedContinuation<Response, Error>
    }

    private let executableURL: URL
    private let modelURL: URL
    private let expectedSHA256: String
    private let finishTimeout: Duration
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var lineBuffer = Data()
    private var ready = false
    private var stopped = false
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []
    private var queue: [QueuedCommand] = []
    private var active: QueuedCommand?
    private var deadline: Task<Void, Never>?
    private var reader: Task<Void, Never>?
    private var processGeneration = 0

    init(
        executableURL: URL, modelURL: URL, expectedSHA256: String,
        finishTimeout: Duration = .milliseconds(1_500)
    ) {
        self.executableURL = executableURL
        self.modelURL = modelURL
        self.expectedSHA256 = expectedSHA256
        self.finishTimeout = finishTimeout
    }

    func start() async throws {
        guard !stopped else { throw HexSpeechWorkerError.unavailable("Hex speech worker was unloaded.") }
        if ready { return }
        try await withCheckedThrowingContinuation { continuation in
            readyWaiters.append(continuation)
            guard process == nil else { return }

            let process = Process()
            let input = Pipe()
            let output = Pipe()
            process.executableURL = executableURL
            process.arguments = ["--model", modelURL.path]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.standardError
            self.process = process
            self.input = input
            self.output = output
            processGeneration += 1
            let generation = processGeneration
            process.terminationHandler = { [weak self] _ in
                Task { await self?.workerExited(generation: generation) }
            }

            do {
                try process.run()
                let readHandle = output.fileHandleForReading
                reader = Task.detached(priority: .userInitiated) { [weak self] in
                    while !Task.isCancelled {
                        let data = readHandle.availableData
                        await self?.receive(data, generation: generation)
                        if data.isEmpty { return }
                    }
                }
                deadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(90)) } catch { return }
                    await self?.startupTimedOut()
                }
            } catch {
                failProcess(error)
            }
        }
    }

    func begin(id: UUID) async throws {
        _ = try await send(op: "begin", id: id, audio: nil, expectedEvent: "begun", timeout: .seconds(3))
    }

    func feed(id: UUID, samples: [Float]) async throws {
        guard !samples.isEmpty else { return }
        _ = try await send(op: "feed", id: id, audio: encode(samples), expectedEvent: "fed", timeout: .seconds(3))
    }

    func finish(id: UUID) async throws -> (text: String, usedFallback: Bool) {
        let response = try await send(op: "finish", id: id, audio: nil, expectedEvent: "result", timeout: finishTimeout)
        guard let text = response.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HexSpeechWorkerError.protocolViolation("Hex stream returned empty text.")
        }
        guard response.source == "stream" || response.source == "fallback" else {
            throw HexSpeechWorkerError.protocolViolation("Hex stream returned an invalid result source.")
        }
        return (text, response.source == "fallback")
    }

    func cancel(id: UUID) async {
        _ = try? await send(op: "cancel", id: id, audio: nil, expectedEvent: "cancelled", timeout: .seconds(2))
    }

    func transcribe(id: UUID, samples: [Float]) async throws -> String {
        let response = try await send(
            op: "transcribe", id: id, audio: encode(samples), expectedEvent: "result", timeout: .seconds(60)
        )
        return response.text ?? ""
    }

    func stop() {
        stopped = true
        failProcess(HexSpeechWorkerError.unavailable("Hex speech worker was unloaded."))
    }

    private func send(
        op: String, id: UUID, audio: String?, expectedEvent: String, timeout: Duration
    ) async throws -> Response {
        try await start()
        return try await withCheckedThrowingContinuation { continuation in
            queue.append(QueuedCommand(
                command: Command(op: op, id: id.uuidString, audio: audio),
                expectedEvent: expectedEvent,
                timeout: timeout,
                continuation: continuation
            ))
            pump()
        }
    }

    private func pump() {
        guard active == nil, ready, !queue.isEmpty, let handle = input?.fileHandleForWriting else { return }
        let next = queue.removeFirst()
        active = next
        let generation = processGeneration
        do {
            var payload = try JSONEncoder().encode(next.command)
            payload.append(0x0A)
            let data = payload
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    try handle.write(contentsOf: data)
                } catch {
                    Task { await self?.writeFailed(error, generation: generation) }
                }
            }
            deadline = Task { [weak self] in
                do { try await Task.sleep(for: next.timeout) } catch { return }
                await self?.commandTimedOut(id: next.command.id)
            }
        } catch {
            failProcess(error)
        }
    }

    private func receive(_ data: Data, generation: Int) {
        guard generation == processGeneration else { return }
        guard !data.isEmpty else {
            failProcess(HexSpeechWorkerError.unavailable("Hex speech worker closed its output."))
            return
        }
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            let line = lineBuffer.prefix(upTo: newline)
            lineBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            do {
                let response = try JSONDecoder().decode(Response.self, from: Data(line))
                accept(response)
            } catch {
                failProcess(HexSpeechWorkerError.protocolViolation("Hex speech worker sent invalid JSON: \(error)"))
                return
            }
        }
    }

    private func accept(_ response: Response) {
        if !ready {
            guard response.event == "ready", response.modelSha256 == expectedSHA256,
                  response.streamAvailable == true else {
                failProcess(HexSpeechWorkerError.unavailable(response.message ?? "Hex speech worker rejected the model."))
                return
            }
            ready = true
            deadline?.cancel()
            deadline = nil
            let waiters = readyWaiters
            readyWaiters.removeAll()
            waiters.forEach { $0.resume() }
            pump()
            return
        }

        guard let active, response.id == active.command.id else {
            failProcess(HexSpeechWorkerError.protocolViolation("Hex speech worker returned a mismatched recording ID."))
            return
        }
        deadline?.cancel()
        deadline = nil
        self.active = nil
        if response.event == "error" {
            active.continuation.resume(throwing: HexSpeechWorkerError.unavailable(response.message ?? "Hex speech worker failed."))
        } else if response.event == active.expectedEvent {
            active.continuation.resume(returning: response)
        } else {
            active.continuation.resume(throwing: HexSpeechWorkerError.protocolViolation(
                "Hex speech worker returned \(response.event) for \(active.command.op)."
            ))
        }
        pump()
    }

    private func startupTimedOut() {
        guard !ready, process != nil else { return }
        failProcess(HexSpeechWorkerError.timedOut("model loading"))
    }

    private func commandTimedOut(id: String) {
        guard active?.command.id == id else { return }
        failProcess(HexSpeechWorkerError.timedOut(active?.command.op ?? "command"))
    }

    private func workerExited(generation: Int) {
        guard generation == processGeneration, process != nil else { return }
        failProcess(HexSpeechWorkerError.unavailable("Hex speech worker exited."))
    }

    private func writeFailed(_ error: Error, generation: Int) {
        guard generation == processGeneration else { return }
        failProcess(error)
    }

    private func failProcess(_ error: Error) {
        deadline?.cancel()
        deadline = nil
        reader?.cancel()
        reader = nil
        ready = false
        input?.fileHandleForWriting.closeFile()
        output?.fileHandleForReading.closeFile()
        if let process, process.isRunning { process.terminate() }
        process = nil
        input = nil
        output = nil
        lineBuffer.removeAll(keepingCapacity: true)

        let waiters = readyWaiters
        readyWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: error) }
        if let active { active.continuation.resume(throwing: error) }
        active = nil
        let waiting = queue
        queue.removeAll()
        waiting.forEach { $0.continuation.resume(throwing: error) }
    }

    private func encode(_ samples: [Float]) -> String {
        samples.withUnsafeBufferPointer { buffer in
            buffer.withMemoryRebound(to: UInt8.self) { bytes in
                Data(bytes).base64EncodedString()
            }
        }
    }
}
