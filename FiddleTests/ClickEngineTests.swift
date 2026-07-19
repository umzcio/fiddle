import XCTest
import CoreGraphics
@testable import Fiddle

final class ClickEngineLogicTests: XCTestCase {

    private func config(
        repeat repeatMode: RepeatMode = .until,
        times: Int = 0,
        position: PositionMode = .current,
        x: Int = 0,
        y: Int = 0
    ) -> ClickerConfig {
        ClickerConfig(intervalMs: 100, button: .left, clickType: .single,
                      repeat: repeatMode, times: times, position: position, x: x, y: y)
    }

    func testRepeatTimesStopsAfterN() {
        var state = ClickRunState(config: config(repeat: .times, times: 3))
        XCTAssertTrue(state.recordClick())   // 1 of 3
        XCTAssertTrue(state.recordClick())   // 2 of 3
        XCTAssertFalse(state.recordClick())  // 3 of 3 -> done
    }

    func testRepeatUntilNeverStops() {
        var state = ClickRunState(config: config(repeat: .until, times: 2))
        for _ in 0..<25 {
            XCTAssertTrue(state.recordClick())
        }
    }

    func testFixedPositionTarget() {
        let state = ClickRunState(config: config(position: .fixed, x: 12, y: 34))
        XCTAssertEqual(state.targetPoint, CGPoint(x: 12, y: 34))
    }

    func testCurrentPositionHasNoFixedTarget() {
        let state = ClickRunState(config: config(position: .current))
        XCTAssertNil(state.targetPoint)
    }

    func testButtonMapping() {
        XCTAssertEqual(ClickMapping.cgButton(.left), .left)
        XCTAssertEqual(ClickMapping.cgButton(.right), .right)
        XCTAssertEqual(ClickMapping.cgButton(.middle), .center)
    }

    func testEventTypeMapping() {
        XCTAssertEqual(ClickMapping.downType(.left), .leftMouseDown)
        XCTAssertEqual(ClickMapping.upType(.left), .leftMouseUp)
        XCTAssertEqual(ClickMapping.downType(.right), .rightMouseDown)
        XCTAssertEqual(ClickMapping.upType(.right), .rightMouseUp)
        XCTAssertEqual(ClickMapping.downType(.middle), .otherMouseDown)
        XCTAssertEqual(ClickMapping.upType(.middle), .otherMouseUp)
    }

    func testClickStateMapping() {
        XCTAssertEqual(ClickMapping.clickState(.single), 1)
        XCTAssertEqual(ClickMapping.clickState(.double), 2)
    }

    // A bounded run must post exactly `times` clicks and then stop on its own.
    func testTimesModeStopsAfterExactlyNClicks() {
        let poster = RecordingClickPoster()
        let engine = ClickEngine(poster: poster)
        engine.start(config: ClickerConfig(intervalMs: 10, button: .left, clickType: .single,
                                           repeat: .times, times: 3,
                                           position: .fixed, x: 5, y: 6))
        waitUntil { poster.clicks.count >= 3 }
        Thread.sleep(forTimeInterval: 0.15)   // well past 3 more intervals
        XCTAssertEqual(poster.clicks.count, 3)
        XCTAssertFalse(engine.isRunning)
    }

    // stop() must halt posting promptly.
    func testStopHaltsPosting() {
        let poster = RecordingClickPoster()
        let engine = ClickEngine(poster: poster)
        engine.start(config: ClickerConfig(intervalMs: 10, button: .left, clickType: .single,
                                           repeat: .until, times: 1,
                                           position: .fixed, x: 0, y: 0))
        waitUntil { poster.clicks.count >= 2 }
        engine.stop()
        let afterStop = poster.clicks.count
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertEqual(poster.clicks.count, afterStop)
    }

    // Restarting must not leave the previous timer running alongside the new
    // one, which would double the effective click rate.
    func testRestartDoesNotLeaveTwoTimersRunning() {
        let poster = RecordingClickPoster()
        let engine = ClickEngine(poster: poster)
        let config = ClickerConfig(intervalMs: 20, button: .left, clickType: .single,
                                   repeat: .until, times: 1,
                                   position: .fixed, x: 0, y: 0)
        engine.start(config: config)
        engine.start(config: config)
        Thread.sleep(forTimeInterval: 0.25)
        engine.stop()
        // ~12 ticks max for one timer over 250ms at 20ms. Two timers would
        // roughly double this. Generous bound to stay non-flaky.
        XCTAssertLessThan(poster.clicks.count, 20)
    }

    func testFixedPositionPostsAtThatPoint() {
        let poster = RecordingClickPoster()
        let engine = ClickEngine(poster: poster)
        engine.start(config: ClickerConfig(intervalMs: 10, button: .right, clickType: .double,
                                           repeat: .times, times: 1,
                                           position: .fixed, x: 42, y: 99))
        waitUntil { poster.clicks.count >= 1 }
        XCTAssertEqual(poster.clicks.first?.point, CGPoint(x: 42, y: 99))
        XCTAssertEqual(poster.clicks.first?.button, .right)
        XCTAssertEqual(poster.clicks.first?.clickType, .double)
    }

    // With position .current the engine must ask the poster where the cursor
    // is, rather than using a stored coordinate.
    func testCurrentPositionUsesPosterLocation() {
        let poster = RecordingClickPoster()
        poster.location = CGPoint(x: 7, y: 8)
        let engine = ClickEngine(poster: poster)
        engine.start(config: ClickerConfig(intervalMs: 10, button: .left, clickType: .single,
                                           repeat: .times, times: 1,
                                           position: .current, x: 999, y: 999))
        waitUntil { poster.clicks.count >= 1 }
        XCTAssertEqual(poster.clicks.first?.point, CGPoint(x: 7, y: 8))
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}

/// Thread-safe mock: ClickEngine posts from its own queue.
final class RecordingClickPoster: MouseEventPosting {
    private let lock = NSLock()
    private var storage: [(button: MouseButton, clickType: ClickType, point: CGPoint)] = []
    private var loc = CGPoint.zero

    var location: CGPoint {
        get { lock.lock(); defer { lock.unlock() }; return loc }
        set { lock.lock(); loc = newValue; lock.unlock() }
    }
    var clicks: [(button: MouseButton, clickType: ClickType, point: CGPoint)] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
    func currentLocation() -> CGPoint { location }
    func postClick(button: MouseButton, clickType: ClickType, at point: CGPoint) {
        lock.lock(); storage.append((button, clickType, point)); lock.unlock()
    }
}
