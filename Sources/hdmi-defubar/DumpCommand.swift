import Foundation
import DefubarCore

/// `hdmi-defubar --dump` prints the current displays, set key and whether a
/// saved layout exists, as JSON for debugging.
enum DumpCommand {
    private struct Output: Codable {
        var setKey: String
        var displays: [DisplaySnapshot]
        var savedLayout: SavedLayout?
        var storePath: String
    }

    static func run() {
        let system = CGDisplaySystem()
        let store = LayoutStore(url: LayoutStore.defaultURL)
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        let output = Output(setKey: setKey,
                            displays: snapshot,
                            savedLayout: store.layout(forSetKey: setKey),
                            storePath: LayoutStore.defaultURL.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(output)) ?? Data()
        print(String(decoding: data, as: UTF8.self))
    }
}
