import Foundation

/// One window as the platform reports it right now. Coordinates are absolute,
/// in the global top-left-origin, y-down space shared by the Accessibility API
/// and `CGDisplayBounds`.
///
/// `handle` is an opaque index the platform adapter uses to find the window
/// again; the core never interprets it, which keeps the placement logic free
/// of Accessibility types and therefore testable.
public struct LiveWindow: Equatable {
    public var handle: Int
    public var bundleID: String
    public var appName: String
    public var title: String
    /// The WindowServer id, when it could be obtained. Stable for the life of
    /// the window, which covers the whole unplug-and-replug case.
    public var windowID: UInt32?
    /// Index within its own application's window list, as a last-resort match.
    public var ordinal: Int
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(handle: Int, bundleID: String, appName: String, title: String,
                windowID: UInt32?, ordinal: Int,
                x: Int, y: Int, width: Int, height: Int) {
        self.handle = handle
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.windowID = windowID
        self.ordinal = ordinal
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// One remembered window position, stored relative to the display it sat on so
/// it lands on the right monitor even if the arrangement comes back shifted.
public struct WindowSnapshot: Codable, Equatable {
    public var bundleID: String
    public var appName: String
    public var title: String
    public var windowID: UInt32?
    public var ordinal: Int
    /// Fingerprint match key of the display the window sat on.
    public var displayMatchKey: String
    /// Index among displays sharing that match key, in origin order. Only ever
    /// non-zero for two identical monitors that expose no EDID serial.
    public var displayIndex: Int
    public var dx: Int
    public var dy: Int
    public var width: Int
    public var height: Int

    public init(bundleID: String, appName: String, title: String,
                windowID: UInt32?, ordinal: Int,
                displayMatchKey: String, displayIndex: Int,
                dx: Int, dy: Int, width: Int, height: Int) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.windowID = windowID
        self.ordinal = ordinal
        self.displayMatchKey = displayMatchKey
        self.displayIndex = displayIndex
        self.dx = dx
        self.dy = dy
        self.width = width
        self.height = height
    }
}

/// The remembered window arrangement for one layout variant.
public struct WindowLayoutSnapshot: Codable, Equatable {
    public var capturedAt: Date
    public var windows: [WindowSnapshot]

    public init(capturedAt: Date, windows: [WindowSnapshot]) {
        self.capturedAt = capturedAt
        self.windows = windows
    }
}

/// Where one window should be put back, in absolute coordinates.
public struct WindowMove: Equatable {
    public var handle: Int
    /// For logging and notifications only.
    public var description: String
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(handle: Int, description: String, x: Int, y: Int, width: Int, height: Int) {
        self.handle = handle
        self.description = description
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Outcome of putting windows back.
public struct WindowRestoreResult: Equatable {
    public var moved: Int
    /// Windows the platform refused to move, by description.
    public var failed: [String]

    public init(moved: Int, failed: [String]) {
        self.moved = moved
        self.failed = failed
    }
}

/// Abstraction over the platform window stack, so the matching and coordinate
/// logic stays testable without the Accessibility API. Mirrors the
/// `DisplaySystem` seam.
public protocol WindowSystem {
    /// Whether the Accessibility permission has been granted.
    var isPermitted: Bool { get }
    /// Prompts for the Accessibility permission. No-op once granted.
    func requestPermission()
    /// Every movable standard window of every regular application.
    func currentWindows() -> [LiveWindow]
    /// Applies the moves, returning how many stuck.
    func apply(_ moves: [WindowMove]) -> WindowRestoreResult
}
