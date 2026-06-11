import XCTest
@testable import Fiddle

final class PlaybackEngineTests: XCTestCase {
    func testTimesModeStopsAfterNPasses() {
        var s = PlaybackRunState(config: RecorderConfig(repeat: .times, times: 3))
        XCTAssertTrue(s.finishPass())   // after pass 1 -> continue
        XCTAssertTrue(s.finishPass())   // after pass 2 -> continue
        XCTAssertFalse(s.finishPass())  // after pass 3 -> stop
    }

    func testTimesModeSinglePass() {
        var s = PlaybackRunState(config: RecorderConfig(repeat: .times, times: 1))
        XCTAssertFalse(s.finishPass())
    }

    func testUntilModeAlwaysContinues() {
        var s = PlaybackRunState(config: RecorderConfig(repeat: .until, times: 1))
        XCTAssertTrue(s.finishPass())
        XCTAssertTrue(s.finishPass())
    }

    // Stopping between a posted down and its up must post a compensating up,
    // so a panic mid-pair cannot leave a synthetic button logically pressed.
    func testStopMidPairReleasesPressedButton() {
        let poster = RecordingPoster()
        let engine = PlaybackEngine(poster: poster)
        let events = [
            RecordedEvent(kind: .down, button: .left, x: 10, y: 10, delayMs: 0),
            RecordedEvent(kind: .up, button: .left, x: 10, y: 10, delayMs: 5000),
        ]
        engine.start(events: events, config: RecorderConfig(repeat: .times, times: 1))
        waitUntil { poster.posts.count >= 1 }
        XCTAssertEqual(poster.posts.first?.down, true)
        engine.stop()
        waitUntil { poster.posts.count >= 2 }
        XCTAssertEqual(poster.posts.count, 2)
        XCTAssertEqual(poster.posts.last?.down, false)
        XCTAssertEqual(poster.posts.last?.button, .left)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}

/// Thread-safe mock poster: playLoop posts from its worker thread.
final class RecordingPoster: SingleMouseEventPosting {
    private let lock = NSLock()
    private var storage: [(button: MouseButton, down: Bool)] = []
    var posts: [(button: MouseButton, down: Bool)] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
    func post(button: MouseButton, down: Bool, at point: CGPoint) {
        lock.lock(); storage.append((button, down)); lock.unlock()
    }
    func move(to point: CGPoint) {}
}
