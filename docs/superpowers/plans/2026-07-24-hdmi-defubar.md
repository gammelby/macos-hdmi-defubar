# hdmi-defubar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menubar app that fingerprints monitors by stable hardware identity and restores the saved resolution/arrangement when macOS assigns a churned display UUID and falls back to defaults.

**Architecture:** Two SwiftPM targets. `DefubarCore` is a pure library holding all decision logic (fingerprinting, layout models, store, mode selection, diffing and the Engine state machine) with full unit tests. The `hdmi-defubar` executable target holds the system adapters (CoreGraphics display system, reconfiguration watcher, notifications, SwiftUI MenuBarExtra) which are thin and verified manually.

**Tech Stack:** Swift 6.2 toolchain in Swift 5 language mode, SwiftPM, SwiftUI `MenuBarExtra`, CoreGraphics display APIs, UserNotifications, ServiceManagement, XCTest.

## Global Constraints

- Platform floor: macOS 13 (`platforms: [.macOS(.v13)]`), swift-tools-version 5.9.
- No external package dependencies.
- Bundle identifier: `dk.ulrik.hdmi-defubar`. Log subsystem: `dk.ulrik.hdmi-defubar`.
- Layout store path: `~/Library/Application Support/hdmi-defubar/layouts.json`.
- Timing constants: 2.0 s display-settle debounce, 10.0 s learner stability window, 5.0 s self-caused suppression window after an apply.
- Refresh rates compare equal within 0.5 Hz; a refresh of 0 on either side matches anything.
- Restore is capped structurally at one attempt per settled topology change.
- User-visible copy (notifications, menu items, README): no em-dashes and no Oxford comma.

---

### Task 1: SwiftPM scaffold

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/DefubarCore/DisplayFingerprint.swift` (placeholder content replaced in Task 2)
- Create: `Sources/hdmi-defubar/main.swift` (placeholder content replaced in Task 10)
- Test: `Tests/DefubarCoreTests/SmokeTests.swift`

**Interfaces:**
- Produces: library module `DefubarCore`, executable `hdmi-defubar`, test target `DefubarCoreTests`.

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "hdmi-defubar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DefubarCore"),
        .executableTarget(name: "hdmi-defubar", dependencies: ["DefubarCore"]),
        .testTarget(name: "DefubarCoreTests", dependencies: ["DefubarCore"]),
    ]
)
```

- [ ] **Step 2: Write .gitignore**

```
.build/
build/
.DS_Store
.swiftpm/
```

- [ ] **Step 3: Write placeholder sources**

`Sources/DefubarCore/DisplayFingerprint.swift`:

```swift
// Replaced in Task 2.
public enum DefubarCoreMarker {}
```

`Sources/hdmi-defubar/main.swift`:

```swift
import DefubarCore
print("hdmi-defubar placeholder")
```

`Tests/DefubarCoreTests/SmokeTests.swift`:

```swift
import XCTest
@testable import DefubarCore

final class SmokeTests: XCTestCase {
    func testModuleLinks() {
        _ = DefubarCoreMarker.self
    }
}
```

- [ ] **Step 4: Verify build and test**

Run: `swift test`
Expected: `Test Suite 'All tests' passed`, 1 test.

Run: `swift run hdmi-defubar`
Expected: prints `hdmi-defubar placeholder`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "feat: SwiftPM scaffold with core library, executable and test targets"
```

---

### Task 2: Display fingerprinting

**Files:**
- Modify: `Sources/DefubarCore/DisplayFingerprint.swift` (replace placeholder)
- Test: `Tests/DefubarCoreTests/DisplayFingerprintTests.swift`

**Interfaces:**
- Produces: `DisplayFingerprint(vendor: UInt32, model: UInt32, serial: UInt32, isBuiltin: Bool)`, `var matchKey: String`, `static func setKey(for: [DisplayFingerprint]) -> String`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import DefubarCore

final class DisplayFingerprintTests: XCTestCase {
    func testMatchKeyIncludesSerialWhenPresent() {
        let fp = DisplayFingerprint(vendor: 7789, model: 30471, serial: 502218, isBuiltin: false)
        XCTAssertEqual(fp.matchKey, "e-7789-30471-502218")
    }

    func testMatchKeyOmitsZeroSerial() {
        let fp = DisplayFingerprint(vendor: 7789, model: 30471, serial: 0, isBuiltin: false)
        XCTAssertEqual(fp.matchKey, "e-7789-30471")
    }

    func testBuiltinPrefix() {
        let fp = DisplayFingerprint(vendor: 1552, model: 41041, serial: 1, isBuiltin: true)
        XCTAssertEqual(fp.matchKey, "b-1552-41041-1")
    }

    func testSetKeyIsOrderIndependent() {
        let a = DisplayFingerprint(vendor: 1, model: 2, serial: 3, isBuiltin: true)
        let b = DisplayFingerprint(vendor: 4, model: 5, serial: 6, isBuiltin: false)
        XCTAssertEqual(DisplayFingerprint.setKey(for: [a, b]),
                       DisplayFingerprint.setKey(for: [b, a]))
        XCTAssertEqual(DisplayFingerprint.setKey(for: [a, b]), "b-1-2-3+e-4-5-6")
    }

    func testSetKeyKeepsDuplicates() {
        let a = DisplayFingerprint(vendor: 4, model: 5, serial: 0, isBuiltin: false)
        XCTAssertEqual(DisplayFingerprint.setKey(for: [a, a]), "e-4-5+e-4-5")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DisplayFingerprintTests`
Expected: compile error, `DisplayFingerprint` not found.

- [ ] **Step 3: Implement**

Replace `Sources/DefubarCore/DisplayFingerprint.swift`:

```swift
import Foundation

/// Stable hardware identity of a display, independent of the churned
/// WindowServer display UUID.
public struct DisplayFingerprint: Codable, Equatable, Hashable {
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var isBuiltin: Bool

    public init(vendor: UInt32, model: UInt32, serial: UInt32, isBuiltin: Bool) {
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.isBuiltin = isBuiltin
    }

    /// Matching identity. Serial 0 means "not exposed" and is omitted so the
    /// fingerprint degrades to vendor + model.
    public var matchKey: String {
        let prefix = isBuiltin ? "b" : "e"
        let base = "\(prefix)-\(vendor)-\(model)"
        return serial != 0 ? "\(base)-\(serial)" : base
    }

    /// Key identifying a set of simultaneously connected displays.
    public static func setKey(for fingerprints: [DisplayFingerprint]) -> String {
        fingerprints.map(\.matchKey).sorted().joined(separator: "+")
    }
}
```

