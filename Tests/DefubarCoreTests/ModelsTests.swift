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

    func testSetDisplayLabelPrefersNonEmptyCustomName() {
        var set = LayoutSet(layout: SavedLayout(from: [Self.named("LG HDR 4K")]))
        XCTAssertEqual(set.displayLabel, "LG HDR 4K")
        set.customName = "Home desk"
        XCTAssertEqual(set.displayLabel, "Home desk")
        set.customName = ""
        XCTAssertEqual(set.displayLabel, "LG HDR 4K")
    }

    func testVariantLabelFallsBackToTheModes() {
        var variant = LayoutVariant(layout: SavedLayout(from: [Self.named("LG HDR 4K")]))
        XCTAssertEqual(variant.label, "1920×1080 @ 60")
        variant.customName = "4K mode"
        XCTAssertEqual(variant.label, "4K mode")
    }

    func testDerivedVariantNameOrdersLikeDerivedNameAndCollapses() {
        var layout = SavedLayout(from: [
            Self.named("DELL U2720Q", serial: 0),
            Self.named("DELL U2720Q", serial: 0),
            Self.named("MacBook thing", builtin: true, serial: 1),
        ])
        // The built-in comes first, then the two identical externals collapse.
        layout.displays[2].pointWidth = 3024
        layout.displays[2].pointHeight = 1964
        layout.displays[2].refresh = 120
        XCTAssertEqual(layout.derivedVariantName, "3024×1964 @ 120 + 2× 1920×1080 @ 60")
    }

    func testModeSignatureIgnoresArrangementAndDisplayOrder() {
        let a = SavedLayout(from: [Self.named("LG", serial: 2), Self.named("Odyssey", serial: 3)])
        var b = SavedLayout(from: [Self.named("Odyssey", serial: 3), Self.named("LG", serial: 2)])
        b.displays[0].originX = 9999
        b.displays[1].originY = -1080
        XCTAssertEqual(a.modeSignature, b.modeSignature)
    }

    func testModeSignatureChangesWithResolution() {
        let a = SavedLayout(from: [Self.named("LG", serial: 2)])
        var b = a
        b.displays[0].pointWidth = 2560
        XCTAssertNotEqual(a.modeSignature, b.modeSignature)
    }

    func testModeSignatureToleratesRefreshRounding() {
        let a = SavedLayout(from: [Self.named("LG", serial: 2)])
        var b = a
        b.displays[0].refresh = 59.94
        XCTAssertEqual(a.modeSignature, b.modeSignature)
    }

    func testSavedLayoutCodableRoundTrip() throws {
        let layout = SavedLayout(from: [Self.snap(), Self.snap(id: 2, serial: 101, x: 1920)])
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(SavedLayout.self, from: data)
        XCTAssertEqual(decoded, layout)
    }
}
