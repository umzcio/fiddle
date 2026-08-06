import XCTest

extension XCTestCase {
    /// Poll until `condition` is true or fail the test at `timeout`.
    /// A silent timeout would let downstream assertions pass vacuously.
    func waitUntil(timeout: TimeInterval = 2,
                   file: StaticString = #filePath, line: UInt = #line,
                   _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if !condition() {
            XCTFail("timed out after \(timeout)s waiting for condition", file: file, line: line)
        }
    }
}
