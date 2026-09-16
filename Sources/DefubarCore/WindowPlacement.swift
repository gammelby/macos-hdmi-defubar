import Foundation

/// Turns live windows into a storable snapshot and back into moves.
///
/// Matching is three-tier and each live window is used at most once: The
/// WindowServer id first (exact, and what covers the unplug-and-replug case),
/// then application plus window title, then application plus position in that
/// application's window list. Live windows nothing matches are left alone,
/// which is what keeps windows opened since the capture where they are.
public enum WindowPlacement {
    /// Windows already within this many points of the target are left alone,
    /// so a restore that changes nothing moves nothing.
    public static let tolerance = 2

    // MARK: - Capture

    public static func capture(_ live: [LiveWindow],
                               displays: [DisplaySnapshot]) -> [WindowSnapshot] {
        let groups = displayGroups(displays)
        return live.compactMap { window in
            guard let (display, index) = owningDisplay(of: window, groups: groups) else {
                return nil
            }
            return WindowSnapshot(
                bundleID: window.bundleID,
                appName: window.appName,
                title: window.title,
                windowID: window.windowID,
                ordinal: window.ordinal,
                displayMatchKey: display.fingerprint.matchKey,
                displayIndex: index,
                dx: window.x - display.originX,
                dy: window.y - display.originY,
                width: window.width,
                height: window.height)
        }
    }

    // MARK: - Restore

    public static func plan(saved: [WindowSnapshot],
                            live: [LiveWindow],
                            displays: [DisplaySnapshot]) -> [WindowMove] {
        let groups = displayGroups(displays)
        var available = Set(live.indices)
        var pairs: [(WindowSnapshot, LiveWindow)] = []
        var unmatched = Array(saved.indices)

        func consume(_ matcher: (WindowSnapshot, LiveWindow) -> Bool) {
            var stillUnmatched: [Int] = []
            for savedIndex in unmatched {
                let target = saved[savedIndex]
                if let liveIndex = available.sorted().first(where: { matcher(target, live[$0]) }) {
                    available.remove(liveIndex)
                    pairs.append((target, live[liveIndex]))
                } else {
                    stillUnmatched.append(savedIndex)
                }
            }
            unmatched = stillUnmatched
        }

        consume { saved, live in
            guard let a = saved.windowID, let b = live.windowID else { return false }
            return a == b
        }
        consume { saved, live in
            !saved.title.isEmpty && saved.bundleID == live.bundleID && saved.title == live.title
        }
        consume { saved, live in
            saved.bundleID == live.bundleID && saved.ordinal == live.ordinal
        }

        return pairs.compactMap { target, window in
            guard let display = display(forMatchKey: target.displayMatchKey,
                                        index: target.displayIndex, groups: groups) else {
                // The display the window lived on is not connected; leave it.
                return nil
            }
            let rect = absoluteRect(of: target, on: display)
            guard abs(rect.x - window.x) > tolerance || abs(rect.y - window.y) > tolerance
                || abs(rect.width - window.width) > tolerance
                || abs(rect.height - window.height) > tolerance else {
                return nil
            }
            return WindowMove(handle: window.handle, description: describe(window),
                              x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        }
    }

    /// Places the remembered rect back on its display, shrinking and nudging it
    /// so it stays fully on that display. A display can come back at a smaller
    /// resolution than when the window was remembered.
    static func absoluteRect(of saved: WindowSnapshot,
                             on display: DisplaySnapshot) -> (x: Int, y: Int, width: Int, height: Int) {
        let width = min(saved.width, display.pointWidth)
        let height = min(saved.height, display.pointHeight)
        let x = clamp(display.originX + saved.dx,
                      low: display.originX, high: display.originX + display.pointWidth - width)
        let y = clamp(display.originY + saved.dy,
                      low: display.originY, high: display.originY + display.pointHeight - height)
        return (x, y, width, height)
    }

    // MARK: - Displays

    /// Displays by fingerprint match key, each group in origin order so the
    /// index is stable across reconnects. Only two identical monitors with no
    /// EDID serial ever produce a group larger than one.
    private static func displayGroups(_ displays: [DisplaySnapshot]) -> [String: [DisplaySnapshot]] {
        Dictionary(grouping: displays, by: { $0.fingerprint.matchKey })
            .mapValues { group in
                group.sorted { ($0.originX, $0.originY) < ($1.originX, $1.originY) }
            }
    }

    private static func display(forMatchKey key: String, index: Int,
                                groups: [String: [DisplaySnapshot]]) -> DisplaySnapshot? {
        guard let group = groups[key], !group.isEmpty else { return nil }
        return group[min(index, group.count - 1)]
    }

    /// The display a window belongs to: The one it overlaps most. A window
    /// overlapping nothing (fully offscreen) is not remembered.
    private static func owningDisplay(of window: LiveWindow,
                                      groups: [String: [DisplaySnapshot]]) -> (DisplaySnapshot, Int)? {
        var best: (display: DisplaySnapshot, index: Int, area: Int)?
        for key in groups.keys.sorted() {
            for (index, display) in groups[key]!.enumerated() {
                let overlapW = overlap(window.x, window.x + window.width,
                                       display.originX, display.originX + display.pointWidth)
                let overlapH = overlap(window.y, window.y + window.height,
                                       display.originY, display.originY + display.pointHeight)
                let area = overlapW * overlapH
                if area > 0 && area > (best?.area ?? 0) {
                    best = (display, index, area)
                }
            }
        }
        guard let best else { return nil }
        return (best.display, best.index)
    }

    private static func overlap(_ aLow: Int, _ aHigh: Int, _ bLow: Int, _ bHigh: Int) -> Int {
        max(0, min(aHigh, bHigh) - max(aLow, bLow))
    }

    private static func clamp(_ value: Int, low: Int, high: Int) -> Int {
        guard high > low else { return low }
        return min(max(value, low), high)
    }

    private static func describe(_ window: LiveWindow) -> String {
        window.title.isEmpty ? window.appName : "\(window.appName) (\(window.title))"
    }
}
