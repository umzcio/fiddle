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

    // One nudge must actually reach the mover. keepAwake is false so the test
    // does not take a real IOKit power assertion, and idleOnly is false so the
    // nudge is not suppressed by real system idle time.
    func testJigglerNudgesTheCursor() {
        let mover = RecordingMover()
        mover.current = CGPoint(x: 100, y: 100)
        let engine = JiggleEngine(mover: mover)
        engine.start(config: JigglerConfig(intervalSec: 1, distancePx: 40,
                                           mode: .visible, keepAwake: false, idleOnly: false))
        waitUntil(timeout: 4) { !mover.moves.isEmpty }
        engine.stop()
        XCTAssertFalse(mover.moves.isEmpty)
        XCTAssertNotEqual(mover.moves.first, CGPoint(x: 100, y: 100))
    }

    // Zen mode must return the cursor, so the pointer does not walk across the
    // screen over hours. The restore is the second move of the pair.
    func testZenModeReturnsTheCursor() {
        let mover = RecordingMover()
        mover.current = CGPoint(x: 100, y: 100)
        let engine = JiggleEngine(mover: mover)
        engine.start(config: JigglerConfig(intervalSec: 1, distancePx: 40,
                                           mode: .zen, keepAwake: false, idleOnly: false))
        waitUntil(timeout: 4) { mover.moves.count >= 2 }
        engine.stop()
        XCTAssertGreaterThanOrEqual(mover.moves.count, 2)
        XCTAssertEqual(mover.moves.last, CGPoint(x: 100, y: 100))
    }

    func testAntiAFKNudgesTheCursor() {
        let mover = RecordingMover()
        mover.current = CGPoint(x: 50, y: 50)
        let engine = AntiAFKEngine(mover: mover)
        engine.start(config: AntiAFKConfig(intervalSec: 1, distancePx: 30, keepAwake: false))
        waitUntil(timeout: 4) { !mover.moves.isEmpty }
        engine.stop()
        XCTAssertFalse(mover.moves.isEmpty)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}

/// Thread-safe mock: the jiggle engines move from their own queue.
///
/// `move(to:)` also updates `current`, unlike a naive recorder that only
/// appends to a log. JiggleEngine's zen-mode restore path re-reads
/// `mover.location()` ~40ms after the nudge and only restores if the cursor
/// is still where it was just moved to (so it does not yank a cursor the
/// user has since moved). Without tracking the move here, that guard would
/// never pass and the restore would never be observed.
final class RecordingMover: CursorMoving {
    private let lock = NSLock()
    private var storage: [CGPoint] = []
    private var loc = CGPoint.zero

    var current: CGPoint {
        get { lock.lock(); defer { lock.unlock() }; return loc }
        set { lock.lock(); loc = newValue; lock.unlock() }
    }
    var moves: [CGPoint] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
    func location() -> CGPoint { current }
    func move(to point: CGPoint) {
        lock.lock(); storage.append(point); loc = point; lock.unlock()
    }
}
