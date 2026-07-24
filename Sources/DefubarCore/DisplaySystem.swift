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
