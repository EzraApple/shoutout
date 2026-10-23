import AppKit
import XCTest
@testable import ShoutOut

@MainActor
final class IndicatorPlacementControllerTests: XCTestCase {
    func testOldPresentationCannotOverwriteNewGrabAreaOrStartADrag() throws {
        let harness = try Harness(style: .glass)
        defer { harness.close() }
        let oldGeometry = harness.model.onInteractionRegionChanged
        let oldDrag = harness.model.onDragChanged
        let replacement = IndicatorOverlayModel(style: .crab, state: .idle, crabHeight: 362)
        harness.controller.attach(panel: harness.panel, model: replacement)
        harness.controller.placeIndicator()
        replacement.onInteractionRegionChanged?(CGRect(x: 18, y: 143, width: 54, height: 76))
        let grabArea = replacement.dragRect

        oldGeometry?(CGRect(x: 29, y: 43, width: 8, height: 30))
        oldDrag?(CGPoint(x: 30, y: 58), CGSize(width: 20, height: 0))

        XCTAssertEqual(replacement.dragRect, grabArea)
        XCTAssertGreaterThanOrEqual(replacement.dragRect.height, 92)
        XCTAssertFalse(harness.controller.isDragging)
        XCTAssertNil(harness.model.onInteractionRegionChanged)
    }

    func testRebuiltNativePresentationsReportTheirOwnGrabAreasAndHover() async throws {
        var pointer = CGPoint.zero
        let harness = try Harness(style: .glass, pointerLocation: { pointer })
        defer { harness.close() }

        for style in [OverlayStyle.crab, .glass, .capsule, .crab, .glass] {
            pointer = .zero
            let model = IndicatorOverlayModel(style: style, state: .idle, crabHeight: 362)
            let view = IndicatorHostingView(rootView: IndicatorOverlayHostView(model: model))
            view.sizingOptions = .intrinsicContentSize
            view.autoresizingMask = [.width, .height]
            harness.panel.contentView = view
            harness.controller.attach(panel: harness.panel, model: model)
            harness.controller.placeIndicator()
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))

