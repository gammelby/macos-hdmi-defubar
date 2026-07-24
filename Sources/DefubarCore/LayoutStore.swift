import Foundation

/// JSON-file-backed store of saved layouts keyed by set key.
/// Not thread-safe; use from one queue (the app uses the main queue).
public final class LayoutStore {
    private struct LayoutFile: Codable {
        var version = 1
        var layouts: [String: SavedLayout] = [:]
    }

    public private(set) var recoveredFromCorruption = false
    private let url: URL
    private var file: LayoutFile

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hdmi-defubar/layouts.json")
    }

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url) {
            if let decoded = try? JSONDecoder().decode(LayoutFile.self, from: data) {
                file = decoded
            } else {
                file = LayoutFile()
                recoveredFromCorruption = true
                let aside = URL(fileURLWithPath: url.path + ".corrupt")
                try? FileManager.default.removeItem(at: aside)
                try? FileManager.default.moveItem(at: url, to: aside)
            }
        } else {
            file = LayoutFile()
        }
        migrateKeysIfNeeded()
    }

    /// Rekeys entries whose stored key does not match the canonical set key
    /// computed from their fingerprints (the match key format has changed
    /// over time). On collision the entry under the lexicographically first
    /// old key wins.
    private func migrateKeysIfNeeded() {
        var migrated: [String: SavedLayout] = [:]
        var changed = false
        for key in file.layouts.keys.sorted() {
            let layout = file.layouts[key]!
            let canonical = DisplayFingerprint.setKey(for: layout.displays.map(\.fingerprint))
            if canonical != key { changed = true }
            if migrated[canonical] == nil {
                migrated[canonical] = layout
            }
        }
        if changed {
            file.layouts = migrated
            persist()
        }
    }

    public func layout(forSetKey key: String) -> SavedLayout? {
        file.layouts[key]
    }

    public func allSetKeys() -> [String] {
        file.layouts.keys.sorted()
    }

    /// Saves under the canonical set key computed from the layout's own
    /// fingerprints, so entries can never be stored under a stale key format.
    public func save(_ layout: SavedLayout) {
        file.layouts[DisplayFingerprint.setKey(for: layout.displays.map(\.fingerprint))] = layout
        persist()
    }

    public func delete(forSetKey key: String) {
        file.layouts.removeValue(forKey: key)
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(file).write(to: url, options: .atomic)
        } catch {
            // Persist failures leave the in-memory state authoritative; the
            // caller surfaces store problems via recoveredFromCorruption only.
        }
    }
}
