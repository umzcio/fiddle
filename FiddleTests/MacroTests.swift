import XCTest
@testable import Fiddle

final class MacroTests: XCTestCase {
    private func click(_ b: MouseButton, _ t: ClickType, _ x: Int, _ y: Int) -> MacroStep {
        MacroStep(kind: .click, button: b, clickType: t, x: x, y: y, ms: 0)
    }
    private func wait(_ ms: Int) -> MacroStep { MacroStep(kind: .wait, button: .left, clickType: .single, x: 0, y: 0, ms: ms) }
    private func move(_ x: Int, _ y: Int) -> MacroStep { MacroStep(kind: .move, button: .left, clickType: .single, x: x, y: y, ms: 0) }

    func testWaitAccumulatesIntoNextActionDelay() {
        let events = MacroCompiler.compile([wait(500), click(.left, .single, 10, 20)])
        XCTAssertEqual(events.count, 2)            // down + up
        XCTAssertEqual(events[0].kind, .down)
        XCTAssertEqual(events[0].delayMs, 500)
        XCTAssertEqual(events[1].kind, .up)
        XCTAssertEqual(events[0].x, 10); XCTAssertEqual(events[0].y, 20)
    }

    func testSingleClickEmitsDownUp() {
        let events = MacroCompiler.compile([click(.right, .single, 1, 2)])
        XCTAssertEqual(events.map(\.kind), [.down, .up])
        XCTAssertEqual(events[0].button, .right)
        XCTAssertEqual(events[0].delayMs, 0)
    }

    func testDoubleClickEmitsTwoPairs() {
        let events = MacroCompiler.compile([click(.left, .double, 5, 5)])
        XCTAssertEqual(events.map(\.kind), [.down, .up, .down, .up])
    }

    func testDoubleClickSecondPairCarriesClickStateTwo() {
        let events = MacroCompiler.compile([click(.left, .double, 5, 5)])
        XCTAssertEqual(events.map(\.clickState), [1, 1, 2, 2])
    }

    func testSingleClickCarriesClickStateOne() {
        let events = MacroCompiler.compile([click(.left, .single, 5, 5)])
        XCTAssertEqual(events.map(\.clickState), [1, 1])
    }

    func testMoveEmitsSingleMoveEvent() {
        let events = MacroCompiler.compile([wait(100), move(7, 8)])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].kind, .move)
        XCTAssertEqual(events[0].delayMs, 100)
        XCTAssertEqual(events[0].x, 7); XCTAssertEqual(events[0].y, 8)
    }

    func testMacroCodableRoundTrip() throws {
        let macro = Macro(id: "m1", name: "Test", steps: [wait(250), click(.left, .single, 3, 4), move(9, 9)])
        let back = try JSONDecoder().decode(Macro.self, from: try JSONEncoder().encode(macro))
        XCTAssertEqual(macro, back)
    }

    func testMacroConfigRoundTrip() throws {
        let cfg = MacroConfig(macroId: "m1", repeat: .times, times: 3)
        XCTAssertEqual(try JSONDecoder().decode(MacroConfig.self, from: JSONEncoder().encode(cfg)), cfg)
    }
}
