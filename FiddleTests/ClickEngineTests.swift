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
}
