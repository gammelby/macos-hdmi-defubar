import Foundation

/// What a learn pass did, so the caller can word the notification.
public struct LearnResult: Equatable {
    public var setKey: String
    public var variantID: String
    /// The mode combination had not been seen for this set before.
    public var isNewVariant: Bool
    /// The monitor set itself had not been seen before.
    public var isNewSet: Bool

    public init(setKey: String, variantID: String, isNewVariant: Bool, isNewSet: Bool) {
        self.setKey = setKey
        self.variantID = variantID
        self.isNewVariant = isNewVariant
        self.isNewSet = isNewSet
    }
}

/// JSON-file-backed store of layout sets keyed by set key. Each set holds one
/// variant per resolution combination seen for it.
/// Not thread-safe; use from one queue (the app uses the main queue).
public final class LayoutStore {
    private struct LayoutFile: Codable {
        var version = 2
        var sets: [String: LayoutSet] = [:]
    }

    /// The version 1 shape: one layout per set, its custom name naming the set.
    private struct LayoutFileV1: Codable {
        var version: Int
        var layouts: [String: LayoutV1]
    }

    private struct LayoutV1: Codable {
        var displays: [SavedDisplay]
        var customName: String?
    }

    private struct VersionProbe: Codable {
        var version: Int
    }

    public private(set) var recoveredFromCorruption = false
    private let url: URL
    private let readOnly: Bool
    private var file: LayoutFile

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hdmi-defubar/layouts.json")
    }

    /// - Parameter readOnly: Suppresses every write, including the schema
    ///   upgrade and the corruption move-aside. Inspection tools use this so
    ///   looking at the store cannot change it.
    public init(url: URL, readOnly: Bool = false) {
        self.url = url
        self.readOnly = readOnly
        var upgraded = false
        if let data = try? Data(contentsOf: url) {
            if let decoded = Self.decode(data) {
                file = decoded.file
                upgraded = decoded.upgraded
            } else {
                file = LayoutFile()
                recoveredFromCorruption = true
                if !readOnly {
                    let aside = URL(fileURLWithPath: url.path + ".corrupt")
                    try? FileManager.default.removeItem(at: aside)
                    try? FileManager.default.moveItem(at: url, to: aside)
                }
            }
        } else {
            file = LayoutFile()
        }
        // Write the upgraded schema back at once, so the file on disk stops
        // claiming to be version 1 and the upgrade is not redone every launch.
        if upgraded { persist() }
        dropEmptySets()
        migrateKeysIfNeeded()
    }

    /// Reads the current schema, falling back to the version 1 shape and
    /// reporting whether that fallback was used. Returns nil only when the
    /// data is neither, which is what triggers the move-aside recovery.
    private static func decode(_ data: Data) -> (file: LayoutFile, upgraded: Bool)? {
        let decoder = JSONDecoder()
        let version = (try? decoder.decode(VersionProbe.self, from: data))?.version
        if version == 1, let old = try? decoder.decode(LayoutFileV1.self, from: data) {
            var migrated = LayoutFile()
            for (key, layout) in old.layouts {
                // The v1 custom name named the whole set, so it stays at set
                // level and the single variant keeps its derived name.
                migrated.sets[key] = LayoutSet(layout: SavedLayout(displays: layout.displays),
                                               customName: layout.customName)
            }
            return (migrated, true)
        }
        guard let current = try? decoder.decode(LayoutFile.self, from: data) else { return nil }
        return (current, false)
    }

    /// A set with no variants has no identity and nothing to restore; it can
    /// only come from hand-edited or truncated data.
    private func dropEmptySets() {
        let cleaned = file.sets.filter { !$0.value.variants.isEmpty }
        if cleaned.count != file.sets.count {
            file.sets = cleaned
            persist()
        }
    }

    /// Rekeys entries whose stored key does not match the canonical set key
    /// computed from their fingerprints (the match key format has changed
    /// over time). On collision the entry under the lexicographically first
    /// old key wins.
    private func migrateKeysIfNeeded() {
        var migrated: [String: LayoutSet] = [:]
        var changed = false
        for key in file.sets.keys.sorted() {
            let set = file.sets[key]!
            guard let fingerprints = set.variants.first?.layout.displays.map(\.fingerprint) else {
                continue
            }
            let canonical = DisplayFingerprint.setKey(for: fingerprints)
            if canonical != key { changed = true }
            if migrated[canonical] == nil {
                migrated[canonical] = set
            }
        }
        if changed {
            file.sets = migrated
            persist()
        }
    }

    // MARK: - Reading

    public func set(forSetKey key: String) -> LayoutSet? {
        file.sets[key]
    }

    /// The layout a reconnect of this set should restore.
    public func activeLayout(forSetKey key: String) -> SavedLayout? {
        file.sets[key]?.activeLayout
    }

    public func allSetKeys() -> [String] {
        file.sets.keys.sorted()
    }

    public func allSets() -> [(setKey: String, set: LayoutSet)] {
        file.sets.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Every variant of every set, for mode inheritance: a display's known
    /// mode may have been recorded under any combination it appeared in.
    public func allLayouts() -> [SavedLayout] {
        allSets().flatMap { $0.set.variants.map(\.layout) }
    }

    public func allVariantIDs() -> Set<String> {
        Set(file.sets.values.flatMap { $0.variants.map(\.id) })
    }

    // MARK: - Writing

    /// Records a layout observed as stable. A mode combination already known
    /// for this set updates that variant in place, keeping its id and name, so
    /// rearranging displays never creates a variant. An unseen combination
    /// becomes a new variant. Either way the touched variant becomes active.
    @discardableResult
    public func learn(_ layout: SavedLayout) -> LearnResult {
        let key = DisplayFingerprint.setKey(for: layout.displays.map(\.fingerprint))
        guard var set = file.sets[key] else {
            let variant = LayoutVariant(layout: layout)
            file.sets[key] = LayoutSet(variants: [variant], activeVariantID: variant.id)
            persist()
            return LearnResult(setKey: key, variantID: variant.id,
                               isNewVariant: true, isNewSet: true)
        }
        let signature = layout.modeSignature
        if let index = set.variants.firstIndex(where: { $0.layout.modeSignature == signature }) {
            set.variants[index].layout = layout
            set.activeVariantID = set.variants[index].id
            file.sets[key] = set
            persist()
            return LearnResult(setKey: key, variantID: set.variants[index].id,
                               isNewVariant: false, isNewSet: false)
        }
        let variant = LayoutVariant(layout: layout)
        set.variants.append(variant)
        set.activeVariantID = variant.id
        file.sets[key] = set
        persist()
        return LearnResult(setKey: key, variantID: variant.id,
                           isNewVariant: true, isNewSet: false)
    }

    /// Forces a new variant even when the mode combination is already known,
    /// for the explicit "save current as new variant" action.
    @discardableResult
    public func saveAsNewVariant(_ layout: SavedLayout) -> LearnResult {
        let key = DisplayFingerprint.setKey(for: layout.displays.map(\.fingerprint))
        let variant = LayoutVariant(layout: layout)
        if var set = file.sets[key] {
            set.variants.append(variant)
            set.activeVariantID = variant.id
            file.sets[key] = set
            persist()
            return LearnResult(setKey: key, variantID: variant.id,
                               isNewVariant: true, isNewSet: false)
        }
        file.sets[key] = LayoutSet(variants: [variant], activeVariantID: variant.id)
        persist()
        return LearnResult(setKey: key, variantID: variant.id, isNewVariant: true, isNewSet: true)
    }

    public func setActiveVariant(setKey key: String, variantID: String) {
        guard var set = file.sets[key], set.variant(withID: variantID) != nil else { return }
        set.activeVariantID = variantID
        file.sets[key] = set
        persist()
    }

    public func renameSet(setKey key: String, to name: String) {
        guard var set = file.sets[key] else { return }
        set.customName = Self.normalized(name)
        file.sets[key] = set
        persist()
    }

    public func renameVariant(setKey key: String, variantID: String, to name: String) {
        guard var set = file.sets[key],
              let index = set.variants.firstIndex(where: { $0.id == variantID }) else { return }
        set.variants[index].customName = Self.normalized(name)
        file.sets[key] = set
        persist()
    }

    /// Deletes one variant, promoting the next one when the active variant
    /// goes. Deleting the last variant deletes the set. Returns the ids that
    /// no longer exist, so window snapshots can be pruned.
    @discardableResult
    public func deleteVariant(setKey key: String, variantID: String) -> [String] {
        guard var set = file.sets[key],
              let index = set.variants.firstIndex(where: { $0.id == variantID }) else { return [] }
        set.variants.remove(at: index)
        guard !set.variants.isEmpty else {
            file.sets.removeValue(forKey: key)
            persist()
            return [variantID]
        }
        if set.activeVariantID == variantID {
            set.activeVariantID = set.variants[min(index, set.variants.count - 1)].id
        }
        file.sets[key] = set
        persist()
        return [variantID]
    }

    @discardableResult
    public func deleteSet(forSetKey key: String) -> [String] {
        guard let set = file.sets.removeValue(forKey: key) else { return [] }
        persist()
        return set.variants.map(\.id)
    }

    private static func normalized(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func persist() {
        guard !readOnly else { return }
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
