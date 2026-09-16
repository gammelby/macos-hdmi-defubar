import Foundation
import DefubarCore

/// `hdmi-defubar --dump` prints the current displays, set key, the saved set
/// with its variants and the remembered window count, as JSON for debugging.
enum DumpCommand {
    private struct Output: Codable {
        var setKey: String
        var displays: [DisplaySnapshot]
        var savedSet: LayoutSet?
        var activeLayout: SavedLayout?
        var rememberedWindows: Int?
        var accessibilityGranted: Bool
        var storePath: String
        var windowStorePath: String
    }

    static func run() {
        let system = CGDisplaySystem()
        // Read-only: Inspecting the store must not upgrade, rekey or move it
        // aside behind the running app's back.
        let store = LayoutStore(url: LayoutStore.defaultURL, readOnly: true)
        let windowStore = WindowStore(url: WindowStore.defaultURL, readOnly: true)
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        let saved = store.set(forSetKey: setKey)
        let output = Output(
            setKey: setKey,
            displays: snapshot,
            savedSet: saved,
            activeLayout: saved?.activeLayout,
            rememberedWindows: saved?.activeVariant
                .flatMap { windowStore.snapshot(forVariantID: $0.id) }?.windows.count,
            accessibilityGranted: AXWindowSystem().isPermitted,
            storePath: LayoutStore.defaultURL.path,
            windowStorePath: WindowStore.defaultURL.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(output)) ?? Data()
        print(String(decoding: data, as: UTF8.self))
    }
}
