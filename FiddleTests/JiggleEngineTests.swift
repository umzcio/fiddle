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

    // The engine's own posted nudge resets the system idle clock; the reading
    // then roughly equals the time since the nudge and must NOT count as user
    // activity, or idle-only mode defeats itself.
    func testOwnNudgeIsNotUserInput() {
        XCTAssertFalse(JiggleMath.isRealUserInput(systemIdle: 30.0, sinceLastSynthetic: 30.1))
        XCTAssertFalse(JiggleMath.isRealUserInput(systemIdle: 29.9, sinceLastSynthetic: 30.0))
    }

    func testNewerEventThanNudgeIsUserInput() {
        XCTAssertTrue(JiggleMath.isRealUserInput(systemIdle: 0.2, sinceLastSynthetic: 30.0))
        XCTAssertTrue(JiggleMath.isRealUserInput(systemIdle: 5.0, sinceLastSynthetic: 30.0))
    }
}
