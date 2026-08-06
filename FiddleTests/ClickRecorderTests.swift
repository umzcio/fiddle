import XCTest
import CoreGraphics
@testable import Fiddle

@MainActor
final class ClickRecorderTests: XCTestCase {

    // ingest() is the test seam for everything capture() does after the
    // is-a-tap-live check: beginBuffering() resets the buffer without
    // creating a real CGEvent tap, and stop() only tap-disables when a tap
    // exists, so it always hands back whatever is in `events` even when
    // isRecording is false. That lets these tests call ingest() directly.

    func testIngestRecordsMappedEventsWithAccumulatedDelay() {
        let recorder = ClickRecorder()
        recorder.beginBuffering()
        recorder.ingest(type: .leftMouseDown, location: CGPoint(x: 10, y: 20), clickState: 1)
        Thread.sleep(forTimeInterval: 0.03)
        recorder.ingest(type: .leftMouseUp, location: CGPoint(x: 10, y: 20), clickState: 1)

        let events = recorder.stop()
        XCTAssertEqual(events.count, 2)

        XCTAssertEqual(events[0].kind, .down)
        XCTAssertEqual(events[0].button, .left)
        XCTAssertEqual(events[0].x, 10)
        XCTAssertEqual(events[0].y, 20)
        // Measured from beginBuffering()'s timestamp, not zero.
        XCTAssertGreaterThanOrEqual(events[0].delayMs, 0)
        XCTAssertLessThanOrEqual(events[0].delayMs, 500)

        XCTAssertEqual(events[1].kind, .up)
        XCTAssertGreaterThanOrEqual(events[1].delayMs, 20)
        XCTAssertLessThanOrEqual(events[1].delayMs, 500)
    }

    func testIngestHonorsExcludeClosure() {
        let recorder = ClickRecorder()
        recorder.exclude = { _ in true }
        recorder.beginBuffering()
        recorder.ingest(type: .leftMouseDown, location: CGPoint(x: 1, y: 2), clickState: 1)

        XCTAssertEqual(recorder.stop(), [])
    }

    func testIngestIgnoresUnmappedTypes() {
        let recorder = ClickRecorder()
        recorder.beginBuffering()
        recorder.ingest(type: .mouseMoved, location: CGPoint(x: 1, y: 2), clickState: 1)

        XCTAssertEqual(recorder.stop(), [])
    }

    func testIngestStopsAtCapAndFiresLimitOnceExactly() {
        let recorder = ClickRecorder()
        recorder.beginBuffering()
        var limitReachedCount = 0
        recorder.onLimitReached = { limitReachedCount += 1 }

        for _ in 0..<(ClickRecorder.maxEvents + 5) {
            recorder.ingest(type: .leftMouseDown, location: CGPoint(x: 0, y: 0), clickState: 1)
        }

        XCTAssertEqual(limitReachedCount, 1)

        let events = recorder.stop()
        XCTAssertEqual(events.count, ClickRecorder.maxEvents)
    }

    func testIsOwnDetectsTaggedEvents() throws {
        let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                             mouseCursorPosition: .zero, mouseButton: .left)
        try XCTSkipIf(event == nil, "CGEvent creation unavailable in this environment")
        let ownEvent = event!
        ownEvent.setIntegerValueField(.eventSourceUserData, value: SyntheticEvents.userDataTag)
        XCTAssertTrue(SyntheticEvents.isOwn(ownEvent))

        let untaggedEvent = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                                   mouseCursorPosition: .zero, mouseButton: .left))
        XCTAssertFalse(SyntheticEvents.isOwn(untaggedEvent))
    }
}
