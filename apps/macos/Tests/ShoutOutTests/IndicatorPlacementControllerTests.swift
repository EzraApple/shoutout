import AppKit
import XCTest
@testable import ShoutOut

@MainActor
final class IndicatorPlacementControllerTests: XCTestCase {
    func testDroppingGlassAtTopPersistsPlacementAndDismissesGuides() throws {
        let harness = try Harness(style: .glass)
        defer { harness.close() }

        let originalFrame = harness.panel.frame
        XCTAssertTrue(harness.newGuidePanels.isEmpty)

        let topTarget = IndicatorAnchor.top.targetFrame(in: harness.screen.visibleFrame)
        harness.drag(to: CGPoint(x: topTarget.midX, y: topTarget.midY),
                     translation: CGSize(width: 32, height: -18))

        XCTAssertTrue(harness.controller.isDragging)
        XCTAssertTrue(harness.panel.isVisible)
        XCTAssertEqual(harness.panel.frame.origin,
                       CGPoint(x: originalFrame.minX + 32, y: originalFrame.minY + 18))
        let guides = harness.newGuidePanels
        XCTAssertEqual(guides.count, NSScreen.screens.count)
        XCTAssertTrue(guides.allSatisfy(\.isVisible))

        harness.model.onDragEnded?()

        XCTAssertFalse(harness.controller.isDragging)
        XCTAssertEqual(harness.defaults.string(forKey: "indicatorAnchor.glass"), "top")
        XCTAssertNotNil(harness.defaults.object(forKey: "indicatorDisplay.glass"))
        XCTAssertEqual(harness.model.anchor, .top)
        XCTAssertEqual(harness.panel.frame,
                       IndicatorAnchor.top.frame(in: harness.screen.visibleFrame,
                                                 style: .glass, crabHeight: harness.model.crabHeight))
        XCTAssertTrue(harness.panel.isVisible)
        XCTAssertTrue(guides.allSatisfy { !$0.isVisible })
    }

    func testDroppingInCenterRestoresSavedAnchor() throws {
        let harness = try Harness(style: .glass, savedAnchor: .top)
        defer { harness.close() }
        let originalFrame = harness.panel.frame

        harness.drag(to: CGPoint(x: harness.screen.visibleFrame.midX,
                                 y: harness.screen.visibleFrame.midY))
        XCTAssertTrue(harness.controller.isDragging)
        let guides = harness.newGuidePanels
        harness.model.onDragEnded?()

        XCTAssertFalse(harness.controller.isDragging)
        XCTAssertEqual(harness.defaults.string(forKey: "indicatorAnchor.glass"), "top")
        XCTAssertEqual(harness.model.anchor, .top)
        XCTAssertEqual(harness.panel.frame, originalFrame)
        XCTAssertTrue(guides.allSatisfy { !$0.isVisible })
    }

    func testCancelRestoresFrameWithoutSavingDropTarget() throws {
        let harness = try Harness(style: .glass)
        defer { harness.close() }
        let originalFrame = harness.panel.frame
        let topTarget = IndicatorAnchor.top.targetFrame(in: harness.screen.visibleFrame)

        harness.drag(to: CGPoint(x: topTarget.midX, y: topTarget.midY),
                     translation: CGSize(width: 28, height: 0))
        let guides = harness.newGuidePanels
        harness.controller.cancelDrag()

        XCTAssertFalse(harness.controller.isDragging)
        XCTAssertNil(harness.defaults.string(forKey: "indicatorAnchor.glass"))
        XCTAssertEqual(harness.model.anchor, .right)
        XCTAssertEqual(harness.panel.frame, originalFrame)
        XCTAssertTrue(guides.allSatisfy { !$0.isVisible })
    }

