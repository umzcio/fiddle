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
}
