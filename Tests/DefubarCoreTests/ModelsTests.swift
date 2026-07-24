import XCTest
@testable import DefubarCore

final class ModelsTests: XCTestCase {
    static func snap(id: UInt32 = 1, serial: UInt32 = 100, x: Int = 0, y: Int = 0) -> DisplaySnapshot {
        DisplaySnapshot(
            displayID: id,
            fingerprint: DisplayFingerprint(vendor: 10, model: 20, serial: serial, isBuiltin: false),
            name: "Test Display",
            pointWidth: 1920, pointHeight: 1080,
            pixelWidth: 3840, pixelHeight: 2160,
            refresh: 60.0,
            originX: x, originY: y,
            isMain: x == 0 && y == 0)
    }

    func testSavedDisplayFromSnapshotDropsDisplayID() {
        let s = Self.snap(id: 42, x: 100, y: 200)
        let saved = SavedDisplay(from: s)
        XCTAssertEqual(saved.fingerprint, s.fingerprint)
        XCTAssertEqual(saved.name, "Test Display")
        XCTAssertEqual(saved.originX, 100)
        XCTAssertEqual(saved.originY, 200)
        XCTAssertEqual(saved.pixelWidth, 3840)
        XCTAssertFalse(saved.isMain)
    }

    func testSavedLayoutCodableRoundTrip() throws {
        let layout = SavedLayout(from: [Self.snap(), Self.snap(id: 2, serial: 101, x: 1920)])
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(SavedLayout.self, from: data)
        XCTAssertEqual(decoded, layout)
    }
}
