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

/// Desired layout for one set of simultaneously connected displays.
public struct SavedLayout: Codable, Equatable {
    public var displays: [SavedDisplay]

    public init(displays: [SavedDisplay]) {
        self.displays = displays
    }

    public init(from snapshot: [DisplaySnapshot]) {
        displays = snapshot.map(SavedDisplay.init)
    }
}
