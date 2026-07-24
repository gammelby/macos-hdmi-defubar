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
