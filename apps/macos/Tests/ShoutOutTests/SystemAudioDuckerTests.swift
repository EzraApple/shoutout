import Foundation
import XCTest
@testable import ShoutOut

@MainActor
final class SystemAudioDuckerTests: XCTestCase {
    func testEndWaitsForInFlightDimThenRestoresOriginalVolume() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = FakeVolumeDevice(volume: 60)
        await device.blockNextDim()
        let ducker = makeDucker(defaults: defaults, device: device)

        ducker.beginDuckingIfEnabled()
        await device.dimStarted.wait()
        ducker.endDucking()
        await device.releaseDim.open()
        await ducker.waitForPendingOperations()

        let state = await device.snapshot()
        XCTAssertEqual(state.volume, 60)
        XCTAssertEqual(state.writes, [10, 60])
        XCTAssertNil(defaults.object(forKey: savedVolumeKey))
    }

    func testEndDuringPendingReadNeverDims() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = FakeVolumeDevice(volume: 60)
        await device.blockNextRead()
        let ducker = makeDucker(defaults: defaults, device: device)

        ducker.beginDuckingIfEnabled()
        await device.readStarted.wait()
        ducker.endDucking()
        await device.releaseRead.open()
        await ducker.waitForPendingOperations()

        let state = await device.snapshot()
        XCTAssertEqual(state.volume, 60)
        XCTAssertTrue(state.writes.isEmpty)
        XCTAssertNil(defaults.object(forKey: savedVolumeKey))
    }

    func testRapidBeginEndBeginRestoresBeforeSecondDim() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = FakeVolumeDevice(volume: 60)
        await device.blockNextDim()
        let ducker = makeDucker(defaults: defaults, device: device)

        ducker.beginDuckingIfEnabled()
        await device.dimStarted.wait()
        ducker.endDucking()
        ducker.beginDuckingIfEnabled()
        await device.releaseDim.open()
        await ducker.waitForPendingOperations()

        let dimmed = await device.snapshot()
        XCTAssertEqual(dimmed.volume, 10)
        XCTAssertEqual(dimmed.writes, [10, 60, 10])
        XCTAssertEqual(defaults.integer(forKey: savedVolumeKey), 60)

        ducker.endDucking()
        await ducker.waitForPendingOperations()
        let restored = await device.snapshot()
        XCTAssertEqual(restored.volume, 60)
        XCTAssertEqual(restored.writes, [10, 60, 10, 60])
        XCTAssertNil(defaults.object(forKey: savedVolumeKey))
    }

    func testFailedWriteKeepsPersistedOriginalUntilRestoreSucceeds() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = FakeVolumeDevice(volume: 60)
        await device.failNextWrite(to: 10)
        await device.failNextWrite(to: 60)
        let ducker = makeDucker(defaults: defaults, device: device)

        ducker.beginDuckingIfEnabled()
        await ducker.waitForPendingOperations()
        let afterFailure = await device.snapshot()
        XCTAssertEqual(defaults.integer(forKey: savedVolumeKey), 60)
        XCTAssertEqual(afterFailure.volume, 60)

        ducker.endDucking()
        await ducker.waitForPendingOperations()
        let restored = await device.snapshot()
        XCTAssertEqual(restored.volume, 60)
        XCTAssertEqual(restored.writes, [10, 60, 60])
        XCTAssertNil(defaults.object(forKey: savedVolumeKey))
    }

    func testFailedStartupReadPreservesPersistedRestoreAndSkipsNewDim() async {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(60, forKey: savedVolumeKey)
        let device = FakeVolumeDevice(volume: 10)
        await device.failNextReads(2)
        let ducker = makeDucker(defaults: defaults, device: device)

        await ducker.waitForPendingOperations()
        ducker.beginDuckingIfEnabled()
        await ducker.waitForPendingOperations()
        let state = await device.snapshot()

        XCTAssertEqual(defaults.integer(forKey: savedVolumeKey), 60)
        XCTAssertTrue(state.writes.isEmpty)
    }

    private var savedVolumeKey: String { "audioDucker.savedOutputVolume" }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "SystemAudioDuckerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: Defaults.dimSystemAudio)
        return (defaults, suite)
    }

    private func makeDucker(defaults: UserDefaults, device: FakeVolumeDevice) -> SystemAudioDucker {
        SystemAudioDucker(
            defaults: defaults,
            readVolume: { await device.read() },
            setVolume: { await device.write($0) }
        )
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private actor FakeVolumeDevice {
    let readStarted = AsyncGate()
    let releaseRead = AsyncGate()
    let dimStarted = AsyncGate()
    let releaseDim = AsyncGate()

    private var volume: Int
    private var writes: [Int] = []
    private var blockRead = false
    private var blockDim = false
    private var failedReads = 0
    private var failedWrites: [Int: Int] = [:]

    init(volume: Int) { self.volume = volume }

    func blockNextRead() { blockRead = true }
    func blockNextDim() { blockDim = true }
    func failNextReads(_ count: Int) { failedReads = count }
    func failNextWrite(to target: Int) { failedWrites[target, default: 0] += 1 }

    func read() async -> Int? {
        if blockRead {
            blockRead = false
            await readStarted.open()
            await releaseRead.wait()
        }
        if failedReads > 0 {
            failedReads -= 1
            return nil
        }
        return volume
    }

    func write(_ target: Int) async -> Bool {
        if target == 10, blockDim {
            blockDim = false
            await dimStarted.open()
            await releaseDim.wait()
        }
        writes.append(target)
        volume = target
        if failedWrites[target, default: 0] > 0 {
            failedWrites[target, default: 0] -= 1
            return false
        }
        return true
    }

    func snapshot() -> (volume: Int, writes: [Int]) { (volume, writes) }
}
