import Foundation

public enum EngineEffect: Equatable {
    case applyLayout(SavedLayout)
    case saveLayout(SavedLayout)
    case startLearnTimer
    case cancelLearnTimer
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
            guard let saved = savedLayout,
                  !LayoutDiff.changes(saved: saved, current: snapshot).isEmpty else {
                return [.cancelLearnTimer]
            }
            return [.cancelLearnTimer, .applyLayout(saved)]
        }
        return [.startLearnTimer]
    }

    public func learnTimerFired(_ snapshot: [DisplaySnapshot]) -> [EngineEffect] {
        [.saveLayout(SavedLayout(from: snapshot))]
    }
}
