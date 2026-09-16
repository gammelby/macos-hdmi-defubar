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

    func key(_ layout: SavedLayout) -> String {
        DisplayFingerprint.setKey(for: layout.displays.map(\.fingerprint))
    }

    // MARK: - Basics

    func testMissingFileMeansEmptyStore() {
        let store = LayoutStore(url: storeURL)
        XCTAssertNil(store.set(forSetKey: "x"))
        XCTAssertFalse(store.recoveredFromCorruption)
        XCTAssertEqual(store.allSetKeys(), [])
    }

    func testLearnAndReloadRoundTrip() {
        let store = LayoutStore(url: storeURL)
        let l = layout(names: "A", "B")
        store.learn(l)
        let reloaded = LayoutStore(url: storeURL)
        XCTAssertEqual(reloaded.activeLayout(forSetKey: key(l)), l)
        XCTAssertEqual(reloaded.allSetKeys(), [key(l)])
    }

    func testDeleteSetRemovesEverything() {
        let store = LayoutStore(url: storeURL)
        let l = layout(names: "A")
        let result = store.learn(l)
        XCTAssertEqual(store.deleteSet(forSetKey: key(l)), [result.variantID])
        XCTAssertNil(LayoutStore(url: storeURL).set(forSetKey: key(l)))
    }

    // MARK: - Variants

    func testRearrangingUpdatesTheSameVariant() {
        // Same modes, different arrangement: This is the everyday "I moved a
        // display in System Settings" case and must not create a variant.
        let store = LayoutStore(url: storeURL)
        var l = layout(names: "A", "B")
        let first = store.learn(l)
        store.renameVariant(setKey: key(l), variantID: first.variantID, to: "Desk")
        l.displays[1].originX = 5000
        let second = store.learn(l)
        XCTAssertFalse(second.isNewVariant)
        XCTAssertEqual(second.variantID, first.variantID)
        XCTAssertEqual(store.set(forSetKey: key(l))?.variants.count, 1)
        XCTAssertEqual(store.set(forSetKey: key(l))?.variants[0].customName, "Desk")
        XCTAssertEqual(store.activeLayout(forSetKey: key(l))?.displays[1].originX, 5000)
    }

    func testNewResolutionCreatesAVariantAndMakesItActive() {
        let store = LayoutStore(url: storeURL)
        var l = layout(names: "A")
        let first = store.learn(l)
        l.displays[0].pointWidth = 999
        let second = store.learn(l)
        XCTAssertTrue(second.isNewVariant)
        XCTAssertFalse(second.isNewSet)
        XCTAssertNotEqual(second.variantID, first.variantID)
        XCTAssertEqual(store.set(forSetKey: key(l))?.variants.count, 2)
        XCTAssertEqual(store.set(forSetKey: key(l))?.activeVariantID, second.variantID)
        XCTAssertEqual(store.activeLayout(forSetKey: key(l))?.displays[0].pointWidth, 999)
    }

    func testSwitchingBackReactivatesTheOriginalVariantWithoutClobbering() {
        let store = LayoutStore(url: storeURL)
        let original = layout(names: "A")
        var changed = original
        changed.displays[0].pointWidth = 999
        let first = store.learn(original)
        store.learn(changed)
        let back = store.learn(original)
        XCTAssertEqual(back.variantID, first.variantID)
        XCTAssertFalse(back.isNewVariant)
        XCTAssertEqual(store.set(forSetKey: key(original))?.variants.count, 2)
        XCTAssertEqual(store.activeLayout(forSetKey: key(original)), original)
    }

    func testSaveAsNewVariantForcesADuplicate() {
        let store = LayoutStore(url: storeURL)
        let l = layout(names: "A")
        store.learn(l)
        let forced = store.saveAsNewVariant(l)
        XCTAssertTrue(forced.isNewVariant)
        XCTAssertEqual(store.set(forSetKey: key(l))?.variants.count, 2)
        XCTAssertEqual(store.set(forSetKey: key(l))?.activeVariantID, forced.variantID)
    }

    func testDeletingTheActiveVariantPromotesAnother() {
        let store = LayoutStore(url: storeURL)
        var l = layout(names: "A")
        let first = store.learn(l)
        l.displays[0].pointWidth = 999
        let second = store.learn(l)
        XCTAssertEqual(store.deleteVariant(setKey: key(l), variantID: second.variantID),
                       [second.variantID])
        XCTAssertEqual(store.set(forSetKey: key(l))?.activeVariantID, first.variantID)
    }

    func testDeletingTheLastVariantDeletesTheSet() {
        let store = LayoutStore(url: storeURL)
        let l = layout(names: "A")
        let only = store.learn(l)
        store.deleteVariant(setKey: key(l), variantID: only.variantID)
        XCTAssertNil(store.set(forSetKey: key(l)))
        XCTAssertEqual(store.allVariantIDs(), [])
    }

    func testSetActiveVariantIgnoresUnknownIDs() {
        let store = LayoutStore(url: storeURL)
        let l = layout(names: "A")
        let only = store.learn(l)
        store.setActiveVariant(setKey: key(l), variantID: "nope")
        XCTAssertEqual(store.set(forSetKey: key(l))?.activeVariantID, only.variantID)
    }

    func testAllLayoutsReturnsEveryVariantOfEverySet() {
        let store = LayoutStore(url: storeURL)
        var l = layout(names: "A")
        store.learn(l)
        l.displays[0].pointWidth = 999
        store.learn(l)
        store.learn(layout(names: "A", "B"))
        XCTAssertEqual(store.allLayouts().count, 3)
    }

    // MARK: - Naming

    func testLearningOverAnExistingSetPreservesItsName() {
        let store = LayoutStore(url: storeURL)
        var l = layout(names: "A")
        store.learn(l)
        store.renameSet(setKey: key(l), to: "Home desk")
        l.displays[0].originX = 42
        store.learn(l)
        XCTAssertEqual(store.set(forSetKey: key(l))?.customName, "Home desk")
        XCTAssertEqual(store.activeLayout(forSetKey: key(l))?.displays[0].originX, 42)
    }

    func testRenameToWhitespaceClearsTheCustomName() {
        let store = LayoutStore(url: storeURL)
        let l = layout(names: "A")
        let result = store.learn(l)
        store.renameSet(setKey: key(l), to: "Home desk")
        store.renameSet(setKey: key(l), to: "   ")
        XCTAssertNil(store.set(forSetKey: key(l))?.customName)
        store.renameVariant(setKey: key(l), variantID: result.variantID, to: "4K")
        store.renameVariant(setKey: key(l), variantID: result.variantID, to: "")
        XCTAssertNil(store.set(forSetKey: key(l))?.variants[0].customName)
    }

    // MARK: - Migration and recovery

    private struct LayoutFileV1Fixture: Codable {
        struct LayoutV1: Codable {
            var displays: [SavedDisplay]
            var customName: String?
        }
        var version = 1
        var layouts: [String: LayoutV1]
    }

    private func writeV1Fixture(_ layouts: [String: LayoutFileV1Fixture.LayoutV1]) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(LayoutFileV1Fixture(layouts: layouts))
        try data.write(to: storeURL)
    }

    func testMigratesVersionOneIntoASingleNamedVariant() throws {
        let l = layout(names: "A", "B")
        try writeV1Fixture([key(l): .init(displays: l.displays, customName: "Home desk")])
        let store = LayoutStore(url: storeURL)
        let set = store.set(forSetKey: key(l))
        XCTAssertEqual(set?.customName, "Home desk")
        XCTAssertEqual(set?.variants.count, 1)
        // The old name named the whole set, so the variant keeps its derived one.
        XCTAssertNil(set?.variants[0].customName)
        XCTAssertEqual(store.activeLayout(forSetKey: key(l)), l)
    }

    func testVersionOneUpgradeIsWrittenBackImmediately() throws {
        // Otherwise the file keeps claiming to be version 1 until some other
        // change happens to persist it.
        let l = layout(names: "A")
        try writeV1Fixture([key(l): .init(displays: l.displays, customName: "Home desk")])
        _ = LayoutStore(url: storeURL)
        let raw = try JSONSerialization.jsonObject(
            with: Data(contentsOf: storeURL)) as? [String: Any]
        XCTAssertEqual(raw?["version"] as? Int, 2)
        XCTAssertNotNil(raw?["sets"])
        XCTAssertNil(raw?["layouts"])
    }

    func testMigratesVersionOneWithoutACustomName() throws {
        let l = layout(names: "A")
        try writeV1Fixture([key(l): .init(displays: l.displays, customName: nil)])
        let store = LayoutStore(url: storeURL)
        XCTAssertNil(store.set(forSetKey: key(l))?.customName)
        XCTAssertEqual(store.activeLayout(forSetKey: key(l)), l)
    }

    func testMigratesLegacyKeysToCanonicalSetKey() throws {
        let l = layout(names: "A", "B")
        try writeV1Fixture(["legacy-old-format-key": .init(displays: l.displays, customName: nil)])
        let store = LayoutStore(url: storeURL)
        XCTAssertEqual(store.activeLayout(forSetKey: key(l)), l)
        XCTAssertEqual(store.allSetKeys(), [key(l)])
        // Migration is persisted, not just in-memory.
        XCTAssertEqual(LayoutStore(url: storeURL).allSetKeys(), [key(l)])
    }

    func testMigrationCollisionKeepsFirstKeyInSortedOrder() throws {
        let good = layout(names: "Good")
        var bad = good
        bad.displays[0].pointWidth = 1
        // Same fingerprints, so same canonical key; sorted key order decides.
        try writeV1Fixture([
            "key-a": .init(displays: good.displays, customName: nil),
            "key-b": .init(displays: bad.displays, customName: nil),
        ])
        let store = LayoutStore(url: storeURL)
        XCTAssertEqual(store.allSetKeys(), [key(good)])
        XCTAssertEqual(store.activeLayout(forSetKey: key(good)), good)
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

final class ReadOnlyLayoutStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("defubar-readonly-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    var storeURL: URL { dir.appendingPathComponent("layouts.json") }

    func testReadOnlyStoreDoesNotUpgradeTheFile() throws {
        let fixture = """
        {"version":1,"layouts":{"legacy":{"displays":[],"customName":"Home desk"}}}
        """
        try Data(fixture.utf8).write(to: storeURL)
        let store = LayoutStore(url: storeURL, readOnly: true)
        store.learn(SavedLayout(displays: []))
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: storeURL)) as? [String: Any]
        XCTAssertEqual(raw?["version"] as? Int, 1)
        XCTAssertNotNil(raw?["layouts"])
    }

    func testReadOnlyStoreDoesNotMoveACorruptFileAside() throws {
        try Data("not json {".utf8).write(to: storeURL)
        let store = LayoutStore(url: storeURL, readOnly: true)
        XCTAssertTrue(store.recoveredFromCorruption)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path + ".corrupt"))
    }
}
