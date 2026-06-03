import XCTest
import CoreGraphics
@testable import Fiddle

final class JiggleMathTests: XCTestCase {

    func testAlwaysJigglesWhenNotIdleOnly() {
        XCTAssertTrue(JiggleMath.shouldJiggle(idleOnly: false, secondsSinceInput: 0, threshold: 3))
    }

    func testIdleOnlyPausesWhileUserActive() {
        XCTAssertFalse(JiggleMath.shouldJiggle(idleOnly: true, secondsSinceInput: 1, threshold: 3))
    }

    func testIdleOnlyJigglesOnceIdlePastThreshold() {
        XCTAssertTrue(JiggleMath.shouldJiggle(idleOnly: true, secondsSinceInput: 5, threshold: 3))
        XCTAssertTrue(JiggleMath.shouldJiggle(idleOnly: true, secondsSinceInput: 3, threshold: 3))
    }

    func testZenNudgeReturnsToOrigin() {
        let (move, restore) = JiggleMath.nudge(from: CGPoint(x: 100, y: 100), dx: 40, zen: true)
        XCTAssertEqual(move, CGPoint(x: 140, y: 100))
        XCTAssertEqual(restore, CGPoint(x: 100, y: 100))
    }

    func testVisibleNudgeDoesNotReturn() {
        let (move, restore) = JiggleMath.nudge(from: CGPoint(x: 100, y: 100), dx: -40, zen: false)
        XCTAssertEqual(move, CGPoint(x: 60, y: 100))
        XCTAssertNil(restore)
    }
}
