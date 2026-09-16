import Foundation

public enum EngineEffect: Equatable {
    case applyLayout(SavedLayout)
    case saveLayout(SavedLayout)
    case startLearnTimer
    case cancelLearnTimer
    /// Put remembered windows back. Emitted on every topology change into a
    /// known set, including when the displays needed no change at all: macOS
    /// piles windows onto a remaining screen on unplug whether or not it then
    /// gets the resolutions right by itself.
    case restoreWindows
}

/// Pure decision core. Feed it settled display events; it returns effects.
/// The restore cap is structural: applyLayout is only ever emitted for a
/// topology change and each settled event emits at most one.
///
/// Layouts are only ever saved from user-driven states (the learn timer or an
/// explicit menu save). An unknown monitor set is deliberately NOT saved as a
/// baseline: at topology-change time the current state may be a default that
/// macOS just applied, and saving it would enshrine a wrong config as the
/// desired layout.
public struct Engine {
    private var lastSetKey: String?

    public init() {}

    /// - Parameter sawDisplaysAddedOrRemoved: true when the reconfiguration
    ///   burst contained display add/remove events. A fast unplug/replug can
    ///   settle with an unchanged set key; the flags still mark it as a
    ///   topology change so the state is treated as suspect, never learned.
    public mutating func displaysSettled(_ snapshot: [DisplaySnapshot],
                                         selfCaused: Bool,
                                         savedLayout: SavedLayout?,
                                         sawDisplaysAddedOrRemoved: Bool) -> [EngineEffect] {
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        let isTopologyChange = setKey != lastSetKey || sawDisplaysAddedOrRemoved
        lastSetKey = setKey

        if selfCaused {
            return [.cancelLearnTimer]
        }
        if isTopologyChange {
            guard let saved = savedLayout else {
                // Unknown sets with externals are never auto-saved (the
                // current state may be a wrong macOS default). Built-in-only
                // sets are safe: the identity cannot churn and the default
                // config is trustworthy, so "MacBook" gets an entry on sight.
                if !snapshot.isEmpty && snapshot.allSatisfy(\.fingerprint.isBuiltin) {
                    return [.cancelLearnTimer, .saveLayout(SavedLayout(from: snapshot))]
                }
                return [.cancelLearnTimer]
            }
            if LayoutDiff.changes(saved: saved, current: snapshot).isEmpty {
                return [.cancelLearnTimer, .restoreWindows]
            }
            return [.cancelLearnTimer, .applyLayout(saved), .restoreWindows]
        }
        return [.startLearnTimer]
    }

    public func learnTimerFired(_ snapshot: [DisplaySnapshot]) -> [EngineEffect] {
        [.saveLayout(SavedLayout(from: snapshot))]
    }
}
