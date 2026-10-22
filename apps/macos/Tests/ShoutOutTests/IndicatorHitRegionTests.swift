import AppKit
import XCTest
@testable import ShoutOut

final class IndicatorHitRegionTests: XCTestCase {
    func testIdlePillCanBeGrabbedBesideItsThinVisibleSurface() {
        let bounds = CGRect(x: 0, y: 0, width: 40, height: 116)
        let surface = CGRect(x: 29, y: 43, width: 8, height: 30)
        let target = getIndicatorHitFrame(for: surface, style: .glass, anchor: .right, in: bounds)

        XCTAssertTrue(target.contains(CGPoint(x: 20, y: 58)))
        XCTAssertFalse(surface.contains(CGPoint(x: 20, y: 58)))
        XCTAssertGreaterThanOrEqual(target.width, 32)
        XCTAssertGreaterThanOrEqual(target.height, 48)
        XCTAssertFalse(target.contains(CGPoint(x: 20, y: 10)))
        XCTAssertTrue(bounds.contains(target))
    }

    func testHorizontalPillHasTheSameGrabAllowance() {
        let bounds = CGRect(x: 0, y: 0, width: 116, height: 40)
        let surface = CGRect(x: 43, y: 3, width: 30, height: 8)
        let target = getIndicatorHitFrame(for: surface, style: .capsule, anchor: .top, in: bounds)
        XCTAssertTrue(target.contains(CGPoint(x: 58, y: 20)))
        XCTAssertGreaterThanOrEqual(target.width, 48)
        XCTAssertTrue(bounds.contains(target))
    }

    func testCrabGrabAllowanceStaysNearTheVisibleCrab() {
        let bounds = CGRect(x: 0, y: 0, width: 72, height: 360)
        let surface = CGRect(x: 18, y: 142, width: 54, height: 76)
        let target = getIndicatorHitFrame(for: surface, style: .crab, anchor: .right, in: bounds)
        XCTAssertTrue(target.contains(CGPoint(x: 14, y: 180)))
        XCTAssertFalse(target.contains(CGPoint(x: 35, y: 30)))
        XCTAssertTrue(bounds.contains(target))
    }

    func testMissingSurfaceDoesNotCreateAnInvisibleGrabArea() {
        XCTAssertEqual(getIndicatorHitFrame(for: .zero, style: .glass, anchor: .right,
                                               in: CGRect(x: 0, y: 0, width: 40, height: 116)), .zero)
    }

    func testOffAndOutOfBoundsSurfacesHaveNoGrabArea() {
        let bounds = CGRect(x: 0, y: 0, width: 40, height: 116)
        XCTAssertEqual(getIndicatorHitFrame(for: CGRect(x: 100, y: 200, width: 8, height: 30),
                                           style: .glass, anchor: .right, in: bounds), .zero)
        XCTAssertEqual(getIndicatorHitFrame(for: CGRect(x: 29, y: 43, width: 8, height: 30),
                                           style: .off, anchor: .right, in: bounds), .zero)
    }

    @MainActor
    func testHostingViewAcceptsTheFirstMouseDownFromAnotherApp() {
        let model = IndicatorOverlayModel(style: .glass, state: .idle, crabHeight: 220)
        let view = IndicatorHostingView(rootView: IndicatorOverlayHostView(model: model))
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    }
}
