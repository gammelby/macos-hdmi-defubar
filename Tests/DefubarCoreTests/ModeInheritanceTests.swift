import XCTest
@testable import DefubarCore

final class ModeInheritanceTests: XCTestCase {
    func snap(name: String, vendor: UInt32 = 19501, model: UInt32 = 29234, serial: UInt32 = 1536,
              builtin: Bool = false, pointW: Int = 1920, pointH: Int = 1080,
              pixelW: Int = 1920, pixelH: Int = 1080, refresh: Double = 60,
              x: Int = 0, y: Int = 0) -> DisplaySnapshot {
        DisplaySnapshot(
            displayID: serial, fingerprint: DisplayFingerprint(vendor: vendor, model: model,
                                                               serial: serial, isBuiltin: builtin),
            name: name, pointWidth: pointW, pointHeight: pointH,
            pixelWidth: pixelW, pixelHeight: pixelH, refresh: refresh,
            originX: x, originY: y, isMain: builtin)
    }

    func testInheritsModeByMatchKeyAcrossModelChurn() {
        // Saved under model 29233, current reports 29234; same serial.
        let savedTriple = SavedLayout(from: [
            snap(name: "MacBook", vendor: 1552, model: 41041, serial: 99, builtin: true,
                 pointW: 2056, pointH: 1329, pixelW: 4112, pixelH: 2658, refresh: 120),
            snap(name: "Odyssey", model: 29233, pointW: 3360, pointH: 1890,
                 pixelW: 6720, pixelH: 3780, refresh: 60, x: 501, y: -1890),
        ])
        let current = [
            snap(name: "MacBook", vendor: 1552, model: 41041, serial: 99, builtin: true,
                 pointW: 1728, pointH: 1117, pixelW: 3456, pixelH: 2234, refresh: 120),
            snap(name: "Odyssey", model: 29234, pointW: 1920, pointH: 1080, x: -1920, y: -1080),
        ]
        let synthetic = ModeInheritance.syntheticLayout(for: current, from: [savedTriple])
        XCTAssertNotNil(synthetic)
        let odyssey = synthetic!.displays.first { !$0.fingerprint.isBuiltin }!
        XCTAssertEqual(odyssey.pointWidth, 3360)
        XCTAssertEqual(odyssey.pixelWidth, 6720)
        let mac = synthetic!.displays.first { $0.fingerprint.isBuiltin }!
        XCTAssertEqual(mac.pointWidth, 2056)
    }

    func testKeepsCurrentOriginsAndMain() {
        let saved = SavedLayout(from: [
            snap(name: "Odyssey", model: 29233, pointW: 3360, pointH: 1890, x: 501, y: -1890),
        ])
        let current = [snap(name: "Odyssey", model: 29234, pointW: 1920, pointH: 1080,
                            x: -1920, y: -1080)]
        let synthetic = ModeInheritance.syntheticLayout(for: current, from: [saved])
        XCTAssertEqual(synthetic?.displays[0].originX, -1920)
        XCTAssertEqual(synthetic?.displays[0].originY, -1080)
    }

    func testReturnsNilWhenNothingDiffersOrMatches() {
        let saved = SavedLayout(from: [snap(name: "Odyssey", pointW: 1920, pointH: 1080)])
        let sameMode = [snap(name: "Odyssey", pointW: 1920, pointH: 1080, x: 100)]
        XCTAssertNil(ModeInheritance.syntheticLayout(for: sameMode, from: [saved]))
        let unknownDisplay = [snap(name: "Other", vendor: 1, serial: 42)]
        XCTAssertNil(ModeInheritance.syntheticLayout(for: unknownDisplay, from: [saved]))
    }

    func testPrefersLayoutSharingMoreDisplaysWithCurrentSet() {
        let pairWithOdyssey = SavedLayout(from: [
            snap(name: "MacBook", vendor: 1552, model: 41041, serial: 99, builtin: true,
                 pointW: 2056, pointH: 1329),
            snap(name: "Odyssey", pointW: 3360, pointH: 1890),
        ])
        let odysseyAloneOtherMode = SavedLayout(from: [
            snap(name: "Odyssey", pointW: 2560, pointH: 1440),
        ])
        let current = [
            snap(name: "MacBook", vendor: 1552, model: 41041, serial: 99, builtin: true,
                 pointW: 2056, pointH: 1329),
            snap(name: "Odyssey", pointW: 1920, pointH: 1080),
        ]
        // The pair layout shares two displays with the current set, the
        // single-display layout only one; the pair's mode must win.
        let synthetic = ModeInheritance.syntheticLayout(
            for: current, from: [odysseyAloneOtherMode, pairWithOdyssey])
        let odyssey = synthetic!.displays.first { !$0.fingerprint.isBuiltin }!
        XCTAssertEqual(odyssey.pointWidth, 3360)
    }
}
