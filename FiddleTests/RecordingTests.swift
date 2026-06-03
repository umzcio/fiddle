import XCTest
import CoreGraphics
@testable import Fiddle

final class RecordingTests: XCTestCase {
    func testEventMappingCoversMouseButtons() {
        XCTAssertEqual(RecordEventMapping.event(for: .leftMouseDown)?.button, .left)
        XCTAssertEqual(RecordEventMapping.event(for: .leftMouseDown)?.kind, .down)
        XCTAssertEqual(RecordEventMapping.event(for: .leftMouseUp)?.kind, .up)
        XCTAssertEqual(RecordEventMapping.event(for: .rightMouseDown)?.button, .right)
        XCTAssertEqual(RecordEventMapping.event(for: .otherMouseUp)?.button, .middle)
    }

    func testEventMappingIgnoresNonMouse() {
        XCTAssertNil(RecordEventMapping.event(for: .keyDown))
        XCTAssertNil(RecordEventMapping.event(for: .mouseMoved))
    }

    func testDisplayStepsCoalescesClick() {
        let events = [
            RecordedEvent(kind: .down, button: .left, x: 10, y: 20, delayMs: 0),
            RecordedEvent(kind: .up,   button: .left, x: 10, y: 20, delayMs: 5),
        ]
        let steps = RecordedSequence.displaySteps(events)
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].label, "Left click")
        XCTAssertEqual(steps[0].x, 10)
        XCTAssertEqual(steps[0].delayMs, 0)
    }

    func testDisplayStepsKeepsSeparateClicks() {
        let events = [
            RecordedEvent(kind: .down, button: .left,  x: 1, y: 1, delayMs: 0),
            RecordedEvent(kind: .up,   button: .left,  x: 1, y: 1, delayMs: 4),
            RecordedEvent(kind: .down, button: .right, x: 9, y: 9, delayMs: 600),
            RecordedEvent(kind: .up,   button: .right, x: 9, y: 9, delayMs: 3),
        ]
        let steps = RecordedSequence.displaySteps(events)
        XCTAssertEqual(steps.map(\.label), ["Left click", "Right click"])
        XCTAssertEqual(steps[1].delayMs, 600)
    }

    func testDisplayStepsRendersLoneEventAsPress() {
        let events = [RecordedEvent(kind: .down, button: .left, x: 0, y: 0, delayMs: 0)]
        XCTAssertEqual(RecordedSequence.displaySteps(events).first?.label, "Left press")
    }

    func testRecordedEventAndConfigRoundTrip() throws {
        let cfg = RecorderConfig(repeat: .times, times: 7)
        let events = [RecordedEvent(kind: .down, button: .middle, x: 3, y: 4, delayMs: 12)]
        XCTAssertEqual(try JSONDecoder().decode(RecorderConfig.self, from: JSONEncoder().encode(cfg)), cfg)
        XCTAssertEqual(try JSONDecoder().decode([RecordedEvent].self, from: JSONEncoder().encode(events)), events)
    }
}
