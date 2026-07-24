import XCTest
@testable import DefubarCore

final class SmokeTests: XCTestCase {
    func testModuleLinks() {
        _ = DisplayFingerprint(vendor: 0, model: 0, serial: 0, isBuiltin: false)
    }
}
