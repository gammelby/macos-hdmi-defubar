import Foundation

/// Why an arrangement was kept.
public enum WindowHistoryReason: String, Codable {
    case periodic
    case beforeDisplayChange
    case beforeRestore
}

/// One earlier arrangement of a layout variant.
public struct WindowHistoryEntry: Codable, Equatable, Identifiable {
    public var id: String
    public var reason: WindowHistoryReason
    public var savedAt: Date
    public var windows: [WindowSnapshot]

    public init(id: String = UUID().uuidString, reason: WindowHistoryReason, savedAt: Date,
                windows: [WindowSnapshot]) {
        self.id = id
        self.reason = reason
        self.savedAt = savedAt
        self.windows = windows
    }

    public func placementSummary(displays: [SavedDisplay]) -> String {
        WindowPlacement.summary(of: windows, displays: displays)
    }

    fileprivate var placements: Set<Placement> {
        Set(windows.map(Placement.init))
    }
}

/// Where a window is, without the title: Terminal and browser titles change
/// all the time and do not make a new arrangement.
private struct Placement: Hashable {
    let windowID: UInt32?
    let bundleID: String
    let displayMatchKey: String
    let displayIndex: Int
    let dx: Int
    let dy: Int
    let width: Int
    let height: Int

    init(_ window: WindowSnapshot) {
        windowID = window.windowID
        bundleID = window.bundleID
        displayMatchKey = window.displayMatchKey
        displayIndex = window.displayIndex
        dx = window.dx
        dy = window.dy
        width = window.width
        height = window.height
    }
}

/// JSON-file-backed history of earlier window arrangements, keyed by layout
/// variant id, newest first.
///
/// Separate from `WindowStore` so the current arrangement can keep being
/// rewritten cheaply and damage to one file cannot affect the other. Not
/// thread-safe; use from one queue (the app uses the main queue).
public final class WindowHistoryStore {
    private struct HistoryFile: Codable {
        var version = 1
        var variants: [String: [WindowHistoryEntry]] = [:]
    }

    public static let maxEntriesPerVariant = 30
    public static let periodicSpacing: TimeInterval = 15 * 60

    public private(set) var recoveredFromCorruption = false
    private let url: URL
    private let readOnly: Bool
    private var file: HistoryFile

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hdmi-defubar/window-history.json")
    }

    /// - Parameter readOnly: Suppresses every write, so inspection tools
    ///   cannot change the store just by looking at it.
    public init(url: URL, readOnly: Bool = false) {
        self.url = url
        self.readOnly = readOnly
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode(HistoryFile.self, from: data) {
                file = decoded
            } else {
                file = HistoryFile()
                recoveredFromCorruption = true
                if !readOnly {
                    let aside = URL(fileURLWithPath: url.path + ".corrupt")
                    try? FileManager.default.removeItem(at: aside)
                    try? FileManager.default.moveItem(at: url, to: aside)
                }
            }
        } else {
            file = HistoryFile()
        }
    }

    /// Newest first.
    public func entries(forVariantID id: String) -> [WindowHistoryEntry] {
        file.variants[id] ?? []
    }

    /// Keeps an arrangement unless it is empty, matches the newest entry or,
    /// for a periodic checkpoint, comes too soon after the newest entry.
    /// Returns whether an entry was added.
    @discardableResult
    public func checkpoint(_ windows: [WindowSnapshot], forVariantID id: String,
                           reason: WindowHistoryReason, at date: Date = Date()) -> Bool {
        guard !windows.isEmpty else { return false }
        let entry = WindowHistoryEntry(reason: reason, savedAt: date, windows: windows)
        let existing = file.variants[id] ?? []
        if let newest = existing.first {
            if newest.placements == entry.placements { return false }
            if reason == .periodic && date < newest.savedAt.addingTimeInterval(Self.periodicSpacing) {
                return false
            }
        }
        file.variants[id] = Array(([entry] + existing).prefix(Self.maxEntriesPerVariant))
        persist()
        return true
    }

    /// Makes an entry the variant's current arrangement. What is on screen is
    /// kept as a new entry first, so going back can itself be undone.
    public func recall(_ entry: WindowHistoryEntry, forVariantID id: String,
                       replacing live: [WindowSnapshot], in store: WindowStore,
                       at date: Date = Date()) {
        checkpoint(live, forVariantID: id, reason: .beforeRestore, at: date)
        store.save(entry.windows, forVariantID: id, at: date)
    }

    /// Drops history whose variant no longer exists.
    public func prune(keeping ids: Set<String>) {
        let kept = file.variants.filter { ids.contains($0.key) }
        guard kept.count != file.variants.count else { return }
        file.variants = kept
        persist()
    }

    private func persist() {
        guard !readOnly else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(file).write(to: url, options: .atomic)
        } catch {
            // Persist failures leave the in-memory state authoritative; the
            // caller surfaces store problems via recoveredFromCorruption only.
        }
    }
}
