import Foundation
import XCTest
@testable import ShoutOut

@MainActor
final class MiniLanguagePassIntegrationTests: XCTestCase {
    func testProductionDefaultIsBundledMiniAndGenerativeToolRemainsExplicit() throws {
        XCTAssertEqual(LanguagePassModelOption.defaultID, MiniCleanupConfiguration.modelID)
        XCTAssertEqual(LanguagePassModelOption.option(for: LanguagePassModelOption.defaultID).title, "Mini")
        XCTAssertEqual(LanguagePassModelOption.all.map(\.id), [LanguagePassModelOption.generativeDefaultID])
        let suite = "ShoutOut.MiniDefault.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = MiniCleanupConfiguration.makeLanguagePassService(defaults: defaults)
        XCTAssertTrue(service.usesMiniEditor)
        XCTAssertEqual(service.selectedModelID, LanguagePassModelOption.defaultID)
        XCTAssertEqual(service.availableModels, [LanguagePassModelOption.defaultID])
        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(defaults.object(forKey: Defaults.languagePassModel) as? String, nil)
    }

    func testLoadFailurePreservesExactInputWithoutFormatting() async {
        let service = LanguagePassService(miniModelDirectory: URL(fileURLWithPath: "/nonexistent/mini-test"))
        let source = "  UM, Can We Just Like Keep This?\n"
        let result = await service.process(rawText: source, baseText: source)
        XCTAssertTrue(result.finalText == source)
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.fallbackReason, "model_not_ready")
        XCTAssertNil(result.candidateText)
        XCTAssertNil(result.styleRawValue)
    }

    func testDisabledTrialDoesNotChangeSavedSettings() async {
        let keys = [Defaults.languagePassModel, Defaults.languagePassStyle, Defaults.languagePassEnabled]
        let before = keys.map { UserDefaults.standard.object(forKey: $0).map { String(describing: $0) } }
        let service = LanguagePassService(miniModelDirectory: URL(fileURLWithPath: "/nonexistent/mini-test"))
        service.selectedStyle = .formal
        service.isEnabled = false
        let source = "  Um, Keep THIS?\n"
        let result = await service.process(rawText: source, baseText: source)
        XCTAssertTrue(result.finalText == source)
        XCTAssertFalse(result.enabled)
        XCTAssertEqual(result.fallbackReason, "disabled")
        XCTAssertNil(result.modelID)
        XCTAssertNil(result.styleRawValue)
        let after = keys.map { UserDefaults.standard.object(forKey: $0).map { String(describing: $0) } }
        XCTAssertEqual(before, after)
    }

    func testTrialSettingsPersistOnlyInProvidedSuite() throws {
        let suite = "ShoutOut.MiniTrial.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = LanguagePassService(
            miniModelDirectory: URL(fileURLWithPath: "/nonexistent/mini-test"), defaults: defaults)
        XCTAssertTrue(service.usesMiniEditor)
        XCTAssertTrue(service.isEnabled)
        service.isEnabled = false
        XCTAssertEqual(defaults.object(forKey: Defaults.languagePassEnabled) as? Bool, false)
        let nextLaunch = LanguagePassService(
            miniModelDirectory: URL(fileURLWithPath: "/nonexistent/mini-test"), defaults: defaults)
        XCTAssertFalse(nextLaunch.isEnabled)
        XCTAssertTrue(nextLaunch.usesMiniEditor)
    }

    func testProductionMiniClearsLegacyToneAndModel() throws {
        let suite = "ShoutOut.MiniDefault.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("formal", forKey: Defaults.languagePassStyle)
        defaults.set("mlx-community/Llama-3.2-1B-Instruct-4bit", forKey: Defaults.languagePassModel)
        let service = MiniCleanupConfiguration.makeLanguagePassService(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: Defaults.languagePassStyle))
        XCTAssertNil(defaults.object(forKey: Defaults.languagePassModel))
        XCTAssertEqual(service.selectedModelID, MiniCleanupConfiguration.modelID)
    }

    func testPrivateDevelopmentReplayThroughAppService() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["MINI_TEST_MODEL_DIRECTORY"],
              let casePath = environment["MINI_TEST_CASES"] else {
            throw XCTSkip("Set private Mini asset and development-case paths to run the app-service replay.")
        }
        struct ReplayCase: Decodable {
            let id: String
            let source: String
            let expectedOutput: String
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: casePath))
        let cases = try data.split(separator: 10).map { try JSONDecoder().decode(ReplayCase.self, from: Data($0)) }
        XCTAssertEqual(cases.count, 168)
        let suite = "ShoutOut.MiniReplay.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("formal", forKey: Defaults.languagePassStyle)
        defaults.set(LanguagePassModelOption.generativeDefaultID, forKey: Defaults.languagePassModel)
        let service = MiniCleanupConfiguration.makeLanguagePassService(
            defaults: defaults, miniModelDirectory: URL(fileURLWithPath: directory))
        XCTAssertTrue(service.usesMiniEditor)
        XCTAssertEqual(service.selectedModelID, MiniCleanupConfiguration.modelID)
        XCTAssertNil(defaults.object(forKey: Defaults.languagePassStyle))
        XCTAssertNil(defaults.object(forKey: Defaults.languagePassModel))
        async let warmup: Void = service.prepareIfNeeded()
        async let firstRequest: Void = service.prepareIfNeeded()
        _ = await (warmup, firstRequest)
        XCTAssertEqual(service.modelState, .ready)
        for row in cases {
            let result = await service.process(rawText: row.source, baseText: row.source)
            XCTAssertNil(result.fallbackReason, "Unexpected fallback: \(row.id)")
            XCTAssertTrue(result.accepted, "Output rejected: \(row.id)")
            XCTAssertTrue(result.finalText == row.expectedOutput, "Native output differs: \(row.id)")
            XCTAssertTrue(result.candidateText == row.expectedOutput, "Candidate differs: \(row.id)")
        }
        service.unload()
        XCTAssertEqual(service.modelState, .unloaded)
    }
}
