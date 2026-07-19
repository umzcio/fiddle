import XCTest
import AppKit
@testable import Fiddle

final class KeyEngineTests: XCTestCase {
    func testRunStateTimesStopsAfterN() {
        var s = KeyRunState(repeat: .times, times: 2)
        XCTAssertTrue(s.recordPress())
        XCTAssertFalse(s.recordPress())
    }

    func testRunStateSingle() {
        var s = KeyRunState(repeat: .times, times: 1)
        XCTAssertFalse(s.recordPress())
    }

    func testRunStateUntilAlwaysContinues() {
        var s = KeyRunState(repeat: .until, times: 1)
        XCTAssertTrue(s.recordPress())
        XCTAssertTrue(s.recordPress())
    }

    func testFlagsMapEachModifier() {
        XCTAssertTrue(KeyboardSynthesis.flags(from: [.command]).contains(.maskCommand))
        XCTAssertTrue(KeyboardSynthesis.flags(from: [.option]).contains(.maskAlternate))
        XCTAssertTrue(KeyboardSynthesis.flags(from: [.control]).contains(.maskControl))
        XCTAssertTrue(KeyboardSynthesis.flags(from: [.shift]).contains(.maskShift))
        XCTAssertTrue(KeyboardSynthesis.flags(from: []).isEmpty)
    }

    func testFlagsCombine() {
        let f = KeyboardSynthesis.flags(from: [.command, .shift])
        XCTAssertTrue(f.contains(.maskCommand))
        XCTAssertTrue(f.contains(.maskShift))
        XCTAssertFalse(f.contains(.maskAlternate))
    }

    func testKeyTimesModeStopsAfterNPresses() {
        let poster = RecordingKeyPoster()
        let engine = KeyEngine(poster: poster)
        engine.start(keyCode: 49, flags: [], intervalMs: 10, repeat: .times, times: 3)
        waitUntil { poster.presses.count >= 3 }
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertEqual(poster.presses.count, 3)
        XCTAssertFalse(engine.isRunning)
    }

    func testKeyStopHaltsPosting() {
        let poster = RecordingKeyPoster()
        let engine = KeyEngine(poster: poster)
        engine.start(keyCode: 49, flags: [], intervalMs: 10, repeat: .until, times: 1)
        waitUntil { poster.presses.count >= 2 }
        engine.stop()
        let afterStop = poster.presses.count
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertEqual(poster.presses.count, afterStop)
    }

    func testKeyCodeAndFlagsArePassedThrough() {
        let poster = RecordingKeyPoster()
        let engine = KeyEngine(poster: poster)
        engine.start(keyCode: 36, flags: [.maskCommand], intervalMs: 10, repeat: .times, times: 1)
        waitUntil { poster.presses.count >= 1 }
        XCTAssertEqual(poster.presses.first?.keyCode, 36)
        XCTAssertTrue(poster.presses.first?.flags.contains(.maskCommand) ?? false)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}

/// Thread-safe mock: KeyEngine posts from its own queue.
final class RecordingKeyPoster: KeyEventPosting {
    private let lock = NSLock()
    private var storage: [(keyCode: CGKeyCode, flags: CGEventFlags)] = []
    var presses: [(keyCode: CGKeyCode, flags: CGEventFlags)] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
    func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        lock.lock(); storage.append((keyCode, flags)); lock.unlock()
    }
}
