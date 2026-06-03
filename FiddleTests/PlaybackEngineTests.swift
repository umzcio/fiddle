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
}
