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
