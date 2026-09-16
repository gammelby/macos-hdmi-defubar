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

    func testUnknownSetWithExternalsIsNotSavedAsBaseline() {
        var engine = Engine()
        let effects = engine.displaysSettled(both, selfCaused: false, savedLayout: nil,
                                             sawDisplaysAddedOrRemoved: false)
        XCTAssertEqual(effects, [.cancelLearnTimer])
    }

    func testUnknownBuiltinOnlySetIsSavedAutomatically() {
        // Safe to auto-create: the built-in display's identity cannot churn
        // and its default config is trustworthy.
        var engine = Engine()
        let effects = engine.displaysSettled(laptopOnly, selfCaused: false, savedLayout: nil,
                                             sawDisplaysAddedOrRemoved: true)
        XCTAssertEqual(effects, [.cancelLearnTimer,
                                 .saveLayout(SavedLayout(from: laptopOnly))])
    }

    func testTopologyChangeWithMatchingLayoutStillRestoresWindows() {
        var engine = Engine()
        _ = engine.displaysSettled(laptopOnly, selfCaused: false, savedLayout: SavedLayout(from: laptopOnly),
                                   sawDisplaysAddedOrRemoved: false)
        let effects = engine.displaysSettled(both, selfCaused: false, savedLayout: SavedLayout(from: both),
                                             sawDisplaysAddedOrRemoved: true)
        // The displays were already right, but macOS still piled the windows
        // onto one screen on unplug.
        XCTAssertEqual(effects, [.cancelLearnTimer, .restoreWindows])
    }

    func testTopologyChangeWithDriftedLayoutRestores() {
        var engine = Engine()
        _ = engine.displaysSettled(laptopOnly, selfCaused: false, savedLayout: SavedLayout(from: laptopOnly),
                                   sawDisplaysAddedOrRemoved: false)
        let saved = SavedLayout(from: both)
        let effects = engine.displaysSettled(bothWrong, selfCaused: false, savedLayout: saved,
                                             sawDisplaysAddedOrRemoved: true)
        XCTAssertEqual(effects, [.cancelLearnTimer, .applyLayout(saved), .restoreWindows])
    }

    func testFastReplugWithSameSetKeyIsATopologyChange() {
        // Unplug and replug within one settle window: the set key never
        // changes, but add/remove flags were seen. Must restore, not learn.
        var engine = Engine()
        _ = engine.displaysSettled(both, selfCaused: false, savedLayout: SavedLayout(from: both),
                                   sawDisplaysAddedOrRemoved: false)
        let saved = SavedLayout(from: both)
        let effects = engine.displaysSettled(bothWrong, selfCaused: false, savedLayout: saved,
                                             sawDisplaysAddedOrRemoved: true)
        XCTAssertEqual(effects, [.cancelLearnTimer, .applyLayout(saved), .restoreWindows])
    }

    func testInPlaceChangeStartsLearnTimer() {
        var engine = Engine()
        _ = engine.displaysSettled(both, selfCaused: false, savedLayout: SavedLayout(from: both),
                                   sawDisplaysAddedOrRemoved: false)
        let effects = engine.displaysSettled(bothWrong, selfCaused: false, savedLayout: SavedLayout(from: both),
                                             sawDisplaysAddedOrRemoved: false)
        XCTAssertEqual(effects, [.startLearnTimer])
    }

    func testSelfCausedEventOnlyCancelsTimerButUpdatesState() {
        var engine = Engine()
        _ = engine.displaysSettled(laptopOnly, selfCaused: false, savedLayout: SavedLayout(from: laptopOnly),
                                   sawDisplaysAddedOrRemoved: false)
        // Self-caused topology-looking event after our own apply.
        let effects = engine.displaysSettled(both, selfCaused: true, savedLayout: SavedLayout(from: both),
                                             sawDisplaysAddedOrRemoved: true)
        XCTAssertEqual(effects, [.cancelLearnTimer])
        // Next in-place change is classified against the updated set key.
        let next = engine.displaysSettled(bothWrong, selfCaused: false, savedLayout: SavedLayout(from: both),
                                          sawDisplaysAddedOrRemoved: false)
        XCTAssertEqual(next, [.startLearnTimer])
    }

    func testUnknownSetNeverRestoresWindows() {
        // Nothing is remembered for a set that has never been saved, so the
        // effect would be a no-op; not emitting it keeps that explicit.
        var engine = Engine()
        let effects = engine.displaysSettled(both, selfCaused: false, savedLayout: nil,
                                             sawDisplaysAddedOrRemoved: true)
        XCTAssertFalse(effects.contains(.restoreWindows))
    }

    func testLearnTimerFiredSavesLearnedLayout() {
        let engine = Engine()
        let effects = engine.learnTimerFired(bothWrong)
        XCTAssertEqual(effects, [.saveLayout(SavedLayout(from: bothWrong))])
    }
}
