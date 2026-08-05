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

    // MARK: - FiddleController.capped

    private func macro(_ id: String, stepCount: Int) -> Macro {
        Macro(id: id, name: id, steps: (0..<stepCount).map { wait($0) })
    }

    @MainActor
    func testCappedUnderBudgetPassesThroughUnchanged() {
        let macros = [macro("a", stepCount: 10), macro("b", stepCount: 20)]
        let (result, truncated) = FiddleController.capped(macros, budget: 100)
        XCTAssertFalse(truncated)
        XCTAssertEqual(result, macros)
    }

    @MainActor
    func testCappedOverBudgetCutToExactlyBudgetTotalStepsPreservingOrder() {
        let macros = [macro("a", stepCount: 6), macro("b", stepCount: 6), macro("c", stepCount: 6)]
        let (result, truncated) = FiddleController.capped(macros, budget: 10)
        XCTAssertTrue(truncated)
        XCTAssertEqual(result.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(result.reduce(0) { $0 + $1.steps.count }, 10)
        XCTAssertEqual(result[0].steps.count, 6)
        XCTAssertEqual(result[1].steps.count, 4)
        XCTAssertEqual(result[2].steps.count, 0)
        // Order of surviving steps is preserved (earliest steps kept).
        XCTAssertEqual(result[0].steps, macros[0].steps)
        XCTAssertEqual(result[1].steps, Array(macros[1].steps.prefix(4)))
    }

    @MainActor
    func testCappedSingleMacroLargerThanWholeBudgetKeepsFirstNSteps() {
        let macros = [macro("a", stepCount: 50)]
        let (result, truncated) = FiddleController.capped(macros, budget: 10)
        XCTAssertTrue(truncated)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "a")
        XCTAssertEqual(result[0].steps.count, 10)
        XCTAssertEqual(result[0].steps, Array(macros[0].steps.prefix(10)))
    }

    @MainActor
    func testCappedEmptyLibraryIsOk() {
        let (result, truncated) = FiddleController.capped([], budget: 10)
        XCTAssertFalse(truncated)
        XCTAssertEqual(result, [])
    }
}
