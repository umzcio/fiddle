import XCTest
import IOKit.pwr_mgt
@testable import Fiddle

final class PowerAssertionTests: XCTestCase {
    func testKindMapsToIOPMType() {
        XCTAssertEqual(PowerAssertion.Kind.displaySleep.ioType, kIOPMAssertionTypePreventUserIdleDisplaySleep)
        XCTAssertEqual(PowerAssertion.Kind.systemSleep.ioType, kIOPMAssertionTypePreventUserIdleSystemSleep)
    }
}
