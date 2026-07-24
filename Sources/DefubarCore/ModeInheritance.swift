import Foundation

/// First-connect help for unknown monitor sets: even when a *combination* of
/// displays has never been saved, the individual displays usually have. This
/// builds a synthetic layout that borrows each display's saved mode from
/// other layouts while keeping the current origins, so a known monitor comes
/// up at its known resolution instead of the macOS default. The synthetic
/// layout is applied but never saved; only user arrangements are learned.
public enum ModeInheritance {
    public static func syntheticLayout(for snapshot: [DisplaySnapshot],
                                       from layouts: [SavedLayout]) -> SavedLayout? {
        let currentKeys = Set(snapshot.map(\.fingerprint.matchKey))
        // Best source first: layouts sharing the most displays with the
        // current set, then the larger layout, then stable name order.
        let ordered = layouts.sorted { a, b in
            let aShared = a.displays.filter { currentKeys.contains($0.fingerprint.matchKey) }.count
            let bShared = b.displays.filter { currentKeys.contains($0.fingerprint.matchKey) }.count
            if aShared != bShared { return aShared > bShared }
            if a.displays.count != b.displays.count { return a.displays.count > b.displays.count }
            return a.derivedName < b.derivedName
        }
        var inheritedAnything = false
        let displays = snapshot.map { current -> SavedDisplay in
            var result = SavedDisplay(from: current)
            for layout in ordered {
                guard let match = layout.displays.first(where: {
                    $0.fingerprint.matchKey == current.fingerprint.matchKey
                }) else { continue }
                let modeDiffers = match.pointWidth != current.pointWidth
                    || match.pointHeight != current.pointHeight
                    || match.pixelWidth != current.pixelWidth
                    || match.pixelHeight != current.pixelHeight
                    || !ModeSelection.refreshMatches(match.refresh, current.refresh)
                if modeDiffers {
                    result.pointWidth = match.pointWidth
                    result.pointHeight = match.pointHeight
                    result.pixelWidth = match.pixelWidth
                    result.pixelHeight = match.pixelHeight
                    result.refresh = match.refresh
                    inheritedAnything = true
                }
                break
            }
            return result
        }
        return inheritedAnything ? SavedLayout(displays: displays) : nil
    }
}
