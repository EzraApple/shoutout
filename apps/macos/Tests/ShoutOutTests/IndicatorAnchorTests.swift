import CoreGraphics
import XCTest
@testable import ShoutOut

final class IndicatorAnchorTests: XCTestCase {
    private let visibleFrame = CGRect(x: -1_600, y: 240, width: 1_440, height: 900)

    func testAllowedAnchorsMatchIndicatorStyle() {
        XCTAssertEqual(IndicatorAnchor.allowed(for: .crab), [.left, .right])
        XCTAssertEqual(IndicatorAnchor.allowed(for: .glass), [.left, .right, .top, .bottom])
        XCTAssertEqual(IndicatorAnchor.allowed(for: .capsule), [.left, .right, .top, .bottom])
        XCTAssertTrue(IndicatorAnchor.allowed(for: .off).isEmpty)
        XCTAssertFalse(IndicatorAnchor.left.isHorizontal)
        XCTAssertFalse(IndicatorAnchor.right.isHorizontal)
        XCTAssertTrue(IndicatorAnchor.top.isHorizontal)
        XCTAssertTrue(IndicatorAnchor.bottom.isHorizontal)
    }

    func testPillFramesRotateAndStayInsideOffsetVisibleFrame() {
        for style in [OverlayStyle.glass, .capsule] {
            for anchor in IndicatorAnchor.allowed(for: style) {
                let frame = anchor.frame(in: visibleFrame, style: style, crabHeight: 116)
                let expectedSize = anchor.isHorizontal
                    ? CGSize(width: 116, height: 40)
                    : CGSize(width: 40, height: 116)

                XCTAssertEqual(frame.size, expectedSize, "\(style) \(anchor)")
                XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX, "\(style) \(anchor)")
                XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX, "\(style) \(anchor)")
                XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY, "\(style) \(anchor)")
                XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY, "\(style) \(anchor)")

                if anchor.isHorizontal {
                    XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.01)
                } else {
                    XCTAssertEqual(frame.midY, visibleFrame.midY, accuracy: 0.01)
                }
            }
        }
    }

    func testFramesUseTheRequestedEdgeWithNegativeScreenCoordinates() {
        let frames = Dictionary(uniqueKeysWithValues: IndicatorAnchor.allCases.map {
            ($0, $0.frame(in: visibleFrame, style: .glass, crabHeight: 116))
        })

        XCTAssertLessThan(frames[.left]!.midX, visibleFrame.midX)
        XCTAssertGreaterThan(frames[.right]!.midX, visibleFrame.midX)
        XCTAssertGreaterThan(frames[.top]!.midY, visibleFrame.midY)
        XCTAssertLessThan(frames[.bottom]!.midY, visibleFrame.midY)
    }

    func testCrabFramesStayNearSidesWithAtMostFourPointBleed() {
        for anchor in IndicatorAnchor.allowed(for: .crab) {
            let frame = anchor.frame(in: visibleFrame, style: .crab, crabHeight: 128)
            XCTAssertEqual(frame.width, 72, accuracy: 0.01)
            XCTAssertEqual(frame.height, 128, accuracy: 0.01)
            XCTAssertEqual(frame.midY, visibleFrame.midY + 18, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX - 4)
            XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX + 4)
            XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY)
            XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY)
        }
    }

    func testDropTargetsFollowEachEdgeAndSelectOnlyAllowedAnchors() {
        for anchor in IndicatorAnchor.allCases {
            let target = anchor.targetFrame(in: visibleFrame)
            XCTAssertEqual(
                IndicatorAnchor.dropTarget(at: CGPoint(x: target.midX, y: target.midY),
                                           in: visibleFrame, style: .glass),
                anchor
            )
            if anchor.isHorizontal {
                XCTAssertEqual(target.midX, visibleFrame.midX, accuracy: 0.01)
                XCTAssertEqual(target.size, CGSize(width: 144, height: 88))
            } else {
                XCTAssertEqual(target.midY, visibleFrame.midY, accuracy: 0.01)
                XCTAssertEqual(target.size, CGSize(width: 88, height: 144))
            }
        }

        let topTarget = IndicatorAnchor.top.targetFrame(in: visibleFrame)
        XCTAssertNil(IndicatorAnchor.dropTarget(at: CGPoint(x: topTarget.midX, y: topTarget.midY),
                                                in: visibleFrame, style: .crab))
    }

    func testDropTargetsDoNotSelectFromTheScreenCenterOrWhenOff() {
        let center = CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        XCTAssertNil(IndicatorAnchor.dropTarget(at: center, in: visibleFrame, style: .glass))
        XCTAssertNil(IndicatorAnchor.dropTarget(at: center, in: visibleFrame, style: .crab))

        for anchor in IndicatorAnchor.allCases {
            let target = anchor.targetFrame(in: visibleFrame)
            let point = CGPoint(x: target.midX, y: target.midY)
            XCTAssertNil(IndicatorAnchor.dropTarget(at: point, in: visibleFrame, style: .off))
        }
    }

    func testDropTargetSelectionExtendsTwentyFourPointsBeyondVisibleTarget() {
        let target = IndicatorAnchor.left.targetFrame(in: visibleFrame)
        XCTAssertEqual(
            IndicatorAnchor.dropTarget(at: CGPoint(x: target.minX - 23, y: target.midY),
                                       in: visibleFrame, style: .glass),
            .left
        )
        XCTAssertNil(
            IndicatorAnchor.dropTarget(at: CGPoint(x: target.minX - 25, y: target.midY),
                                       in: visibleFrame, style: .glass)
        )
    }

    func testCrabCanDropSidewaysAcrossItsCrawlRange() {
        for anchor in [IndicatorAnchor.left, .right] {
            let target = anchor.targetFrame(in: visibleFrame)
            for offset: CGFloat in [-130, 130] {
                let point = CGPoint(x: target.midX, y: target.midY + offset)
                XCTAssertEqual(IndicatorAnchor.dropTarget(at: point, in: visibleFrame, style: .crab), anchor)
                XCTAssertNil(IndicatorAnchor.dropTarget(at: point, in: visibleFrame, style: .glass))
            }
        }
    }
}