            XCTAssertGreaterThanOrEqual(model.dragRect.height, style == .crab ? 92 : 48, "\(style)")
            pointer = harness.panel.convertPoint(toScreen: view.convert(
                CGPoint(x: model.dragRect.midX, y: model.dragRect.midY), to: nil))
            harness.controller.samplePointer()
            XCTAssertTrue(model.isHovered, "\(style) should hover after replacing its presentation")
            XCTAssertFalse(harness.panel.ignoresMouseEvents)
        }
    }

    func testNativeCrabMouseEventsMoveBetweenBothSides() throws {
        let harness = try Harness(style: .crab)
        defer { harness.close() }
        let view = IndicatorHostingView(rootView: IndicatorOverlayHostView(model: harness.model))
        harness.panel.contentView = view
        view.frame = CGRect(origin: .zero, size: harness.panel.frame.size)
        view.dragRect = CGRect(x: 10, y: view.bounds.midY - 46, width: 62, height: 92)
        XCTAssertTrue(view.hitTest(CGPoint(x: 30, y: view.bounds.midY)) === view)

        for anchor in [IndicatorAnchor.left, .right] {
            let priorRevision = harness.model.crabPlacementRevision
            let start = CGPoint(x: harness.panel.frame.midX, y: harness.panel.frame.midY)
            let target = anchor.targetFrame(in: harness.screen.visibleFrame)
            func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type,
                    location: harness.panel.convertPoint(fromScreen: point), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: harness.panel.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            }
            view.mouseDown(with: try event(.leftMouseDown, at: start))
            view.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: target.midX, y: target.midY)))
            XCTAssertTrue(harness.controller.isDragging)
            view.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: target.midX, y: target.midY)))

            XCTAssertFalse(harness.controller.isDragging)
            XCTAssertEqual(harness.model.anchor, anchor)
            XCTAssertEqual(harness.model.crabPlacementRevision, priorRevision + 1)
            XCTAssertEqual(harness.defaults.string(forKey: "indicatorAnchor.crab"), anchor.rawValue)
        }
    }

    func testDroppingGlassAtTopPersistsPlacementAndDismissesGuides() throws {
        let harness = try Harness(style: .glass)
        defer { harness.close() }

        let originalFrame = harness.panel.frame
        XCTAssertTrue(harness.newGuidePanels.isEmpty)

        let topTarget = IndicatorAnchor.top.targetFrame(in: harness.screen.visibleFrame)
        harness.drag(to: CGPoint(x: topTarget.midX, y: topTarget.midY),
                     translation: CGSize(width: 32, height: -18))

        XCTAssertTrue(harness.controller.isDragging)
        XCTAssertTrue(harness.model.isDragging)
        XCTAssertTrue(harness.panel.isVisible)
        XCTAssertEqual(harness.panel.frame.origin,
                       CGPoint(x: originalFrame.minX + 32, y: originalFrame.minY + 18))
        let guides = harness.newGuidePanels
        XCTAssertEqual(guides.count, NSScreen.screens.count)
        XCTAssertTrue(guides.allSatisfy(\.isVisible))

        harness.model.onDragEnded?()

        XCTAssertFalse(harness.controller.isDragging)
        XCTAssertFalse(harness.model.isDragging)
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
        XCTAssertEqual(harness.model.crabPlacementRevision, 0)
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

    func testHoverStartsInThePaddedGrabAreaAndEndsOutsideIt() throws {
        var pointer = CGPoint.zero
        let harness = try Harness(style: .glass, pointerLocation: { pointer })
        defer { harness.close() }
        let view = try XCTUnwrap(harness.panel.contentView)
        pointer = harness.panel.convertPoint(toScreen: view.convert(CGPoint(x: 10, y: 58), to: nil))

        harness.model.onInteractionRegionChanged?(CGRect(x: 20, y: 43, width: 8, height: 30))

        XCTAssertTrue(harness.model.isHovered)
        XCTAssertFalse(harness.panel.ignoresMouseEvents)

        harness.model.onInteractionRegionChanged?(CGRect(x: 20, y: 0, width: 8, height: 30))

        XCTAssertFalse(harness.model.isHovered)
        XCTAssertTrue(harness.panel.ignoresMouseEvents)
    }

    func testPointerSamplingRestoresPillHoverAfterCrabWithoutMouseMoveEvents() async throws {
        var pointer = CGPoint.zero
        let harness = try Harness(style: .crab, pointerLocation: { pointer })
        defer { harness.close() }

        for style in [OverlayStyle.glass, .capsule] {
            harness.model.style = style
            harness.controller.placeIndicator()
            let view = try XCTUnwrap(harness.panel.contentView)
            harness.model.onInteractionRegionChanged?(CGRect(x: 29, y: 43, width: 8, height: 30))
            pointer = harness.panel.convertPoint(toScreen: view.convert(CGPoint(x: 22, y: 58), to: nil))

            try await Task.sleep(for: .milliseconds(150))

            XCTAssertTrue(harness.model.isHovered, "\(style) should hover without an NSEvent")
            XCTAssertFalse(harness.panel.ignoresMouseEvents)

            pointer = CGPoint(x: harness.screen.visibleFrame.midX, y: harness.screen.visibleFrame.midY)
            try await Task.sleep(for: .milliseconds(150))

            XCTAssertFalse(harness.model.isHovered)
            XCTAssertTrue(harness.panel.ignoresMouseEvents)
        }
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

    init(style: OverlayStyle, savedAnchor: IndicatorAnchor? = nil,
         pointerLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation }) throws {
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
        controller = IndicatorPlacementController(defaults: defaults, pointerLocation: pointerLocation)
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
