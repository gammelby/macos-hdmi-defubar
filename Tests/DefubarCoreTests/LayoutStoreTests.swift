import XCTest
@testable import DefubarCore

final class LayoutStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("defubar-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    var storeURL: URL { dir.appendingPathComponent("layouts.json") }

    func layout(names: String...) -> SavedLayout {
        SavedLayout(from: names.enumerated().map { i, name in
            DisplaySnapshot(
                displayID: UInt32(i),
                fingerprint: DisplayFingerprint(vendor: 1, model: 2, serial: UInt32(i + 1), isBuiltin: false),
                name: name, pointWidth: 100, pointHeight: 100, pixelWidth: 200, pixelHeight: 200,
                refresh: 60, originX: i * 100, originY: 0, isMain: i == 0)
        })
    }

    func testMissingFileMeansEmptyStore() {
        let store = LayoutStore(url: storeURL)
        XCTAssertNil(store.layout(forSetKey: "x"))
        XCTAssertFalse(store.recoveredFromCorruption)
        XCTAssertEqual(store.allSetKeys(), [])
    }

    func testSaveAndReloadRoundTrip() {
        let store = LayoutStore(url: storeURL)
        let l = layout(names: "A", "B")
        store.save(l, forSetKey: "key1")
        let reloaded = LayoutStore(url: storeURL)
        XCTAssertEqual(reloaded.layout(forSetKey: "key1"), l)
        XCTAssertEqual(reloaded.allSetKeys(), ["key1"])
    }

    func testDeleteRemovesLayout() {
        let store = LayoutStore(url: storeURL)
        store.save(layout(names: "A"), forSetKey: "key1")
        store.delete(forSetKey: "key1")
        XCTAssertNil(LayoutStore(url: storeURL).layout(forSetKey: "key1"))
    }

    func testCorruptFileIsMovedAsideAndStoreStartsEmpty() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json {".utf8).write(to: storeURL)
        let store = LayoutStore(url: storeURL)
        XCTAssertTrue(store.recoveredFromCorruption)
        XCTAssertEqual(store.allSetKeys(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path + ".corrupt"))
    }
}
