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
