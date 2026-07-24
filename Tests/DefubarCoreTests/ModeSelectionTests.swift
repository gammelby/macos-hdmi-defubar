import XCTest
@testable import DefubarCore

final class ModeSelectionTests: XCTestCase {
    func target(pointW: Int = 1920, pointH: Int = 1080, pixelW: Int = 3840, pixelH: Int = 2160,
                refresh: Double = 144) -> SavedDisplay {
        SavedDisplay(from: DisplaySnapshot(
            displayID: 1,
            fingerprint: DisplayFingerprint(vendor: 1, model: 2, serial: 3, isBuiltin: false),
            name: "T", pointWidth: pointW, pointHeight: pointH,
            pixelWidth: pixelW, pixelHeight: pixelH,
            refresh: refresh, originX: 0, originY: 0, isMain: true))
    }

    func mode(_ id: Int, pointW: Int, pointH: Int, pixelW: Int, pixelH: Int, refresh: Double) -> ModeDescriptor {
        ModeDescriptor(id: id, pointWidth: pointW, pointHeight: pointH,
                       pixelWidth: pixelW, pixelHeight: pixelH, refresh: refresh)
    }

    func testExactMatchWins() {
        let candidates = [
            mode(0, pointW: 1920, pointH: 1080, pixelW: 1920, pixelH: 1080, refresh: 144),
            mode(1, pointW: 1920, pointH: 1080, pixelW: 3840, pixelH: 2160, refresh: 144),
        ]
        let choice = ModeSelection.select(target: target(), from: candidates)
        XCTAssertEqual(choice, ModeSelection.Choice(mode: candidates[1], isExact: true))
    }

    func testRefreshToleranceCountsAsExact() {
        let candidates = [mode(0, pointW: 1920, pointH: 1080, pixelW: 3840, pixelH: 2160, refresh: 143.6)]
        XCTAssertEqual(ModeSelection.select(target: target(), from: candidates)?.isExact, true)
    }

    func testZeroRefreshMatchesAnything() {
        let candidates = [mode(0, pointW: 1920, pointH: 1080, pixelW: 3840, pixelH: 2160, refresh: 0)]
        XCTAssertEqual(ModeSelection.select(target: target(), from: candidates)?.isExact, true)
    }

    func testFallbackPrefersSamePixelDimsThenClosestRefresh() {
        let candidates = [
            mode(0, pointW: 1920, pointH: 1080, pixelW: 1920, pixelH: 1080, refresh: 144),
            mode(1, pointW: 1920, pointH: 1080, pixelW: 3840, pixelH: 2160, refresh: 60),
            mode(2, pointW: 1920, pointH: 1080, pixelW: 3840, pixelH: 2160, refresh: 120),
        ]
        let choice = ModeSelection.select(target: target(), from: candidates)
        XCTAssertEqual(choice, ModeSelection.Choice(mode: candidates[2], isExact: false))
    }

    func testNoSamePointSizeReturnsNil() {
        let candidates = [mode(0, pointW: 1280, pointH: 720, pixelW: 1280, pixelH: 720, refresh: 60)]
        XCTAssertNil(ModeSelection.select(target: target(), from: candidates))
    }
}
