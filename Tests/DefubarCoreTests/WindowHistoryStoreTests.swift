import XCTest
@testable import DefubarCore

final class WindowHistoryStoreTests: XCTestCase {
    var dir: URL!
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("defubar-history-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    var historyURL: URL { dir.appendingPathComponent("window-history.json") }
    var windowsURL: URL { dir.appendingPathComponent("windows.json") }

    func window(dx: Int = 10, title: String = "One", display: String = "e-1-s2") -> WindowSnapshot {
        WindowSnapshot(bundleID: "com.example.app", appName: "App", title: title,
                       windowID: 7, ordinal: 0,
                       displayMatchKey: display, displayIndex: 0,
                       dx: dx, dy: 20, width: 400, height: 300)
    }

    func savedDisplay(name: String, serial: UInt32, builtin: Bool = false) -> SavedDisplay {
        SavedDisplay(from: DisplaySnapshot(
            displayID: serial,
            fingerprint: DisplayFingerprint(vendor: 1, model: 1, serial: serial, isBuiltin: builtin),
            name: name, pointWidth: 100, pointHeight: 100, pixelWidth: 100, pixelHeight: 100,
            refresh: 60, originX: 0, originY: 0, isMain: builtin))
    }

    func testMissingFileMeansNoHistory() {
        let store = WindowHistoryStore(url: historyURL)
        XCTAssertEqual(store.entries(forVariantID: "v1"), [])
        XCTAssertFalse(store.recoveredFromCorruption)
    }

    func testRoundTripKeepsNewestFirst() {
        let store = WindowHistoryStore(url: historyURL)
        store.checkpoint([window(dx: 1)], forVariantID: "v1", reason: .beforeDisplayChange, at: start)
        store.checkpoint([window(dx: 2)], forVariantID: "v1", reason: .beforeRestore,
                         at: start.addingTimeInterval(60))
        let entries = WindowHistoryStore(url: historyURL).entries(forVariantID: "v1")
        XCTAssertEqual(entries.map(\.windows), [[window(dx: 2)], [window(dx: 1)]])
        XCTAssertEqual(entries.map(\.reason), [.beforeRestore, .beforeDisplayChange])
        XCTAssertEqual(entries[1].savedAt.timeIntervalSince1970,
                       start.timeIntervalSince1970, accuracy: 1)
    }

    func testEmptyArrangementIsNotWorthKeeping() {
        let store = WindowHistoryStore(url: historyURL)
        XCTAssertFalse(store.checkpoint([], forVariantID: "v1", reason: .beforeRestore, at: start))
        XCTAssertEqual(store.entries(forVariantID: "v1"), [])
    }

    func testHistoryIsCappedAtThirtyPerVariantDroppingOldest() {
        let store = WindowHistoryStore(url: historyURL)
        for index in 0..<35 {
            store.checkpoint([window(dx: index)], forVariantID: "v1", reason: .beforeRestore,
                             at: start.addingTimeInterval(TimeInterval(index)))
        }
        let entries = store.entries(forVariantID: "v1")
        XCTAssertEqual(entries.count, 30)
        XCTAssertEqual(entries.first?.windows.first?.dx, 34)
        XCTAssertEqual(entries.last?.windows.first?.dx, 5)
    }

    func testCapIsPerVariant() {
        let store = WindowHistoryStore(url: historyURL)
        store.checkpoint([window(dx: 1)], forVariantID: "v2", reason: .beforeRestore, at: start)
        for index in 2..<40 {
            store.checkpoint([window(dx: index)], forVariantID: "v1", reason: .beforeRestore, at: start)
        }
        XCTAssertEqual(store.entries(forVariantID: "v2").count, 1)
    }

    func testPeriodicCheckpointsAreAtLeastFifteenMinutesApart() {
        let store = WindowHistoryStore(url: historyURL)
        XCTAssertTrue(store.checkpoint([window(dx: 1)], forVariantID: "v1", reason: .periodic, at: start))
        XCTAssertFalse(store.checkpoint([window(dx: 2)], forVariantID: "v1", reason: .periodic,
                                        at: start.addingTimeInterval(899)))
        XCTAssertTrue(store.checkpoint([window(dx: 3)], forVariantID: "v1", reason: .periodic,
                                       at: start.addingTimeInterval(900)))
    }

    func testDisplayChangeAndRestoreCheckpointsIgnoreTheSpacing() {
        let store = WindowHistoryStore(url: historyURL)
        store.checkpoint([window(dx: 1)], forVariantID: "v1", reason: .periodic, at: start)
        XCTAssertTrue(store.checkpoint([window(dx: 2)], forVariantID: "v1", reason: .beforeDisplayChange,
                                       at: start.addingTimeInterval(1)))
        XCTAssertTrue(store.checkpoint([window(dx: 3)], forVariantID: "v1", reason: .beforeRestore,
                                       at: start.addingTimeInterval(2)))
    }

    func testSamePlacementAsNewestEntryIsSkippedEvenWithANewTitle() {
        // Terminal and browser titles change constantly; only where the
        // windows are decides whether this is a new arrangement.
        let store = WindowHistoryStore(url: historyURL)
        store.checkpoint([window(title: "One")], forVariantID: "v1", reason: .beforeRestore, at: start)
        XCTAssertFalse(store.checkpoint([window(title: "Two")], forVariantID: "v1", reason: .beforeRestore,
                                        at: start.addingTimeInterval(3600)))
    }

    func testWindowEnumerationOrderDoesNotCountAsAChange() {
        let store = WindowHistoryStore(url: historyURL)
        var second = window(dx: 500)
        second.windowID = 8
        store.checkpoint([window(), second], forVariantID: "v1", reason: .beforeRestore, at: start)
        XCTAssertFalse(store.checkpoint([second, window()], forVariantID: "v1", reason: .beforeRestore,
                                        at: start.addingTimeInterval(3600)))
    }

    func testPruneDropsVariantsThatNoLongerExist() {
        let store = WindowHistoryStore(url: historyURL)
        store.checkpoint([window()], forVariantID: "v1", reason: .beforeRestore, at: start)
        store.checkpoint([window()], forVariantID: "v2", reason: .beforeRestore, at: start)
        store.prune(keeping: ["v2"])
        let reloaded = WindowHistoryStore(url: historyURL)
        XCTAssertEqual(reloaded.entries(forVariantID: "v1"), [])
        XCTAssertEqual(reloaded.entries(forVariantID: "v2").count, 1)
    }

    func testCorruptHistoryIsMovedAsideAndLeavesRememberedWindowsAlone() throws {
        let windows = WindowStore(url: windowsURL)
        windows.save([window()], forVariantID: "v1", at: start)
        let before = try Data(contentsOf: windowsURL)
        try Data("not json {".utf8).write(to: historyURL)

        let store = WindowHistoryStore(url: historyURL)

        XCTAssertTrue(store.recoveredFromCorruption)
        XCTAssertEqual(store.entries(forVariantID: "v1"), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURL.path + ".corrupt"))
        XCTAssertEqual(try Data(contentsOf: windowsURL), before)
        XCTAssertEqual(WindowStore(url: windowsURL).snapshot(forVariantID: "v1")?.windows, [window()])
    }

