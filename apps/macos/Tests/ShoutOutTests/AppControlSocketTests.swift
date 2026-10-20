import Foundation
import XCTest
@testable import ShoutOut

final class AppControlSocketTests: XCTestCase {
    @MainActor
    func testRoundTripAndShutdown() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("Control/app.sock")
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = AppControlSocket(path: path) { request in
            MainActor.assertIsolated()
            return AppControlResponse(ok: true, values: ["command": request.command])
        }
        try server.start()
        let response = try await AppControlSocket.request(
            AppControlRequest(command: "status"), at: path, timeout: 2
        )
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.values["command"], "status")
        XCTAssertEqual(try permissions(at: path), 0o600)
        XCTAssertEqual(try permissions(at: path.deletingLastPathComponent()), 0o700)

        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        do {
            _ = try await AppControlSocket.request(AppControlRequest(command: "status"), at: path, timeout: 1)
            XCTFail("A stopped server must be unavailable.")
        } catch {
            XCTAssertTrue(AppControlSocket.isConnectionUnavailable(error))
        }
    }

    @MainActor
    func testSecondServerCannotReplaceLiveSocket() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("Control/app.sock")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = AppControlSocket(path: path) { _ in AppControlResponse(ok: true) }
        let second = AppControlSocket(path: path) { _ in AppControlResponse(ok: false) }
        try first.start()
        defer { first.stop() }
        XCTAssertThrowsError(try second.start())
        let response = try await AppControlSocket.request(
            AppControlRequest(command: "status"), at: path, timeout: 2
        )
        XCTAssertTrue(response.ok)
    }

    @MainActor
    func testResponseTimeoutDoesNotSignalSafeOfflineRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("Control/app.sock")
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = AppControlSocket(path: path) { _ in
            try? await Task.sleep(for: .milliseconds(300))
            return AppControlResponse(ok: true)
        }
        try server.start()
        defer { server.stop() }
        do {
            _ = try await AppControlSocket.request(
                AppControlRequest(command: "prepare-model"), at: path, timeout: 0.05
            )
            XCTFail("A delayed response must time out.")
        } catch {
            XCTAssertFalse(AppControlSocket.isConnectionUnavailable(error))
        }
    }

    private func permissions(at path: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
