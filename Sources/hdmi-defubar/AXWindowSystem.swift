import AppKit
import ApplicationServices
import DefubarCore
import os

/// Accessibility-backed window system.
///
/// `LiveWindow.handle` is an index into the element list built by the last
/// `currentWindows()` call, so moves must be planned from a fresh enumeration.
/// The coordinator always does both in one step.
final class AXWindowSystem: WindowSystem {
    private let log = Logger(subsystem: "dk.ulrik.hdmi-defubar", category: "window-system")
    private var elements: [AXUIElement] = []

    /// Exact window identity comes from a private but long-stable symbol. It
    /// is resolved at runtime and its absence is not fatal: Without it,
    /// matching falls back to application plus title plus ordinal.
    private typealias GetWindowFunction =
        @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let getWindowID: GetWindowFunction? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(rtldDefault, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: GetWindowFunction.self)
    }()

    // MARK: - Permission

    var isPermitted: Bool { AXIsProcessTrusted() }

    func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Capture

    func currentWindows() -> [LiveWindow] {
        elements = []
        guard isPermitted else { return [] }
        var result: [LiveWindow] = []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            guard let bundleID = app.bundleIdentifier else { continue }
            let appName = app.localizedName ?? bundleID
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let windows = attribute(appElement, kAXWindowsAttribute) as? [AXUIElement] else {
                continue
            }
            for (ordinal, window) in windows.enumerated() {
                guard isPlaceable(window),
                      let position = pointValue(window, kAXPositionAttribute),
                      let size = sizeValue(window, kAXSizeAttribute),
                      size.width > 0, size.height > 0 else { continue }
                result.append(LiveWindow(
                    handle: elements.count,
                    bundleID: bundleID,
                    appName: appName,
                    title: (attribute(window, kAXTitleAttribute) as? String) ?? "",
                    windowID: windowID(of: window),
                    ordinal: ordinal,
                    x: Int(position.x.rounded()), y: Int(position.y.rounded()),
                    width: Int(size.width.rounded()), height: Int(size.height.rounded())))
                elements.append(window)
            }
        }
        return result
    }

    /// Standard, non-minimized, non-full-screen windows that accept a move.
    /// Panels, sheets and full-screen spaces are not ours to arrange.
    private func isPlaceable(_ window: AXUIElement) -> Bool {
        guard let subrole = attribute(window, kAXSubroleAttribute) as? String,
              subrole == kAXStandardWindowSubrole else { return false }
        if let minimized = attribute(window, kAXMinimizedAttribute) as? Bool, minimized {
            return false
        }
        if let fullScreen = attribute(window, "AXFullScreen") as? Bool, fullScreen {
            return false
        }
        var settable: DarwinBoolean = false
        let status = AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable)
        return status == .success && settable.boolValue
    }

    private func windowID(of window: AXUIElement) -> CGWindowID? {
        guard let getWindowID = Self.getWindowID else { return nil }
        var id: CGWindowID = 0
        guard getWindowID(window, &id) == .success, id != 0 else { return nil }
        return id
    }

    // MARK: - Restore

    func apply(_ moves: [WindowMove]) -> WindowRestoreResult {
        var moved = 0
        var failed: [String] = []
        for move in moves {
            guard elements.indices.contains(move.handle) else {
                failed.append(move.description)
                continue
            }
            let element = elements[move.handle]
            // Position, then size, then position again: A window is clamped to
            // the display it currently sits on, so the first move may be cut
            // short until the size fits.
            setPoint(element, kAXPositionAttribute, CGPoint(x: move.x, y: move.y))
            setSize(element, kAXSizeAttribute, CGSize(width: move.width, height: move.height))
            setPoint(element, kAXPositionAttribute, CGPoint(x: move.x, y: move.y))

            // Trust the result, not the return code: Applications may clamp a
            // move to their own minimum size or refuse it outright while still
            // reporting success.
            let landed = pointValue(element, kAXPositionAttribute) ?? .zero
            if abs(Int(landed.x.rounded()) - move.x) <= WindowPlacement.tolerance
                && abs(Int(landed.y.rounded()) - move.y) <= WindowPlacement.tolerance {
                moved += 1
            } else {
                failed.append(move.description)
                log.info("window would not move: \(move.description, privacy: .public)")
            }
        }
        return WindowRestoreResult(moved: moved, failed: failed)
    }

    // MARK: - Attribute plumbing

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func pointValue(_ element: AXUIElement, _ name: String) -> CGPoint? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeValue(_ element: AXUIElement, _ name: String) -> CGSize? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private func setPoint(_ element: AXUIElement, _ name: String, _ point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(element, name as CFString, value)
    }

    private func setSize(_ element: AXUIElement, _ name: String, _ size: CGSize) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(element, name as CFString, value)
    }
}
