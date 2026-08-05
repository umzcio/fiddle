import XCTest
import IOKit.pwr_mgt
@testable import Fiddle

final class PowerAssertionTests: XCTestCase {
    func testKindMapsToIOPMType() {
        XCTAssertEqual(PowerAssertion.Kind.displaySleep.ioType, kIOPMAssertionTypePreventUserIdleDisplaySleep)
        XCTAssertEqual(PowerAssertion.Kind.systemSleep.ioType, kIOPMAssertionTypePreventUserIdleSystemSleep)
    }

    func testAcquireSetsActiveAndReleaseClearsIt() throws {
        let assertion = PowerAssertion()
        assertion.acquire()
        try XCTSkipIf(!assertion.active, "IOKit refused the assertion in this environment")
        XCTAssertTrue(assertion.active)
        assertion.release()
        XCTAssertFalse(assertion.active)
    }

    func testAcquireIsIdempotent() throws {
        let assertion = PowerAssertion()
        assertion.acquire()
        try XCTSkipIf(!assertion.active, "IOKit refused the assertion in this environment")
        assertion.acquire()
        XCTAssertTrue(assertion.active)
        assertion.release()
        XCTAssertFalse(assertion.active)
    }

    func testReleaseWithoutAcquireIsSafe() {
        let assertion = PowerAssertion()
        assertion.release()
        XCTAssertFalse(assertion.active)
    }

    func testDoubleReleaseIsSafe() throws {
        let assertion = PowerAssertion()
        assertion.acquire()
        try XCTSkipIf(!assertion.active, "IOKit refused the assertion in this environment")
        assertion.release()
        assertion.release()
        XCTAssertFalse(assertion.active)
    }
}
