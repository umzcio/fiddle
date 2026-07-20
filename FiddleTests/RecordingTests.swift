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

    func testRecordedEventClickStateRoundTripAndLegacyDefault() throws {
        // New field round-trips.
        let doubled = RecordedEvent(kind: .down, button: .left, x: 1, y: 1, delayMs: 0, clickState: 2)
        XCTAssertEqual(try JSONDecoder().decode(RecordedEvent.self, from: JSONEncoder().encode(doubled)).clickState, 2)
        // Recordings saved before the field existed decode to clickState 1.
        let legacy = Data(#"{"kind":"down","button":"left","x":1,"y":1,"delayMs":0}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(RecordedEvent.self, from: legacy).clickState, 1)
    }

    // A click whose press and release land on different coordinates must still
    // be importable. It previously produced "press"/"release" rows that the
    // sequencer importer matched against neither of its branches and dropped.
    func testDisplayStepsTagsLoneEventsWithKind() {
        let events = [
            RecordedEvent(kind: .down, button: .left, x: 10, y: 10, delayMs: 0),
            RecordedEvent(kind: .up,   button: .left, x: 12, y: 12, delayMs: 3),
        ]
        let steps = RecordedSequence.displaySteps(events)
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].kind, "press")
        XCTAssertEqual(steps[0].button, .left)
        XCTAssertEqual(steps[1].kind, "release")
    }

    func testDisplayStepsTagsCoalescedClick() {
        let events = [
            RecordedEvent(kind: .down, button: .right, x: 4, y: 5, delayMs: 0),
            RecordedEvent(kind: .up,   button: .right, x: 4, y: 5, delayMs: 2),
        ]
        let steps = RecordedSequence.displaySteps(events)
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].kind, "click")
        XCTAssertEqual(steps[0].button, .right)
        XCTAssertEqual(steps[0].clickType, .single)
        // The human-readable label must not regress.
        XCTAssertEqual(steps[0].label, "Right click")
    }

    func testDisplayStepsCarriesDoubleClickState() {
        let events = [
            RecordedEvent(kind: .down, button: .left, x: 1, y: 1, delayMs: 0, clickState: 2),
            RecordedEvent(kind: .up,   button: .left, x: 1, y: 1, delayMs: 1, clickState: 2),
        ]
        let steps = RecordedSequence.displaySteps(events)
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].clickType, .double)
    }

    func testDisplayStepsTagsMove() {
        let events = [RecordedEvent(kind: .move, button: .left, x: 7, y: 8, delayMs: 0)]
        XCTAssertEqual(RecordedSequence.displaySteps(events).first?.kind, "move")
    }

    func testDisplayStepDecodesWithoutNewFields() throws {
        // Older payloads had only label/x/y/delayMs.
        let legacy = Data(#"{"label":"Left click","x":1,"y":2,"delayMs":3}"#.utf8)
        let step = try JSONDecoder().decode(DisplayStep.self, from: legacy)
        XCTAssertEqual(step.kind, "click")
        XCTAssertEqual(step.button, .left)
        XCTAssertEqual(step.clickType, .single)
    }
}