Also delete `DefubarCoreMarker` usage: update `Tests/DefubarCoreTests/SmokeTests.swift` to:

```swift
import XCTest
@testable import DefubarCore

final class SmokeTests: XCTestCase {
    func testModuleLinks() {
        _ = DisplayFingerprint(vendor: 0, model: 0, serial: 0, isBuiltin: false)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DefubarCore/DisplayFingerprint.swift Tests
git commit -m "feat: display fingerprint and set key"
```

---

### Task 3: Snapshot and layout models

**Files:**
- Create: `Sources/DefubarCore/Models.swift`
- Test: `Tests/DefubarCoreTests/ModelsTests.swift`

**Interfaces:**
- Produces:
  - `DisplaySnapshot(displayID: UInt32, fingerprint: DisplayFingerprint, name: String, pointWidth: Int, pointHeight: Int, pixelWidth: Int, pixelHeight: Int, refresh: Double, originX: Int, originY: Int, isMain: Bool)` (Codable, Equatable)
  - `SavedDisplay` (same fields minus `displayID`; `init(from: DisplaySnapshot)`)
  - `SavedLayout(displays: [SavedDisplay])` (Codable, Equatable)
  - `SavedLayout.init(from snapshot: [DisplaySnapshot])`

- [ ] **Step 1: Write the failing tests**

```swift
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

    func testSavedLayoutCodableRoundTrip() throws {
        let layout = SavedLayout(from: [Self.snap(), Self.snap(id: 2, serial: 101, x: 1920)])
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(SavedLayout.self, from: data)
        XCTAssertEqual(decoded, layout)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ModelsTests`
Expected: compile error, `DisplaySnapshot` not found.

- [ ] **Step 3: Implement `Sources/DefubarCore/Models.swift`**

```swift
import Foundation

/// Current state of one online display as reported by the system.
public struct DisplaySnapshot: Codable, Equatable {
    public var displayID: UInt32
    public var fingerprint: DisplayFingerprint
    public var name: String
    public var pointWidth: Int
    public var pointHeight: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refresh: Double
    public var originX: Int
    public var originY: Int
    public var isMain: Bool

    public init(displayID: UInt32, fingerprint: DisplayFingerprint, name: String,
                pointWidth: Int, pointHeight: Int, pixelWidth: Int, pixelHeight: Int,
                refresh: Double, originX: Int, originY: Int, isMain: Bool) {
        self.displayID = displayID
        self.fingerprint = fingerprint
        self.name = name
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refresh = refresh
        self.originX = originX
        self.originY = originY
        self.isMain = isMain
    }
}

/// Desired state of one display within a saved layout.
public struct SavedDisplay: Codable, Equatable {
    public var fingerprint: DisplayFingerprint
    public var name: String
    public var pointWidth: Int
    public var pointHeight: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refresh: Double
    public var originX: Int
    public var originY: Int
    public var isMain: Bool

    public init(from snapshot: DisplaySnapshot) {
        fingerprint = snapshot.fingerprint
        name = snapshot.name
        pointWidth = snapshot.pointWidth
        pointHeight = snapshot.pointHeight
        pixelWidth = snapshot.pixelWidth
        pixelHeight = snapshot.pixelHeight
        refresh = snapshot.refresh
        originX = snapshot.originX
        originY = snapshot.originY
        isMain = snapshot.isMain
    }
}

/// Desired layout for one set of simultaneously connected displays.
public struct SavedLayout: Codable, Equatable {
    public var displays: [SavedDisplay]

    public init(displays: [SavedDisplay]) {
        self.displays = displays
    }

    public init(from snapshot: [DisplaySnapshot]) {
        displays = snapshot.map(SavedDisplay.init)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DefubarCore/Models.swift Tests/DefubarCoreTests/ModelsTests.swift
git commit -m "feat: snapshot and saved layout models"
```

---

### Task 4: Layout store

**Files:**
- Create: `Sources/DefubarCore/LayoutStore.swift`
- Test: `Tests/DefubarCoreTests/LayoutStoreTests.swift`

**Interfaces:**
- Consumes: `SavedLayout` (Task 3).
- Produces: `LayoutStore(url: URL)`, `func layout(forSetKey: String) -> SavedLayout?`, `func save(_: SavedLayout, forSetKey: String)`, `func delete(forSetKey: String)`, `func allSetKeys() -> [String]`, `var recoveredFromCorruption: Bool`, `static var defaultURL: URL`.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LayoutStoreTests`
Expected: compile error, `LayoutStore` not found.

- [ ] **Step 3: Implement `Sources/DefubarCore/LayoutStore.swift`**

```swift
import Foundation

/// JSON-file-backed store of saved layouts keyed by set key.
/// Not thread-safe; use from one queue (the app uses the main queue).
public final class LayoutStore {
    private struct LayoutFile: Codable {
        var version = 1
        var layouts: [String: SavedLayout] = [:]
    }

