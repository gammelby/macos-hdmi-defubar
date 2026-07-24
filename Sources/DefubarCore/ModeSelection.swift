import Foundation

/// One candidate display mode. `id` is the caller's index into its own
/// parallel list of platform mode objects.
public struct ModeDescriptor: Equatable {
    public var id: Int
    public var pointWidth: Int
    public var pointHeight: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refresh: Double

    public init(id: Int, pointWidth: Int, pointHeight: Int,
                pixelWidth: Int, pixelHeight: Int, refresh: Double) {
        self.id = id
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refresh = refresh
    }
}

public enum ModeSelection {
    public struct Choice: Equatable {
        public var mode: ModeDescriptor
        public var isExact: Bool

        public init(mode: ModeDescriptor, isExact: Bool) {
            self.mode = mode
            self.isExact = isExact
        }
    }

    /// A refresh of 0 means "unknown" on some displays and matches anything.
    public static func refreshMatches(_ a: Double, _ b: Double) -> Bool {
        a == 0 || b == 0 || abs(a - b) <= 0.5
    }

    /// Exact match on point size, pixel size and refresh; otherwise the
    /// closest mode with the same point size; nil when no candidate has the
    /// target point size.
    public static func select(target: SavedDisplay, from candidates: [ModeDescriptor]) -> Choice? {
        if let exact = candidates.first(where: {
            $0.pointWidth == target.pointWidth && $0.pointHeight == target.pointHeight
                && $0.pixelWidth == target.pixelWidth && $0.pixelHeight == target.pixelHeight
                && refreshMatches($0.refresh, target.refresh)
        }) {
            return Choice(mode: exact, isExact: true)
        }
        let samePointSize = candidates.filter {
            $0.pointWidth == target.pointWidth && $0.pointHeight == target.pointHeight
        }
        guard !samePointSize.isEmpty else { return nil }
        let best = samePointSize.min { a, b in
            let aPixel = a.pixelWidth == target.pixelWidth && a.pixelHeight == target.pixelHeight
            let bPixel = b.pixelWidth == target.pixelWidth && b.pixelHeight == target.pixelHeight
            if aPixel != bPixel { return aPixel }
            let aDelta = abs(a.refresh - target.refresh)
            let bDelta = abs(b.refresh - target.refresh)
            if aDelta != bDelta { return aDelta < bDelta }
            return a.pixelWidth > b.pixelWidth
        }!
        return Choice(mode: best, isExact: false)
    }
}
