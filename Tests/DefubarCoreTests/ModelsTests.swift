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

    static func named(_ name: String, builtin: Bool = false, serial: UInt32 = 1) -> DisplaySnapshot {
        DisplaySnapshot(
            displayID: serial,
            fingerprint: DisplayFingerprint(vendor: 10, model: 20, serial: serial, isBuiltin: builtin),
            name: name, pointWidth: 1920, pointHeight: 1080,
            pixelWidth: 3840, pixelHeight: 2160, refresh: 60,
            originX: Int(serial) * 100, originY: 0, isMain: builtin)
    }

    func testDerivedNameShowsBuiltinAsMacBookAndSortsItFirst() {
        let layout = SavedLayout(from: [
            Self.named("LG HDR 4K", serial: 2),
            Self.named("Built-in Retina Display", builtin: true, serial: 1),
        ])
        XCTAssertEqual(layout.derivedName, "MacBook + LG HDR 4K")
    }

    func testDerivedNameSortsExternalsAlphabetically() {
        let layout = SavedLayout(from: [
            Self.named("Odyssey G70B", serial: 3),
            Self.named("LG HDR 4K", serial: 2),
        ])
        XCTAssertEqual(layout.derivedName, "LG HDR 4K + Odyssey G70B")
    }

    func testDerivedNameCollapsesDuplicates() {
        let layout = SavedLayout(from: [
            Self.named("DELL U2720Q", serial: 0),
            Self.named("DELL U2720Q", serial: 0),
            Self.named("MacBook thing", builtin: true, serial: 1),
        ])
        XCTAssertEqual(layout.derivedName, "MacBook + 2× DELL U2720Q")
    }

    func testDisplayLabelPrefersNonEmptyCustomName() {
        var layout = SavedLayout(from: [Self.named("LG HDR 4K")])
        XCTAssertEqual(layout.displayLabel, "LG HDR 4K")
        layout.customName = "Home desk"
        XCTAssertEqual(layout.displayLabel, "Home desk")
        layout.customName = ""
        XCTAssertEqual(layout.displayLabel, "LG HDR 4K")
    }

    func testSavedLayoutCodableRoundTrip() throws {
        let layout = SavedLayout(from: [Self.snap(), Self.snap(id: 2, serial: 101, x: 1920)])
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(SavedLayout.self, from: data)
        XCTAssertEqual(decoded, layout)
    }
}
