import Foundation

/// Current state of one online display as reported by the system.
public struct DisplaySnapshot: Codable, Equatable {
    public var displayID: UInt32
    public var fingerprint: DisplayFingerprint
    public var name: String
    public var pointWidth: Int
    public var pointHeight: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refresh: Double
    public var originX: Int
    public var originY: Int
    public var isMain: Bool

    public init(displayID: UInt32, fingerprint: DisplayFingerprint, name: String,
                pointWidth: Int, pointHeight: Int, pixelWidth: Int, pixelHeight: Int,
                refresh: Double, originX: Int, originY: Int, isMain: Bool) {
        self.displayID = displayID
        self.fingerprint = fingerprint
        self.name = name
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refresh = refresh
        self.originX = originX
        self.originY = originY
        self.isMain = isMain
    }
}

/// Desired state of one display within a saved layout.
public struct SavedDisplay: Codable, Equatable {
    public var fingerprint: DisplayFingerprint
    public var name: String
    public var pointWidth: Int
    public var pointHeight: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refresh: Double
    public var originX: Int
    public var originY: Int
    public var isMain: Bool

    public init(from snapshot: DisplaySnapshot) {
        fingerprint = snapshot.fingerprint
        name = snapshot.name
        pointWidth = snapshot.pointWidth
        pointHeight = snapshot.pointHeight
        pixelWidth = snapshot.pixelWidth
        pixelHeight = snapshot.pixelHeight
        refresh = snapshot.refresh
        originX = snapshot.originX
        originY = snapshot.originY
        isMain = snapshot.isMain
    }
}

/// Desired display state for one set of simultaneously connected displays:
/// per-display mode plus arrangement. A pure value; identity and naming live
/// on `LayoutVariant` and `LayoutSet`.
public struct SavedLayout: Codable, Equatable {
    public var displays: [SavedDisplay]

    public init(displays: [SavedDisplay]) {
        self.displays = displays
    }

    public init(from snapshot: [DisplaySnapshot]) {
        displays = snapshot.map(SavedDisplay.init)
    }

    /// Human-readable name built from the display names: built-in first as
    /// "MacBook", externals alphabetically, identical names collapsed to
    /// "N× Name".
    public var derivedName: String {
        Self.collapseRuns(sortedDisplays.map { $0.fingerprint.isBuiltin ? "MacBook" : $0.name })
    }

    /// Human-readable name built from the display modes, in the same display
    /// order as `derivedName`: "3840×2160 @ 60 + 2560×1440 @ 144".
    public var derivedVariantName: String {
        Self.collapseRuns(sortedDisplays.map {
            "\($0.pointWidth)×\($0.pointHeight) @ \(Int($0.refresh.rounded()))"
        })
    }

    /// Identity of the mode combination, independent of arrangement and of
    /// display order. Two layouts with the same signature differ only in how
    /// the displays are positioned relative to each other, which is what makes
    /// a rearrangement update a variant instead of creating one.
    ///
    /// Refresh is rounded to whole Hz so 59.94 and 60.0 agree, mirroring the
    /// tolerance in `ModeSelection.refreshMatches`. A display reporting a
    /// refresh of 0 ("unknown") gets its own signature; that is rare and the
    /// only cost is one extra variant.
    public var modeSignature: String {
        displays
            .map {
                "\($0.fingerprint.matchKey)|\($0.pointWidth)x\($0.pointHeight)"
                    + "|\($0.pixelWidth)x\($0.pixelHeight)|\(Int($0.refresh.rounded()))"
            }
            .sorted()
            .joined(separator: "+")
    }

    /// Built-in first, then externals by name, then by position for stability
    /// among identically named displays.
    private var sortedDisplays: [SavedDisplay] {
        displays.sorted { a, b in
            if a.fingerprint.isBuiltin != b.fingerprint.isBuiltin {
                return a.fingerprint.isBuiltin
            }
            if a.name != b.name { return a.name < b.name }
            return (a.originX, a.originY) < (b.originX, b.originY)
        }
    }

    /// Joins parts with " + ", collapsing adjacent identical ones to "N× part".
    private static func collapseRuns(_ parts: [String]) -> String {
        var result: [String] = []
        var index = 0
        while index < parts.count {
            var runEnd = index
            while runEnd + 1 < parts.count && parts[runEnd + 1] == parts[index] {
                runEnd += 1
            }
            let count = runEnd - index + 1
            result.append(count > 1 ? "\(count)× \(parts[index])" : parts[index])
            index = runEnd + 1
        }
        return result.joined(separator: " + ")
    }
}

/// One resolution combination for a monitor set, with its own name and its own
/// remembered window arrangement (stored separately, keyed by this id).
public struct LayoutVariant: Codable, Equatable, Identifiable {
    public var id: String
    /// User-assigned name; nil or empty means "use the derived name".
    public var customName: String?
    public var layout: SavedLayout

    public init(id: String = UUID().uuidString, customName: String? = nil, layout: SavedLayout) {
        self.id = id
        self.customName = customName
        self.layout = layout
    }

    /// The label to show in UI: the custom name when set, else the modes.
    public var label: String {
        if let customName, !customName.isEmpty {
            return customName
        }
        return layout.derivedVariantName
    }
}

/// Everything saved for one set of simultaneously connected displays: the
/// variants seen for it and which one a reconnect should restore.
public struct LayoutSet: Codable, Equatable {
    /// User-assigned name; nil or empty means "use the derived name".
    public var customName: String?
    public var variants: [LayoutVariant]
    public var activeVariantID: String

    public init(customName: String? = nil, variants: [LayoutVariant], activeVariantID: String) {
        self.customName = customName
        self.variants = variants
        self.activeVariantID = activeVariantID
    }

    /// Convenience for the common "one variant, it is the active one" case.
    public init(layout: SavedLayout, customName: String? = nil) {
        let variant = LayoutVariant(layout: layout)
        self.init(customName: customName, variants: [variant], activeVariantID: variant.id)
    }

    /// The variant a reconnect restores. Falls back to the first one when the
    /// stored id has gone stale.
    public var activeVariant: LayoutVariant? {
        variants.first { $0.id == activeVariantID } ?? variants.first
    }

    public var activeLayout: SavedLayout? {
        activeVariant?.layout
    }

    /// The label to show in UI: the custom name when set, else the display
    /// names of the active variant.
    public var displayLabel: String {
        if let customName, !customName.isEmpty {
            return customName
        }
        return activeVariant?.layout.derivedName ?? "Unknown layout"
    }

    public func variant(withID id: String) -> LayoutVariant? {
        variants.first { $0.id == id }
    }
}
