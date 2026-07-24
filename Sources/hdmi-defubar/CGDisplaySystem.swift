import AppKit
import CoreGraphics
import DefubarCore
import os

/// CoreGraphics-backed display system.
final class CGDisplaySystem: DisplaySystem {
    private let log = Logger(subsystem: "dk.ulrik.hdmi-defubar", category: "display-system")

    func currentSnapshot() -> [DisplaySnapshot] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).compactMap { id in
            guard let mode = CGDisplayCopyDisplayMode(id) else { return nil }
            let bounds = CGDisplayBounds(id)
            return DisplaySnapshot(
                displayID: id,
                fingerprint: DisplayFingerprint(
                    vendor: CGDisplayVendorNumber(id),
                    model: CGDisplayModelNumber(id),
                    serial: CGDisplaySerialNumber(id),
                    isBuiltin: CGDisplayIsBuiltin(id) != 0),
                name: Self.displayName(id),
                pointWidth: Int(bounds.width), pointHeight: Int(bounds.height),
                pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                refresh: mode.refreshRate,
                originX: Int(bounds.origin.x), originY: Int(bounds.origin.y),
                isMain: CGDisplayIsMain(id) != 0)
        }
    }

    func apply(_ layout: SavedLayout) -> ApplyResult {
        let snapshot = currentSnapshot()
        let changes = LayoutDiff.changes(saved: layout, current: snapshot)
        guard !changes.isEmpty else {
            return ApplyResult(applied: [], substitutions: [], failureMessage: nil)
        }
        var configRef: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configRef) == .success, let config = configRef else {
            return ApplyResult(applied: [], substitutions: [],
                               failureMessage: "could not begin a display configuration transaction")
        }
        var applied: [String] = []
        var substitutions: [String] = []
        for change in changes {
            let id = change.displayID
            if change.needsMode {
                let (descriptors, cgModes) = modeCandidates(for: id)
                if let choice = ModeSelection.select(target: change.target, from: descriptors) {
                    CGConfigureDisplayWithDisplayMode(config, id, cgModes[choice.mode.id], nil)
                    if !choice.isExact { substitutions.append(change.target.name) }
                    log.info("mode for \(change.target.name, privacy: .public): exact=\(choice.isExact)")
                } else {
                    substitutions.append(change.target.name)
                    log.error("no usable mode with saved point size for \(change.target.name, privacy: .public)")
                }
            }
            if change.needsOrigin {
                CGConfigureDisplayOrigin(config, id,
                                         Int32(change.target.originX), Int32(change.target.originY))
            }
            applied.append(change.target.name)
        }
        let error = CGCompleteDisplayConfiguration(config, .permanently)
        guard error == .success else {
            return ApplyResult(applied: [], substitutions: [],
                               failureMessage: "display configuration failed (CGError \(error.rawValue))")
        }
        return ApplyResult(applied: applied, substitutions: substitutions, failureMessage: nil)
    }

    private func modeCandidates(for id: CGDirectDisplayID) -> ([ModeDescriptor], [CGDisplayMode]) {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let all = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
        let usable = all.filter { $0.isUsableForDesktopGUI() }
        let descriptors = usable.enumerated().map { index, mode in
            ModeDescriptor(id: index,
                           pointWidth: mode.width, pointHeight: mode.height,
                           pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                           refresh: mode.refreshRate)
        }
        return (descriptors, usable)
    }

    private static func displayName(_ id: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id
        }
        return screen?.localizedName ?? "Display \(id)"
    }
}
