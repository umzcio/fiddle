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

    // Restarting playback must invalidate the previous worker: the old run's
    // events may not keep posting alongside the new run's.
    func testRestartInvalidatesOldWorker() {
        let poster = RecordingPoster()
        let engine = PlaybackEngine(poster: poster)
        // Run A would post nothing for 10s, then a right-click.
        let slow = [RecordedEvent(kind: .down, button: .right, x: 0, y: 0, delayMs: 10_000)]
        // Run B posts a left pair immediately.
        let fast = [
            RecordedEvent(kind: .down, button: .left, x: 1, y: 1, delayMs: 0),
            RecordedEvent(kind: .up, button: .left, x: 1, y: 1, delayMs: 0),
        ]
        engine.start(events: slow, config: RecorderConfig(repeat: .until, times: 1))
        engine.start(events: fast, config: RecorderConfig(repeat: .times, times: 1))
        waitUntil { poster.posts.count >= 2 }
        Thread.sleep(forTimeInterval: 0.2)
        // Only run B's pair; run A's stale worker posted nothing.
        XCTAssertEqual(poster.posts.count, 2)
        XCTAssertTrue(poster.posts.allSatisfy { $0.button == .left })
    }

    // An old worker finishing naturally must not tear down the run that
    // replaced it (the dead-run half of the restart race).
    func testOldWorkerCompletionDoesNotKillNewRun() {
        let poster = RecordingPoster()
        let engine = PlaybackEngine(poster: poster)
        let quick = [
            RecordedEvent(kind: .down, button: .right, x: 0, y: 0, delayMs: 0),
            RecordedEvent(kind: .up, button: .right, x: 0, y: 0, delayMs: 0),
        ]
        let looping = [
            RecordedEvent(kind: .down, button: .left, x: 1, y: 1, delayMs: 20),
            RecordedEvent(kind: .up, button: .left, x: 1, y: 1, delayMs: 0),
        ]
        engine.start(events: quick, config: RecorderConfig(repeat: .times, times: 1))
        engine.start(events: looping, config: RecorderConfig(repeat: .until, times: 1))
        // If the old worker's cleanup killed the new run, the left pair would
        // stop repeating almost immediately.
        waitUntil { poster.posts.filter { $0.button == .left }.count >= 6 }
        XCTAssertGreaterThanOrEqual(poster.posts.filter { $0.button == .left }.count, 6)
        engine.stop()
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
    func post(button: MouseButton, down: Bool, at point: CGPoint, clickState: Int) {
        lock.lock(); storage.append((button, down)); lock.unlock()
    }
    func move(to point: CGPoint) {}
}
