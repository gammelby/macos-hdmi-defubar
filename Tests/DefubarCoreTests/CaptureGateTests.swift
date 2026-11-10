import XCTest
@testable import DefubarCore

final class CaptureGateTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testAllowsCaptureWhenNothingHasHappened() {
        XCTAssertTrue(CaptureGate(quietSeconds: 8).allows(at: start))
    }

    func testRefusesCaptureInsideDebounceWindowBeforeAnySettle() {
        // The November 9th, 2026 failure: A display dropped and the 20-second
        // capture fired 0.4 seconds later, before the debounce had reported
        // anything. A raw event alone has to close the gate.
        var gate = CaptureGate(quietSeconds: 8)
        gate.noteDisplayActivity(at: start)
        XCTAssertFalse(gate.allows(at: start.addingTimeInterval(0.4)))
    }

    func testEveryEventRestartsTheQuietPeriod() {
        var gate = CaptureGate(quietSeconds: 8)
        gate.noteDisplayActivity(at: start)
        gate.noteDisplayActivity(at: start.addingTimeInterval(6))
        XCTAssertFalse(gate.allows(at: start.addingTimeInterval(13.9)))
        XCTAssertTrue(gate.allows(at: start.addingTimeInterval(14)))
    }

    func testOutOfOrderActivityNeverShortensTheQuietPeriod() {
        var gate = CaptureGate(quietSeconds: 8)
        gate.noteDisplayActivity(at: start.addingTimeInterval(6))
        gate.noteDisplayActivity(at: start)
        XCTAssertFalse(gate.allows(at: start.addingTimeInterval(13.9)))
    }
}
