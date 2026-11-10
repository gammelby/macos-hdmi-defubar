import Foundation

/// Decides whether the periodic window capture may run.
///
/// Fed by every raw display event as well as the debounced settle. Windows are
/// already being shuffled while the debounce is still waiting, so a guard that
/// only knows about settles leaves a gap in which a capture can overwrite a
/// good arrangement with a transient one.
public struct CaptureGate {
    private let quietSeconds: TimeInterval
    private var lastActivityAt = Date.distantPast

    public init(quietSeconds: TimeInterval) {
        self.quietSeconds = quietSeconds
    }

    public mutating func noteDisplayActivity(at date: Date) {
        lastActivityAt = max(lastActivityAt, date)
    }

    public func allows(at date: Date) -> Bool {
        date >= lastActivityAt.addingTimeInterval(quietSeconds)
    }
}
