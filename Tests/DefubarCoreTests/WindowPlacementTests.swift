import XCTest
@testable import DefubarCore

final class WindowPlacementTests: XCTestCase {
    func display(serial: UInt32, x: Int, y: Int = 0,
                 width: Int = 1920, height: Int = 1080) -> DisplaySnapshot {
        DisplaySnapshot(
            displayID: serial,
            fingerprint: DisplayFingerprint(vendor: 1, model: 2, serial: serial, isBuiltin: false),
            name: "D\(serial)",
            pointWidth: width, pointHeight: height,
            pixelWidth: width * 2, pixelHeight: height * 2,
            refresh: 60, originX: x, originY: y, isMain: x == 0)
    }

    func window(handle: Int = 0, bundle: String = "com.example.app", title: String = "One",
                windowID: UInt32? = 900, ordinal: Int = 0,
                x: Int = 100, y: Int = 100, width: Int = 400, height: Int = 300) -> LiveWindow {
        LiveWindow(handle: handle, bundleID: bundle, appName: "App", title: title,
                   windowID: windowID, ordinal: ordinal,
                   x: x, y: y, width: width, height: height)
    }

    var left: DisplaySnapshot { display(serial: 1, x: 0) }
    var right: DisplaySnapshot { display(serial: 2, x: 1920) }

    // MARK: - Capture

    func testCaptureStoresPositionRelativeToTheOwningDisplay() {
        let live = window(x: 2000, y: 150)
        let saved = WindowPlacement.capture([live], displays: [left, right])
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].displayMatchKey, right.fingerprint.matchKey)
        XCTAssertEqual(saved[0].dx, 80)
        XCTAssertEqual(saved[0].dy, 150)
        XCTAssertEqual(saved[0].width, 400)
    }

    func testCapturePicksTheDisplayWithTheLargestOverlap() {
        // Straddles the seam, mostly on the right-hand display.
        let live = window(x: 1820, width: 400)
        let saved = WindowPlacement.capture([live], displays: [left, right])
        XCTAssertEqual(saved[0].displayMatchKey, right.fingerprint.matchKey)
    }

    func testCaptureDropsWindowsOffEveryDisplay() {
        let live = window(x: -5000, y: -5000)
        XCTAssertEqual(WindowPlacement.capture([live], displays: [left, right]), [])
    }

    // MARK: - Matching

    func savedWindow(from live: LiveWindow, on display: DisplaySnapshot) -> WindowSnapshot {
        WindowPlacement.capture([live], displays: [display])[0]
    }

    func testMatchesByWindowIDEvenWhenTheTitleChanged() {
        let captured = savedWindow(from: window(windowID: 42, x: 10, y: 10), on: left)
        let now = window(handle: 7, title: "A different document", windowID: 42, x: 900, y: 500)
        let moves = WindowPlacement.plan(saved: [captured], live: [now], displays: [left])
        XCTAssertEqual(moves.map(\.handle), [7])
        XCTAssertEqual(moves[0].x, 10)
        XCTAssertEqual(moves[0].y, 10)
    }

    func testFallsBackToTitleWhenTheWindowIDIsGone() {
        let captured = savedWindow(from: window(title: "Inbox", windowID: 42, x: 10, y: 10), on: left)
        // After an app relaunch the id is different, the title is not.
        let now = window(handle: 3, title: "Inbox", windowID: 77, x: 900, y: 500)
        let moves = WindowPlacement.plan(saved: [captured], live: [now], displays: [left])
        XCTAssertEqual(moves.map(\.handle), [3])
    }

    func testFallsBackToOrdinalForUntitledWindows() {
        let captured = savedWindow(from: window(title: "", windowID: nil, ordinal: 1, x: 10, y: 10),
                                   on: left)
        let now = window(handle: 5, title: "", windowID: nil, ordinal: 1, x: 900, y: 500)
        let moves = WindowPlacement.plan(saved: [captured], live: [now], displays: [left])
        XCTAssertEqual(moves.map(\.handle), [5])
    }

    func testEachLiveWindowIsUsedOnce() {
        let a = savedWindow(from: window(title: "Same", windowID: 1, ordinal: 0, x: 10, y: 10), on: left)
        let b = savedWindow(from: window(title: "Same", windowID: 2, ordinal: 1, x: 20, y: 20), on: left)
        // Both live windows lost their ids, so both fall through to the title
        // tier and must not both match the first one.
        let live = [
            window(handle: 0, title: "Same", windowID: nil, ordinal: 0, x: 800, y: 800),
            window(handle: 1, title: "Same", windowID: nil, ordinal: 1, x: 800, y: 800),
        ]
        let moves = WindowPlacement.plan(saved: [a, b], live: live, displays: [left])
        XCTAssertEqual(Set(moves.map(\.handle)), [0, 1])
    }

    func testWindowsOpenedSinceTheCaptureAreLeftAlone() {
        let captured = savedWindow(from: window(windowID: 42, x: 10, y: 10), on: left)
        let known = window(handle: 0, windowID: 42, x: 900, y: 900)
        let fresh = window(handle: 1, bundle: "com.example.other", title: "New", windowID: 99,
                           x: 500, y: 500)
        let moves = WindowPlacement.plan(saved: [captured], live: [known, fresh], displays: [left])
        XCTAssertEqual(moves.map(\.handle), [0])
    }

    // MARK: - Placement

    func testWindowAlreadyInPlaceIsNotMoved() {
        let live = window(windowID: 42, x: 10, y: 10)
        let captured = savedWindow(from: live, on: left)
        XCTAssertEqual(WindowPlacement.plan(saved: [captured], live: [live], displays: [left]), [])
    }

    func testPositionFollowsTheDisplayToItsNewOrigin() {
        let captured = savedWindow(from: window(windowID: 42, x: 2000, y: 100), on: right)
        // Same monitor, now arranged to the left of the built-in.
        let moved = display(serial: 2, x: -1920)
        let now = window(handle: 0, windowID: 42, x: 50, y: 50)
        let moves = WindowPlacement.plan(saved: [captured], live: [now], displays: [moved])
        XCTAssertEqual(moves[0].x, -1840)
        XCTAssertEqual(moves[0].y, 100)
    }

    func testRectIsShrunkAndNudgedOntoASmallerDisplay() {
        let captured = savedWindow(from: window(windowID: 42, x: 1500, y: 800, width: 400, height: 300),
                                   on: left)
        let smaller = display(serial: 1, x: 0, width: 1280, height: 800)
        let now = window(handle: 0, windowID: 42, x: 0, y: 0)
        let moves = WindowPlacement.plan(saved: [captured], live: [now], displays: [smaller])
        XCTAssertEqual(moves[0].width, 400)
        XCTAssertEqual(moves[0].height, 300)
        XCTAssertEqual(moves[0].x, 1280 - 400)
        XCTAssertEqual(moves[0].y, 800 - 300)
    }

    func testWindowsOnADisconnectedDisplayAreSkipped() {
        let captured = savedWindow(from: window(windowID: 42, x: 2000, y: 100), on: right)
        let now = window(handle: 0, windowID: 42, x: 50, y: 50)
        XCTAssertEqual(WindowPlacement.plan(saved: [captured], live: [now], displays: [left]), [])
    }
}