    public private(set) var recoveredFromCorruption = false
    private let url: URL
    private var file: LayoutFile

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hdmi-defubar/layouts.json")
    }

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url) {
            if let decoded = try? JSONDecoder().decode(LayoutFile.self, from: data) {
                file = decoded
            } else {
                file = LayoutFile()
                recoveredFromCorruption = true
                let aside = URL(fileURLWithPath: url.path + ".corrupt")
                try? FileManager.default.removeItem(at: aside)
                try? FileManager.default.moveItem(at: url, to: aside)
            }
        } else {
            file = LayoutFile()
        }
    }

    public func layout(forSetKey key: String) -> SavedLayout? {
        file.layouts[key]
    }

    public func allSetKeys() -> [String] {
        file.layouts.keys.sorted()
    }

    public func save(_ layout: SavedLayout, forSetKey key: String) {
        file.layouts[key] = layout
        persist()
    }

    public func delete(forSetKey key: String) {
        file.layouts.removeValue(forKey: key)
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(file).write(to: url, options: .atomic)
        } catch {
            // Persist failures leave the in-memory state authoritative; the
            // caller surfaces store problems via recoveredFromCorruption only.
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DefubarCore/LayoutStore.swift Tests/DefubarCoreTests/LayoutStoreTests.swift
git commit -m "feat: atomic JSON layout store with corruption recovery"
```

---

### Task 5: Mode selection

**Files:**
- Create: `Sources/DefubarCore/ModeSelection.swift`
- Test: `Tests/DefubarCoreTests/ModeSelectionTests.swift`

**Interfaces:**
- Consumes: `SavedDisplay` (Task 3).
- Produces: `ModeDescriptor(id: Int, pointWidth: Int, pointHeight: Int, pixelWidth: Int, pixelHeight: Int, refresh: Double)`, `ModeSelection.Choice(mode: ModeDescriptor, isExact: Bool)`, `ModeSelection.select(target: SavedDisplay, from: [ModeDescriptor]) -> Choice?`, `ModeSelection.refreshMatches(_:_:) -> Bool`.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ModeSelectionTests`
Expected: compile error, `ModeDescriptor` not found.

- [ ] **Step 3: Implement `Sources/DefubarCore/ModeSelection.swift`**

```swift
import Foundation

/// One candidate display mode. `id` is the caller's index into its own
/// parallel list of platform mode objects.
public struct ModeDescriptor: Equatable {
    public var id: Int
    public var pointWidth: Int
    public var pointHeight: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refresh: Double

    public init(id: Int, pointWidth: Int, pointHeight: Int,
                pixelWidth: Int, pixelHeight: Int, refresh: Double) {
        self.id = id
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refresh = refresh
    }
}

public enum ModeSelection {
    public struct Choice: Equatable {
        public var mode: ModeDescriptor
        public var isExact: Bool

        public init(mode: ModeDescriptor, isExact: Bool) {
            self.mode = mode
            self.isExact = isExact
        }
    }

    /// A refresh of 0 means "unknown" on some displays and matches anything.
    public static func refreshMatches(_ a: Double, _ b: Double) -> Bool {
        a == 0 || b == 0 || abs(a - b) <= 0.5
    }

    /// Exact match on point size, pixel size and refresh; otherwise the
    /// closest mode with the same point size; nil when no candidate has the
    /// target point size.
    public static func select(target: SavedDisplay, from candidates: [ModeDescriptor]) -> Choice? {
        if let exact = candidates.first(where: {
            $0.pointWidth == target.pointWidth && $0.pointHeight == target.pointHeight
                && $0.pixelWidth == target.pixelWidth && $0.pixelHeight == target.pixelHeight
                && refreshMatches($0.refresh, target.refresh)
        }) {
            return Choice(mode: exact, isExact: true)
        }
        let samePointSize = candidates.filter {
            $0.pointWidth == target.pointWidth && $0.pointHeight == target.pointHeight
        }
        guard !samePointSize.isEmpty else { return nil }
        let best = samePointSize.min { a, b in
            let aPixel = a.pixelWidth == target.pixelWidth && a.pixelHeight == target.pixelHeight
            let bPixel = b.pixelWidth == target.pixelWidth && b.pixelHeight == target.pixelHeight
            if aPixel != bPixel { return aPixel }
            let aDelta = abs(a.refresh - target.refresh)
            let bDelta = abs(b.refresh - target.refresh)
            if aDelta != bDelta { return aDelta < bDelta }
            return a.pixelWidth > b.pixelWidth
        }!
        return Choice(mode: best, isExact: false)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DefubarCore/ModeSelection.swift Tests/DefubarCoreTests/ModeSelectionTests.swift
git commit -m "feat: display mode selection with same-point-size fallback"
```

---

### Task 6: Layout diffing

**Files:**
- Create: `Sources/DefubarCore/LayoutDiff.swift`
- Test: `Tests/DefubarCoreTests/LayoutDiffTests.swift`

**Interfaces:**
- Consumes: `SavedLayout`, `SavedDisplay`, `DisplaySnapshot` (Task 3), `ModeSelection.refreshMatches` (Task 5).
- Produces: `DisplayChange(displayID: UInt32, target: SavedDisplay, needsMode: Bool, needsOrigin: Bool)`, `LayoutDiff.pairs(saved:current:) -> [(SavedDisplay, DisplaySnapshot)]`, `LayoutDiff.changes(saved:current:) -> [DisplayChange]`.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LayoutDiffTests`
Expected: compile error, `LayoutDiff` not found.

- [ ] **Step 3: Implement `Sources/DefubarCore/LayoutDiff.swift`**

```swift
import Foundation

/// One display whose current state differs from the saved layout.
public struct DisplayChange: Equatable {
    public var displayID: UInt32
    public var target: SavedDisplay
    public var needsMode: Bool
    public var needsOrigin: Bool

    public init(displayID: UInt32, target: SavedDisplay, needsMode: Bool, needsOrigin: Bool) {
        self.displayID = displayID
        self.target = target
        self.needsMode = needsMode
        self.needsOrigin = needsOrigin
    }
}

public enum LayoutDiff {
    /// Pairs saved displays with current displays by fingerprint match key.
    /// Duplicate keys (identical serial-less monitors) pair in origin order,
    /// which is stable but arbitrary.
    public static func pairs(saved: SavedLayout,
                             current: [DisplaySnapshot]) -> [(SavedDisplay, DisplaySnapshot)] {
        let currentByKey = Dictionary(grouping: current, by: { $0.fingerprint.matchKey })
            .mapValues { group in
                group.sorted { ($0.originX, $0.originY) < ($1.originX, $1.originY) }
            }
        let savedByKey = Dictionary(grouping: saved.displays, by: { $0.fingerprint.matchKey })
            .mapValues { group in
                group.sorted { ($0.originX, $0.originY) < ($1.originX, $1.originY) }
            }
        var result: [(SavedDisplay, DisplaySnapshot)] = []
        for (key, savedGroup) in savedByKey.sorted(by: { $0.key < $1.key }) {
            for (savedDisplay, currentDisplay) in zip(savedGroup, currentByKey[key] ?? []) {
                result.append((savedDisplay, currentDisplay))
            }
        }
        return result
    }

    /// Differences between the saved layout and the current state.
    /// Empty result means the layout already matches.
    public static func changes(saved: SavedLayout,
                               current: [DisplaySnapshot]) -> [DisplayChange] {
        pairs(saved: saved, current: current).compactMap { savedDisplay, currentDisplay in
            let needsMode = savedDisplay.pixelWidth != currentDisplay.pixelWidth
                || savedDisplay.pixelHeight != currentDisplay.pixelHeight
                || savedDisplay.pointWidth != currentDisplay.pointWidth
                || savedDisplay.pointHeight != currentDisplay.pointHeight
                || !ModeSelection.refreshMatches(savedDisplay.refresh, currentDisplay.refresh)
            let needsOrigin = savedDisplay.originX != currentDisplay.originX
                || savedDisplay.originY != currentDisplay.originY
            guard needsMode || needsOrigin else { return nil }
            return DisplayChange(displayID: currentDisplay.displayID, target: savedDisplay,
                                 needsMode: needsMode, needsOrigin: needsOrigin)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DefubarCore/LayoutDiff.swift Tests/DefubarCoreTests/LayoutDiffTests.swift
git commit -m "feat: layout diffing with fingerprint pairing"
```

---

### Task 7: Engine state machine

**Files:**
- Create: `Sources/DefubarCore/Engine.swift`
- Test: `Tests/DefubarCoreTests/EngineTests.swift`

**Interfaces:**
- Consumes: `DisplayFingerprint.setKey`, `SavedLayout`, `LayoutDiff.changes`.
- Produces:
  - `SaveReason` enum: `.baseline`, `.learned`
  - `EngineEffect` enum: `.applyLayout(SavedLayout)`, `.saveLayout(SavedLayout, reason: SaveReason)`, `.startLearnTimer`, `.cancelLearnTimer`
  - `Engine()` with `mutating func displaysSettled(_ snapshot: [DisplaySnapshot], selfCaused: Bool, savedLayout: SavedLayout?) -> [EngineEffect]` and `func learnTimerFired(_ snapshot: [DisplaySnapshot]) -> [EngineEffect]`

Behavior contract (from spec):
- Topology change (set key differs from last event, including the first event after launch): restore if a saved layout exists and differs, save a baseline if none exists, do nothing if it matches. Never start a learn timer.
- In-place change (same set key): start the learn timer. Learning happens only when the timer fires.
- Self-caused events only update internal state and cancel any learn timer.
- The one-attempt restore cap is structural: `applyLayout` can only be emitted from a topology-change event and each settled event emits at most one.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import DefubarCore

final class EngineTests: XCTestCase {
    func snap(id: UInt32, serial: UInt32, x: Int) -> DisplaySnapshot {
        DisplaySnapshot(
            displayID: id,
            fingerprint: DisplayFingerprint(vendor: 1, model: 2, serial: serial, isBuiltin: serial == 1),
            name: "D\(serial)", pointWidth: 1920, pointHeight: 1080,
            pixelWidth: 3840, pixelHeight: 2160, refresh: 60,
            originX: x, originY: 0, isMain: x == 0)
    }

    var laptopOnly: [DisplaySnapshot] { [snap(id: 1, serial: 1, x: 0)] }
    var both: [DisplaySnapshot] { [snap(id: 1, serial: 1, x: 0), snap(id: 2, serial: 7, x: 1920)] }
    var bothWrong: [DisplaySnapshot] { [snap(id: 1, serial: 1, x: 0), snap(id: 2, serial: 7, x: -3840)] }

    func testFirstEventWithNoSavedLayoutSavesBaseline() {
        var engine = Engine()
        let effects = engine.displaysSettled(both, selfCaused: false, savedLayout: nil)
        XCTAssertEqual(effects, [.cancelLearnTimer,
                                 .saveLayout(SavedLayout(from: both), reason: .baseline)])
    }

    func testTopologyChangeWithMatchingLayoutDoesNothing() {
        var engine = Engine()
        _ = engine.displaysSettled(laptopOnly, selfCaused: false, savedLayout: SavedLayout(from: laptopOnly))
        let effects = engine.displaysSettled(both, selfCaused: false, savedLayout: SavedLayout(from: both))
        XCTAssertEqual(effects, [.cancelLearnTimer])
    }

    func testTopologyChangeWithDriftedLayoutRestores() {
        var engine = Engine()
        _ = engine.displaysSettled(laptopOnly, selfCaused: false, savedLayout: SavedLayout(from: laptopOnly))
        let saved = SavedLayout(from: both)
        let effects = engine.displaysSettled(bothWrong, selfCaused: false, savedLayout: saved)
        XCTAssertEqual(effects, [.cancelLearnTimer, .applyLayout(saved)])
    }

    func testInPlaceChangeStartsLearnTimer() {
        var engine = Engine()
        _ = engine.displaysSettled(both, selfCaused: false, savedLayout: SavedLayout(from: both))
        let effects = engine.displaysSettled(bothWrong, selfCaused: false, savedLayout: SavedLayout(from: both))
        XCTAssertEqual(effects, [.startLearnTimer])
    }

    func testSelfCausedEventOnlyCancelsTimerButUpdatesState() {
        var engine = Engine()
        _ = engine.displaysSettled(laptopOnly, selfCaused: false, savedLayout: SavedLayout(from: laptopOnly))
        // Self-caused topology-looking event after our own apply.
        let effects = engine.displaysSettled(both, selfCaused: true, savedLayout: SavedLayout(from: both))
        XCTAssertEqual(effects, [.cancelLearnTimer])
        // Next in-place change is classified against the updated set key.
        let next = engine.displaysSettled(bothWrong, selfCaused: false, savedLayout: SavedLayout(from: both))
        XCTAssertEqual(next, [.startLearnTimer])
    }

    func testLearnTimerFiredSavesLearnedLayout() {
        let engine = Engine()
        let effects = engine.learnTimerFired(bothWrong)
        XCTAssertEqual(effects, [.saveLayout(SavedLayout(from: bothWrong), reason: .learned)])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EngineTests`
Expected: compile error, `Engine` not found.

- [ ] **Step 3: Implement `Sources/DefubarCore/Engine.swift`**

```swift
import Foundation

public enum SaveReason: Equatable {
    case baseline
    case learned
}

public enum EngineEffect: Equatable {
    case applyLayout(SavedLayout)
    case saveLayout(SavedLayout, reason: SaveReason)
    case startLearnTimer
    case cancelLearnTimer
}

/// Pure decision core. Feed it settled display events; it returns effects.
/// The restore cap is structural: applyLayout is only ever emitted for a
/// topology change and each settled event emits at most one.
public struct Engine {
    private var lastSetKey: String?

    public init() {}

    public mutating func displaysSettled(_ snapshot: [DisplaySnapshot],
                                         selfCaused: Bool,
                                         savedLayout: SavedLayout?) -> [EngineEffect] {
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        let isTopologyChange = setKey != lastSetKey
        lastSetKey = setKey

        if selfCaused {
            return [.cancelLearnTimer]
        }
        if isTopologyChange {
            guard let saved = savedLayout else {
                return [.cancelLearnTimer,
                        .saveLayout(SavedLayout(from: snapshot), reason: .baseline)]
            }
            if LayoutDiff.changes(saved: saved, current: snapshot).isEmpty {
                return [.cancelLearnTimer]
            }
            return [.cancelLearnTimer, .applyLayout(saved)]
        }
        return [.startLearnTimer]
    }

    public func learnTimerFired(_ snapshot: [DisplaySnapshot]) -> [EngineEffect] {
        [.saveLayout(SavedLayout(from: snapshot), reason: .learned)]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DefubarCore/Engine.swift Tests/DefubarCoreTests/EngineTests.swift
git commit -m "feat: engine state machine for restore and learn decisions"
```

---

### Task 8: Display system protocol, CoreGraphics adapter and --dump

**Files:**
- Create: `Sources/DefubarCore/DisplaySystem.swift` (protocol + ApplyResult)
- Create: `Sources/hdmi-defubar/CGDisplaySystem.swift`
- Create: `Sources/hdmi-defubar/DumpCommand.swift`
- Modify: `Sources/hdmi-defubar/main.swift`

**Interfaces:**
- Consumes: everything from Tasks 2-6.
- Produces:
  - Core: `protocol DisplaySystem { func currentSnapshot() -> [DisplaySnapshot]; func apply(_ layout: SavedLayout) -> ApplyResult }`, `ApplyResult(applied: [String], substitutions: [String], failureMessage: String?)`.
  - App: `final class CGDisplaySystem: DisplaySystem`, `enum DumpCommand { static func run() }`.

- [ ] **Step 1: Add protocol to core, `Sources/DefubarCore/DisplaySystem.swift`**

```swift
import Foundation

/// Result of applying a layout to the live displays.
public struct ApplyResult: Equatable {
    /// Names of displays that were reconfigured.
    public var applied: [String]
    /// Names of displays where the exact saved mode was unavailable and the
    /// closest same-point-size mode was used instead (or no mode change was
    /// possible at all).
    public var substitutions: [String]
    /// Non-nil when the configuration transaction failed.
    public var failureMessage: String?

    public init(applied: [String], substitutions: [String], failureMessage: String?) {
        self.applied = applied
        self.substitutions = substitutions
        self.failureMessage = failureMessage
    }
}

/// Abstraction over the platform display stack, so the decision logic stays
/// testable without CoreGraphics.
public protocol DisplaySystem {
    func currentSnapshot() -> [DisplaySnapshot]
    func apply(_ layout: SavedLayout) -> ApplyResult
}
```

- [ ] **Step 2: Verify core still builds**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 3: Implement `Sources/hdmi-defubar/CGDisplaySystem.swift`**

```swift
import AppKit
import CoreGraphics
import DefubarCore
import os

/// CoreGraphics-backed display system.
final class CGDisplaySystem: DisplaySystem {
    private let log = Logger(subsystem: "dk.ulrik.hdmi-defubar", category: "display-system")

    func currentSnapshot() -> [DisplaySnapshot] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).compactMap { id in
            guard let mode = CGDisplayCopyDisplayMode(id) else { return nil }
            let bounds = CGDisplayBounds(id)
            return DisplaySnapshot(
                displayID: id,
                fingerprint: DisplayFingerprint(
                    vendor: CGDisplayVendorNumber(id),
                    model: CGDisplayModelNumber(id),
                    serial: CGDisplaySerialNumber(id),
                    isBuiltin: CGDisplayIsBuiltin(id) != 0),
                name: Self.displayName(id),
                pointWidth: Int(bounds.width), pointHeight: Int(bounds.height),
                pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                refresh: mode.refreshRate,
                originX: Int(bounds.origin.x), originY: Int(bounds.origin.y),
                isMain: CGDisplayIsMain(id) != 0)
        }
    }

    func apply(_ layout: SavedLayout) -> ApplyResult {
        let snapshot = currentSnapshot()
        let changes = LayoutDiff.changes(saved: layout, current: snapshot)
        guard !changes.isEmpty else {
            return ApplyResult(applied: [], substitutions: [], failureMessage: nil)
        }
        var configRef: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configRef) == .success, let config = configRef else {
            return ApplyResult(applied: [], substitutions: [],
                               failureMessage: "could not begin a display configuration transaction")
        }
        var applied: [String] = []
        var substitutions: [String] = []
        for change in changes {
            let id = change.displayID
            if change.needsMode {
                let (descriptors, cgModes) = modeCandidates(for: id)
                if let choice = ModeSelection.select(target: change.target, from: descriptors) {
                    CGConfigureDisplayWithDisplayMode(config, id, cgModes[choice.mode.id], nil)
                    if !choice.isExact { substitutions.append(change.target.name) }
                    log.info("mode for \(change.target.name, privacy: .public): exact=\(choice.isExact)")
                } else {
                    substitutions.append(change.target.name)
                    log.error("no usable mode with saved point size for \(change.target.name, privacy: .public)")
                }
            }
            if change.needsOrigin {
                CGConfigureDisplayOrigin(config, id,
                                         Int32(change.target.originX), Int32(change.target.originY))
            }
            applied.append(change.target.name)
        }
        let error = CGCompleteDisplayConfiguration(config, .permanently)
        guard error == .success else {
            return ApplyResult(applied: [], substitutions: [],
                               failureMessage: "display configuration failed (CGError \(error.rawValue))")
        }
        return ApplyResult(applied: applied, substitutions: substitutions, failureMessage: nil)
    }

    private func modeCandidates(for id: CGDirectDisplayID) -> ([ModeDescriptor], [CGDisplayMode]) {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let all = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
        let usable = all.filter { $0.isUsableForDesktopGUI() }
        let descriptors = usable.enumerated().map { index, mode in
            ModeDescriptor(id: index,
                           pointWidth: mode.width, pointHeight: mode.height,
                           pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                           refresh: mode.refreshRate)
        }
        return (descriptors, usable)
    }

    private static func displayName(_ id: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id
        }
        return screen?.localizedName ?? "Display \(id)"
    }
}
```

- [ ] **Step 4: Implement `Sources/hdmi-defubar/DumpCommand.swift`**

```swift
import Foundation
import DefubarCore

/// `hdmi-defubar --dump` prints the current displays, set key and whether a
/// saved layout exists, as JSON for debugging.
enum DumpCommand {
    private struct Output: Codable {
        var setKey: String
        var displays: [DisplaySnapshot]
        var savedLayout: SavedLayout?
        var storePath: String
    }

    static func run() {
        let system = CGDisplaySystem()
        let store = LayoutStore(url: LayoutStore.defaultURL)
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        let output = Output(setKey: setKey,
                            displays: snapshot,
                            savedLayout: store.layout(forSetKey: setKey),
                            storePath: LayoutStore.defaultURL.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(output)) ?? Data()
        print(String(decoding: data, as: UTF8.self))
    }
}
```

- [ ] **Step 5: Update `Sources/hdmi-defubar/main.swift`**

```swift
import Foundation

if CommandLine.arguments.contains("--dump") {
    DumpCommand.run()
    exit(0)
}
print("hdmi-defubar: run with --dump, or wait for Task 10 for the app")
```

- [ ] **Step 6: Verify against live hardware**

Run: `swift run hdmi-defubar --dump`
Expected: JSON listing all online displays with fingerprints, a `setKey` string joining them and `savedLayout` null (nothing saved yet).

- [ ] **Step 7: Commit**

```bash
git add Sources/DefubarCore/DisplaySystem.swift Sources/hdmi-defubar
git commit -m "feat: CoreGraphics display system adapter and --dump command"
```

---

### Task 9: Watcher, notifier and coordinator

**Files:**
- Create: `Sources/hdmi-defubar/DisplayWatcher.swift`
- Create: `Sources/hdmi-defubar/Notifier.swift`
- Create: `Sources/hdmi-defubar/Coordinator.swift`

**Interfaces:**
- Consumes: `Engine`, `LayoutStore`, `DisplaySystem`, `ApplyResult`, `EngineEffect` (Tasks 4, 7, 8).
- Produces:
  - `DisplayWatcher(settleSeconds:)` with `var onSettled: () -> Void` and `func start()`
  - `Notifier` with `func requestAuthorization()`, `func post(title: String, body: String)`
  - `Coordinator(system: DisplaySystem, store: LayoutStore)`: `ObservableObject` with `@Published isPaused`, `@Published statusLines: [String]`, `@Published lastAction: String`, `@Published hasSavedLayoutForCurrentSet: Bool`, `@Published savedSetKeys: [String]`, methods `saveCurrentLayout()`, `restoreSavedLayout()`, `deleteLayout(setKey: String)`, `start()`. Main-queue only.

- [ ] **Step 1: Implement `Sources/hdmi-defubar/DisplayWatcher.swift`**

```swift
import CoreGraphics
import Foundation

/// Debounces the burst of CoreGraphics reconfiguration callbacks around a
/// connect or disconnect into one settled notification on the main queue.
final class DisplayWatcher {
    var onSettled: () -> Void = {}
    private let settleSeconds: TimeInterval
    private var pending: DispatchWorkItem?

    init(settleSeconds: TimeInterval = 2.0) {
        self.settleSeconds = settleSeconds
    }

    func start() {
        let info = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, info)
    }

    fileprivate func eventReceived() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onSettled() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleSeconds, execute: work)
    }
}

private func displayReconfigurationCallback(displayID: CGDirectDisplayID,
                                            flags: CGDisplayChangeSummaryFlags,
                                            userInfo: UnsafeMutableRawPointer?) {
    guard let userInfo else { return }
    let watcher = Unmanaged<DisplayWatcher>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async { watcher.eventReceived() }
}
```

- [ ] **Step 2: Implement `Sources/hdmi-defubar/Notifier.swift`**

```swift
import Foundation
import UserNotifications
import os

/// Posts user notifications when running from a real app bundle; falls back
/// to logging only when run as a bare executable (swift run), where
/// UNUserNotificationCenter is unavailable.
final class Notifier {
    private let canNotify = Bundle.main.bundleIdentifier != nil
    private let log = Logger(subsystem: "dk.ulrik.hdmi-defubar", category: "notifier")

    func requestAuthorization() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, error in
            if let error {
                Logger(subsystem: "dk.ulrik.hdmi-defubar", category: "notifier")
                    .error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func post(title: String, body: String) {
        log.info("notify: \(title, privacy: .public): \(body, privacy: .public)")
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 3: Implement `Sources/hdmi-defubar/Coordinator.swift`**

```swift
import Combine
import Foundation
import DefubarCore
import os

/// Wires the watcher, engine, store, display system and notifier together.
/// Main-queue only.
final class Coordinator: ObservableObject {
    @Published var isPaused = false
    @Published var statusLines: [String] = []
    @Published var lastAction = "none yet"
    @Published var hasSavedLayoutForCurrentSet = false
    @Published var savedSetKeys: [String] = []

    private var engine = Engine()
    private let system: DisplaySystem
    private let store: LayoutStore
    private let notifier = Notifier()
    private let watcher = DisplayWatcher()
    private var learnWork: DispatchWorkItem?
    private var selfCausedUntil = Date.distantPast
    private let log = Logger(subsystem: "dk.ulrik.hdmi-defubar", category: "coordinator")

    private let learnSeconds: TimeInterval = 10.0
    private let selfCausedSeconds: TimeInterval = 5.0

    init(system: DisplaySystem, store: LayoutStore) {
        self.system = system
        self.store = store
    }

    func start() {
        notifier.requestAuthorization()
        if store.recoveredFromCorruption {
            notifier.post(title: "hdmi-defubar",
                          body: "The layout store was unreadable and has been moved aside; starting fresh.")
        }
        watcher.onSettled = { [weak self] in self?.displaysSettled() }
        watcher.start()
        displaysSettled()
    }

    // MARK: - Event handling

    private func displaysSettled() {
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        let saved = store.layout(forSetKey: setKey)
        let selfCaused = Date() < selfCausedUntil
        log.info("settled: setKey=\(setKey, privacy: .public) selfCaused=\(selfCaused) hasSaved=\(saved != nil)")
        let effects = engine.displaysSettled(snapshot, selfCaused: selfCaused, savedLayout: saved)
        updateStatus(snapshot: snapshot, saved: saved)
        if isPaused {
            cancelLearnTimer()
            return
        }
        run(effects)
    }

    private func run(_ effects: [EngineEffect]) {
        for effect in effects {
            switch effect {
            case .cancelLearnTimer:
                cancelLearnTimer()
            case .startLearnTimer:
                startLearnTimer()
            case .saveLayout(let layout, let reason):
                let setKey = DisplayFingerprint.setKey(for: layout.displays.map(\.fingerprint))
                store.save(layout, forSetKey: setKey)
                lastAction = reason == .baseline ? "Saved baseline layout" : "Learned adjusted layout"
                log.info("saved layout for \(setKey, privacy: .public) (\(String(describing: reason), privacy: .public))")
                refreshDerivedState()
            case .applyLayout(let layout):
                restore(layout)
            }
        }
    }

    private func restore(_ layout: SavedLayout) {
        selfCausedUntil = Date().addingTimeInterval(selfCausedSeconds)
        let result = system.apply(layout)
        if let failure = result.failureMessage {
            lastAction = "Restore failed"
            notifier.post(title: "hdmi-defubar", body: "Could not restore the saved layout: \(failure).")
            return
        }
        lastAction = "Restored saved layout"
        var body = "\(result.applied.joined(separator: ", ")) came up with a changed configuration; restored your saved layout."
        if !result.substitutions.isEmpty {
            body += " Closest available mode was used for \(result.substitutions.joined(separator: ", "))."
        }
        notifier.post(title: "hdmi-defubar", body: body)
        refreshDerivedState()
    }

    private func startLearnTimer() {
        learnWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let snapshot = self.system.currentSnapshot()
            self.run(self.engine.learnTimerFired(snapshot))
        }
        learnWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + learnSeconds, execute: work)
    }

    private func cancelLearnTimer() {
        learnWork?.cancel()
        learnWork = nil
    }

    // MARK: - Menu actions

    func saveCurrentLayout() {
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        store.save(SavedLayout(from: snapshot), forSetKey: setKey)
        lastAction = "Saved current layout"
        refreshDerivedState()
    }

    func restoreSavedLayout() {
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        guard let saved = store.layout(forSetKey: setKey) else { return }
        restore(saved)
    }

    func deleteLayout(setKey: String) {
        store.delete(forSetKey: setKey)
        refreshDerivedState()
    }

    // MARK: - Status

    private func updateStatus(snapshot: [DisplaySnapshot], saved: SavedLayout?) {
        statusLines = snapshot.map { display in
            "\(display.name): \(display.pointWidth)x\(display.pointHeight) @ \(Int(display.refresh.rounded())) Hz"
        }
        hasSavedLayoutForCurrentSet = saved != nil
        savedSetKeys = store.allSetKeys()
    }

    private func refreshDerivedState() {
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        hasSavedLayoutForCurrentSet = store.layout(forSetKey: setKey) != nil
        savedSetKeys = store.allSetKeys()
    }
}
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: builds with no errors (Coordinator is not yet referenced by main).

- [ ] **Step 5: Commit**

```bash
git add Sources/hdmi-defubar/DisplayWatcher.swift Sources/hdmi-defubar/Notifier.swift Sources/hdmi-defubar/Coordinator.swift
git commit -m "feat: display watcher, notifier and coordinator wiring"
```

---

### Task 10: Menubar app

**Files:**
- Create: `Sources/hdmi-defubar/App.swift`
- Create: `Sources/hdmi-defubar/MenuView.swift`
- Create: `Sources/hdmi-defubar/LoginItem.swift`
- Modify: `Sources/hdmi-defubar/main.swift`

**Interfaces:**
- Consumes: `Coordinator` (Task 9), `DumpCommand` (Task 8).
- Produces: `DefubarApp` SwiftUI app with `MenuBarExtra`, `LoginItem.isAvailable/isEnabled/setEnabled(_:)`.

- [ ] **Step 1: Implement `Sources/hdmi-defubar/LoginItem.swift`**

```swift
import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService. Only available when running from a real
/// app bundle.
enum LoginItem {
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // The toggle rereads isEnabled, so a failure is self-correcting.
        }
    }
}
```

- [ ] **Step 2: Implement `Sources/hdmi-defubar/MenuView.swift`**

```swift
import AppKit
import SwiftUI

struct MenuView: View {
    @ObservedObject var coordinator: Coordinator
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        ForEach(coordinator.statusLines, id: \.self) { line in
            Text(line)
        }
        Text("Last action: \(coordinator.lastAction)")
        Divider()
        Button("Save current layout") { coordinator.saveCurrentLayout() }
        Button("Restore saved layout") { coordinator.restoreSavedLayout() }
            .disabled(!coordinator.hasSavedLayoutForCurrentSet)
        Divider()
        Toggle("Pause automatic handling", isOn: $coordinator.isPaused)
        Toggle("Launch at login", isOn: Binding(
            get: { launchAtLogin },
            set: { newValue in
                LoginItem.setEnabled(newValue)
                launchAtLogin = LoginItem.isEnabled
            }))
            .disabled(!LoginItem.isAvailable)
        Menu("Saved layouts") {
            if coordinator.savedSetKeys.isEmpty {
                Text("No saved layouts")
            }
            ForEach(coordinator.savedSetKeys, id: \.self) { setKey in
                Menu(setKey) {
                    Button("Delete") { coordinator.deleteLayout(setKey: setKey) }
                }
            }
        }
        Divider()
        Button("Quit hdmi-defubar") { NSApp.terminate(nil) }
    }
}
```

- [ ] **Step 3: Implement `Sources/hdmi-defubar/App.swift`**

```swift
import AppKit
import SwiftUI
import DefubarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menubar-only, also when running unbundled where LSUIElement
        // does not apply.
        NSApp.setActivationPolicy(.accessory)
    }
}

struct DefubarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator: Coordinator

    init() {
        let coordinator = Coordinator(system: CGDisplaySystem(),
                                      store: LayoutStore(url: LayoutStore.defaultURL))
        _coordinator = StateObject(wrappedValue: coordinator)
        coordinator.start()
    }

    var body: some Scene {
        MenuBarExtra("hdmi-defubar", systemImage: "display.2") {
            MenuView(coordinator: coordinator)
        }
    }
}
```

- [ ] **Step 4: Update `Sources/hdmi-defubar/main.swift`**

```swift
import Foundation

if CommandLine.arguments.contains("--dump") {
    DumpCommand.run()
    exit(0)
}
DefubarApp.main()
```

- [ ] **Step 5: Verify build and launch**

Run: `swift build`
Expected: no errors.

Run: `swift run hdmi-defubar &` then check a "display.2" icon appears in the menubar with status lines for each connected display; quit via the menu. Kill with `kill %1` if the menu is unreachable.

Run: `swift run hdmi-defubar --dump`
Expected: `savedLayout` is now non-null (the baseline was saved on first settle).

- [ ] **Step 6: Commit**

```bash
git add Sources/hdmi-defubar
git commit -m "feat: SwiftUI menubar app"
```

---

### Task 11: App bundle script, manual test doc and README update

**Files:**
- Create: `Scripts/make-app.sh`
- Create: `docs/manual-testing.md`
- Modify: `README.md` (Building section)

**Interfaces:**
- Consumes: release build of `hdmi-defubar`.
- Produces: `build/hdmi-defubar.app`, ad-hoc signed, `LSUIElement`, bundle id `dk.ulrik.hdmi-defubar`.

- [ ] **Step 1: Write `Scripts/make-app.sh`**

```bash
#!/bin/bash
# Builds hdmi-defubar and wraps it into an app bundle. A real bundle is
# required for user notifications and launch-at-login registration.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/hdmi-defubar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/hdmi-defubar "$APP/Contents/MacOS/hdmi-defubar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>dk.ulrik.hdmi-defubar</string>
    <key>CFBundleName</key>
    <string>hdmi-defubar</string>
    <key>CFBundleExecutable</key>
    <string>hdmi-defubar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
echo "Install with: cp -R $APP /Applications/"
```

Then: `chmod +x Scripts/make-app.sh`

- [ ] **Step 2: Build and launch the bundle**

Run: `Scripts/make-app.sh && open build/hdmi-defubar.app`
Expected: menubar icon appears, no dock icon, notification permission prompt on first launch.

- [ ] **Step 3: Write `docs/manual-testing.md`**

```markdown
# Manual test procedure

Prerequisites: at least one external monitor, the app built and running
(`Scripts/make-app.sh && open build/hdmi-defubar.app`).

## Baseline and learning

1. With all monitors connected, arrange displays as desired in
   System Settings > Displays.
2. Wait 10 seconds. The menubar should show "Last action: Learned adjusted
   layout" (or use Save current layout).
3. Run `swift run hdmi-defubar --dump` and confirm `savedLayout` is non-null
   for the current `setKey`.

## Restore on reconnect

4. Unplug the HDMI monitor, wait for displays to settle, replug it.
5. If macOS assigns a new display ID and a default config, the app should
   restore resolution and arrangement within a few seconds of the settle
   window and post a notification saying it did so.
6. If macOS happens to restore the correct config itself, the app should do
   nothing (no notification).

## Learner does not fight the restorer

7. After a restore, make no changes; confirm no "Learned" action appears
   (self-caused events must not be learned).
8. Rearrange displays manually; after 10 seconds of stability the app should
   learn the new arrangement. Unplug and replug to confirm the new
   arrangement is what gets restored.

## Pause

9. Enable "Pause automatic handling". Unplug and replug a monitor and let
   macOS mess up the layout; the app must not intervene.
10. Disable pause and use "Restore saved layout" to fix it manually.

## Store corruption

11. Quit the app, corrupt the store
    (`echo garbage > ~/Library/Application\ Support/hdmi-defubar/layouts.json`),
    relaunch. The app should notify about the unreadable store, move it to
    `layouts.json.corrupt` and start fresh.
```

- [ ] **Step 4: Update README Building section**

Replace the Building section of `README.md` with:

```markdown
## Building

Requires Xcode command line tools on macOS 13 or later.

    swift test          # run the unit tests
    Scripts/make-app.sh # build build/hdmi-defubar.app
    cp -R build/hdmi-defubar.app /Applications/

The app lives only in the menubar (no dock icon). Launch it once from
/Applications, grant the notification permission and enable "Launch at
login" from its menu. `hdmi-defubar --dump` prints the current displays,
fingerprints and the matched saved layout as JSON for debugging.
```

- [ ] **Step 5: Commit**

```bash
git add Scripts/make-app.sh docs/manual-testing.md README.md
git commit -m "feat: app bundle script, manual test procedure and build docs"
```

---

## Verification checklist (after all tasks)

- `swift test` passes.
- `swift run hdmi-defubar --dump` prints sane JSON on real hardware.
- `Scripts/make-app.sh` produces a signed bundle that launches menubar-only.
- Manual test procedure in `docs/manual-testing.md` executed at least through step 8 on real hardware.
