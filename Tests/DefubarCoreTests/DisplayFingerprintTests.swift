import XCTest
@testable import DefubarCore

final class DisplayFingerprintTests: XCTestCase {
    func testMatchKeyUsesSerialAndIgnoresModelWhenSerialPresent() {
        let fp = DisplayFingerprint(vendor: 7789, model: 30471, serial: 502218, isBuiltin: false)
        XCTAssertEqual(fp.matchKey, "e-7789-s502218")
    }

    func testMatchKeyFallsBackToModelWhenSerialIsZero() {
        let fp = DisplayFingerprint(vendor: 7789, model: 30471, serial: 0, isBuiltin: false)
        XCTAssertEqual(fp.matchKey, "e-7789-m30471")
    }

    func testBuiltinPrefix() {
        let fp = DisplayFingerprint(vendor: 1552, model: 41041, serial: 1, isBuiltin: true)
        XCTAssertEqual(fp.matchKey, "b-1552-s1")
    }

    func testModelChurnDoesNotChangeMatchKey() {
        // Some monitors (Samsung Odyssey G7 family) report a different EDID
        // product id across reconnects. Identity must survive that.
        let before = DisplayFingerprint(vendor: 19501, model: 29233, serial: 1536, isBuiltin: false)
        let after = DisplayFingerprint(vendor: 19501, model: 29234, serial: 1536, isBuiltin: false)
        XCTAssertEqual(before.matchKey, after.matchKey)
    }

    func testSetKeyIsOrderIndependent() {
        let a = DisplayFingerprint(vendor: 1, model: 2, serial: 3, isBuiltin: true)
        let b = DisplayFingerprint(vendor: 4, model: 5, serial: 6, isBuiltin: false)
        XCTAssertEqual(DisplayFingerprint.setKey(for: [a, b]),
                       DisplayFingerprint.setKey(for: [b, a]))
        XCTAssertEqual(DisplayFingerprint.setKey(for: [a, b]), "b-1-s3+e-4-s6")
    }

    func testSetKeyKeepsDuplicates() {
        let a = DisplayFingerprint(vendor: 4, model: 5, serial: 0, isBuiltin: false)
        XCTAssertEqual(DisplayFingerprint.setKey(for: [a, a]), "e-4-m5+e-4-m5")
    }
}