    func testCrabRejectsTopDrop() throws {
        let harness = try Harness(style: .crab)
        defer { harness.close() }
        let originalFrame = harness.panel.frame
        let topTarget = IndicatorAnchor.top.targetFrame(in: harness.screen.visibleFrame)

        harness.drag(to: CGPoint(x: topTarget.midX, y: topTarget.midY))
        harness.model.onDragEnded?()

        XCTAssertNil(harness.defaults.string(forKey: "indicatorAnchor.crab"))
        XCTAssertEqual(harness.model.anchor, .right)
        XCTAssertEqual(harness.panel.frame, originalFrame)
    }

    func testInteractionRegionMakesEmptyPanelAreaClickThrough() throws {
        let harness = try Harness(style: .glass)
        defer { harness.close() }
        let view = try XCTUnwrap(harness.panel.contentView)
        let pointer = view.convert(harness.panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let region = CGRect(
            x: pointer.x < view.bounds.midX ? view.bounds.maxX - 1 : view.bounds.minX,
            y: pointer.y < view.bounds.midY ? view.bounds.maxY - 1 : view.bounds.minY,
            width: 1, height: 1
        )

        harness.model.onInteractionRegionChanged?(region)

        XCTAssertTrue(harness.panel.ignoresMouseEvents)
        XCTAssertFalse(harness.controller.isDragging)
        XCTAssertTrue(harness.newGuidePanels.isEmpty)
    }

    func testTearDownDismissesGuidesDuringAnActiveDrag() throws {
        let harness = try Harness(style: .glass)
        defer { harness.close() }
        let topTarget = IndicatorAnchor.top.targetFrame(in: harness.screen.visibleFrame)
        harness.drag(to: CGPoint(x: topTarget.midX, y: topTarget.midY))
        let guides = harness.newGuidePanels
        XCTAssertEqual(guides.count, NSScreen.screens.count)

        harness.controller.tearDown()

        XCTAssertFalse(harness.controller.isDragging)
        XCTAssertTrue(guides.allSatisfy { !$0.isVisible })
        XCTAssertNil(harness.defaults.string(forKey: "indicatorAnchor.glass"))
    }
}

@MainActor
private final class Harness {
    let suite: String
    let defaults: UserDefaults
    let screen: NSScreen
    let panel: NSPanel
    let model: IndicatorOverlayModel
    let controller: IndicatorPlacementController
    private let priorWindowNumbers: Set<Int>

    init(style: OverlayStyle, savedAnchor: IndicatorAnchor? = nil) throws {
        _ = NSApplication.shared
        screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        suite = "ShoutOut.IndicatorPlacementTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        if let savedAnchor {
            defaults.set(savedAnchor.rawValue, forKey: "indicatorAnchor.\(style.rawValue)")
        }
        priorWindowNumbers = Set(NSApp.windows.map(\.windowNumber))
        model = IndicatorOverlayModel(style: style, state: .idle, crabHeight: 220)
        let initialFrame = IndicatorAnchor.right.frame(in: screen.visibleFrame,
                                                        style: style, crabHeight: 220)
        panel = NSPanel(contentRect: initialFrame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.contentView = NSView(frame: CGRect(origin: .zero, size: initialFrame.size))
        controller = IndicatorPlacementController(defaults: defaults)
        controller.attach(panel: panel, model: model)
        controller.placeIndicator()
        panel.orderFrontRegardless()
    }

    var newGuidePanels: [NSPanel] {
        NSApp.windows.compactMap { window in
            guard let panel = window as? NSPanel,
                  panel.level.rawValue == NSWindow.Level.statusBar.rawValue + 1,
                  !priorWindowNumbers.contains(panel.windowNumber) else { return nil }
            return panel
        }
    }

    func drag(to screenPoint: CGPoint, translation: CGSize = .zero) {
        let windowPoint = panel.convertPoint(fromScreen: screenPoint)
        let localPoint = panel.contentView?.convert(windowPoint, from: nil) ?? windowPoint
        model.onDragChanged?(localPoint, translation)
    }

    func close() {
        controller.tearDown()
        panel.close()
        defaults.removePersistentDomain(forName: suite)
    }
}
