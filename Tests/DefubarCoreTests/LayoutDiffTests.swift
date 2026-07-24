import XCTest
@testable import DefubarCore

final class LayoutDiffTests: XCTestCase {
    func snap(id: UInt32, serial: UInt32, x: Int, y: Int = 0,
              pixelW: Int = 3840, pixelH: Int = 2160, refresh: Double = 60) -> DisplaySnapshot {
        DisplaySnapshot(
            displayID: id,
            fingerprint: DisplayFingerprint(vendor: 1, model: 2, serial: serial, isBuiltin: false),
            name: "D\(id)", pointWidth: 1920, pointHeight: 1080,
            pixelWidth: pixelW, pixelHeight: pixelH,
            refresh: refresh, originX: x, originY: y, isMain: x == 0 && y == 0)
    }

    func testIdenticalLayoutHasNoChanges() {
        let current = [snap(id: 1, serial: 10, x: 0), snap(id: 2, serial: 11, x: 1920)]
        let saved = SavedLayout(from: current)
        XCTAssertEqual(LayoutDiff.changes(saved: saved, current: current), [])
    }

    func testOriginDrift() {
        let saved = SavedLayout(from: [snap(id: 1, serial: 10, x: 0), snap(id: 2, serial: 11, x: 1920)])
        let current = [snap(id: 5, serial: 10, x: 0), snap(id: 6, serial: 11, x: -3840)]
        let changes = LayoutDiff.changes(saved: saved, current: current)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].displayID, 6)
        XCTAssertTrue(changes[0].needsOrigin)
        XCTAssertFalse(changes[0].needsMode)
        XCTAssertEqual(changes[0].target.originX, 1920)
    }

    func testModeDrift() {
        let saved = SavedLayout(from: [snap(id: 1, serial: 10, x: 0, pixelW: 3840, pixelH: 2160, refresh: 144)])
        let current = [snap(id: 9, serial: 10, x: 0, pixelW: 1920, pixelH: 1080, refresh: 60)]
        let changes = LayoutDiff.changes(saved: saved, current: current)
        XCTAssertEqual(changes.count, 1)
        XCTAssertTrue(changes[0].needsMode)
        XCTAssertFalse(changes[0].needsOrigin)
    }

    func testRefreshWithinToleranceIsNotDrift() {
        let saved = SavedLayout(from: [snap(id: 1, serial: 10, x: 0, refresh: 59.94)])
        let current = [snap(id: 2, serial: 10, x: 0, refresh: 60.0)]
        XCTAssertEqual(LayoutDiff.changes(saved: saved, current: current), [])
    }

    func testDuplicateSerialLessMonitorsPairStablyByOrigin() {
        // Two identical monitors with no serial: pair left-to-left, right-to-right.
        func dup(id: UInt32, x: Int) -> DisplaySnapshot {
            DisplaySnapshot(
                displayID: id,
                fingerprint: DisplayFingerprint(vendor: 1, model: 2, serial: 0, isBuiltin: false),
                name: "Twin", pointWidth: 1920, pointHeight: 1080,
                pixelWidth: 1920, pixelHeight: 1080, refresh: 60,
                originX: x, originY: 0, isMain: x == 0)
        }
        let saved = SavedLayout(from: [dup(id: 1, x: 0), dup(id: 2, x: 1920)])
        let current = [dup(id: 7, x: 1920), dup(id: 8, x: 0)]
        XCTAssertEqual(LayoutDiff.changes(saved: saved, current: current), [])
    }

    func testPairsIgnoresDisplayNotInSavedLayout() {
        let saved = SavedLayout(from: [snap(id: 1, serial: 10, x: 0)])
        let current = [snap(id: 1, serial: 10, x: 0), snap(id: 2, serial: 99, x: 1920)]
        XCTAssertEqual(LayoutDiff.pairs(saved: saved, current: current).count, 1)
    }
}
