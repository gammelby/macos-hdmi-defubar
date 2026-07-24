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
        let key = DisplayFingerprint.setKey(for: l.displays.map(\.fingerprint))
        store.save(l)
        let reloaded = LayoutStore(url: storeURL)
        XCTAssertEqual(reloaded.layout(forSetKey: key), l)
        XCTAssertEqual(reloaded.allSetKeys(), [key])
    }

    func testDeleteRemovesLayout() {
        let store = LayoutStore(url: storeURL)
        let l = layout(names: "A")
        let key = DisplayFingerprint.setKey(for: l.displays.map(\.fingerprint))
        store.save(l)
        store.delete(forSetKey: key)
        XCTAssertNil(LayoutStore(url: storeURL).layout(forSetKey: key))
    }

    private struct LayoutFileFixture: Codable {
        var version: Int
        var layouts: [String: SavedLayout]
    }

    func writeFixture(_ layouts: [String: SavedLayout]) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(LayoutFileFixture(version: 1, layouts: layouts))
        try data.write(to: storeURL)
    }

    func testMigratesLegacyKeysToCanonicalSetKey() throws {
        let l = layout(names: "A", "B")
        let canonical = DisplayFingerprint.setKey(for: l.displays.map(\.fingerprint))
        try writeFixture(["legacy-old-format-key": l])
        let store = LayoutStore(url: storeURL)
        XCTAssertEqual(store.layout(forSetKey: canonical), l)
        XCTAssertEqual(store.allSetKeys(), [canonical])
        // Migration is persisted, not just in-memory.
        XCTAssertEqual(LayoutStore(url: storeURL).allSetKeys(), [canonical])
    }

    func testMigrationCollisionKeepsFirstKeyInSortedOrder() throws {
        let good = layout(names: "Good")
        var bad = good
        bad.displays[0].pointWidth = 1
        // Same fingerprints, so same canonical key; sorted key order decides.
        try writeFixture(["key-a": good, "key-b": bad])
        let store = LayoutStore(url: storeURL)
        let canonical = DisplayFingerprint.setKey(for: good.displays.map(\.fingerprint))
        XCTAssertEqual(store.allSetKeys(), [canonical])
        XCTAssertEqual(store.layout(forSetKey: canonical), good)
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
