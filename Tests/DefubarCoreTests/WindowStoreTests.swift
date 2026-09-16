import XCTest
@testable import DefubarCore

final class WindowStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("defubar-window-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    var storeURL: URL { dir.appendingPathComponent("windows.json") }

    func snapshot(title: String) -> WindowSnapshot {
        WindowSnapshot(bundleID: "com.example.app", appName: "App", title: title,
                       windowID: 7, ordinal: 0,
                       displayMatchKey: "e-1-s2", displayIndex: 0,
                       dx: 10, dy: 20, width: 400, height: 300)
    }

    func testMissingFileMeansEmptyStore() {
        let store = WindowStore(url: storeURL)
        XCTAssertNil(store.snapshot(forVariantID: "v1"))
        XCTAssertFalse(store.recoveredFromCorruption)
    }

    func testRoundTripPreservesWindowsAndTimestamp() throws {
        let store = WindowStore(url: storeURL)
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(store.save([snapshot(title: "One")], forVariantID: "v1", at: when))
        let reloaded = try XCTUnwrap(WindowStore(url: storeURL).snapshot(forVariantID: "v1"))
        XCTAssertEqual(reloaded.windows, [snapshot(title: "One")])
        XCTAssertEqual(reloaded.capturedAt.timeIntervalSince1970,
                       when.timeIntervalSince1970, accuracy: 1)
    }

    func testUnchangedArrangementIsNotWrittenBack() {
        // The capture poll runs every 20 seconds; only real movement should
        // touch the disk.
        let store = WindowStore(url: storeURL)
        XCTAssertTrue(store.save([snapshot(title: "One")], forVariantID: "v1"))
        XCTAssertFalse(store.save([snapshot(title: "One")], forVariantID: "v1"))
        XCTAssertTrue(store.save([snapshot(title: "Two")], forVariantID: "v1"))
    }

    func testDeleteAndPrune() {
        let store = WindowStore(url: storeURL)
        store.save([snapshot(title: "One")], forVariantID: "v1")
        store.save([snapshot(title: "Two")], forVariantID: "v2")
        store.delete(forVariantID: "v1")
        XCTAssertNil(store.snapshot(forVariantID: "v1"))
        store.prune(keeping: [])
        XCTAssertNil(WindowStore(url: storeURL).snapshot(forVariantID: "v2"))
    }

    func testCorruptFileIsMovedAsideAndStoreStartsEmpty() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json {".utf8).write(to: storeURL)
        let store = WindowStore(url: storeURL)
        XCTAssertTrue(store.recoveredFromCorruption)
        XCTAssertNil(store.snapshot(forVariantID: "v1"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path + ".corrupt"))
    }
}