    func testReadOnlyStoreNeverWrites() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json {".utf8).write(to: historyURL)
        let store = WindowHistoryStore(url: historyURL, readOnly: true)
        store.checkpoint([window()], forVariantID: "v1", reason: .beforeRestore, at: start)
        XCTAssertEqual(try Data(contentsOf: historyURL), Data("not json {".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path + ".corrupt"))
    }

    func testRecallMakesTheEntryCurrentAndCanBeUndone() throws {
        let windows = WindowStore(url: windowsURL)
        let history = WindowHistoryStore(url: historyURL)
        let good = [window(dx: 1)]
        let bad = [window(dx: 2)]
        history.checkpoint(good, forVariantID: "v1", reason: .beforeDisplayChange, at: start)
        windows.save(bad, forVariantID: "v1", at: start.addingTimeInterval(60))
        let goodEntry = try XCTUnwrap(history.entries(forVariantID: "v1").first)

        history.recall(goodEntry, forVariantID: "v1", replacing: bad, in: windows,
                       at: start.addingTimeInterval(120))

        XCTAssertEqual(windows.snapshot(forVariantID: "v1")?.windows, good)
        let undo = try XCTUnwrap(history.entries(forVariantID: "v1").first)
        XCTAssertEqual(undo.windows, bad)
        XCTAssertEqual(undo.reason, .beforeRestore)

        history.recall(undo, forVariantID: "v1", replacing: good, in: windows,
                       at: start.addingTimeInterval(180))

        XCTAssertEqual(windows.snapshot(forVariantID: "v1")?.windows, bad)
    }

    func testPlacementSummaryNamesEveryDisplayIncludingEmptyOnes() {
        // A display showing 0 is what makes a collapsed entry easy to spot.
        let displays = [savedDisplay(name: "Built-in Retina Display", serial: 1, builtin: true),
                        savedDisplay(name: "Odyssey G70B", serial: 2),
                        savedDisplay(name: "LG HDR 4K", serial: 3)]
        let entry = WindowHistoryEntry(reason: .periodic, savedAt: start, windows: [
            window(display: "b-1-s1"), window(display: "b-1-s1"), window(display: "e-1-s3"),
        ])
        XCTAssertEqual(entry.placementSummary(displays: displays),
                       "Built-in 2, Odyssey G70B 0, LG HDR 4K 1")
    }

    func testPlacementSummaryCountsWindowsOnUnknownDisplaysAsOther() {
        let entry = WindowHistoryEntry(reason: .periodic, savedAt: start,
                                       windows: [window(display: "e-9-s9")])
        XCTAssertEqual(entry.placementSummary(displays: [savedDisplay(name: "LG", serial: 3)]),
                       "LG 0, Other 1")
    }
}
