import XCTest
@testable import DefubarCore

final class DisplayFingerprintTests: XCTestCase {
    func testMatchKeyIncludesSerialWhenPresent() {
        let fp = DisplayFingerprint(vendor: 7789, model: 30471, serial: 502218, isBuiltin: false)
        XCTAssertEqual(fp.matchKey, "e-7789-30471-502218")
    }

    func testMatchKeyOmitsZeroSerial() {
        let fp = DisplayFingerprint(vendor: 7789, model: 30471, serial: 0, isBuiltin: false)
        XCTAssertEqual(fp.matchKey, "e-7789-30471")
    }

    func testBuiltinPrefix() {
        let fp = DisplayFingerprint(vendor: 1552, model: 41041, serial: 1, isBuiltin: true)
        XCTAssertEqual(fp.matchKey, "b-1552-41041-1")
    }

    func testSetKeyIsOrderIndependent() {
        let a = DisplayFingerprint(vendor: 1, model: 2, serial: 3, isBuiltin: true)
        let b = DisplayFingerprint(vendor: 4, model: 5, serial: 6, isBuiltin: false)
        XCTAssertEqual(DisplayFingerprint.setKey(for: [a, b]),
                       DisplayFingerprint.setKey(for: [b, a]))
        XCTAssertEqual(DisplayFingerprint.setKey(for: [a, b]), "b-1-2-3+e-4-5-6")
    }

    func testSetKeyKeepsDuplicates() {
        let a = DisplayFingerprint(vendor: 4, model: 5, serial: 0, isBuiltin: false)
        XCTAssertEqual(DisplayFingerprint.setKey(for: [a, a]), "e-4-5+e-4-5")
    }
}
