import Foundation

/// JSON-file-backed store of remembered window arrangements, keyed by layout
/// variant id.
///
/// Deliberately a separate file from the layouts: Window arrangements are
/// rewritten far more often and are far less precious, so a corrupt or
/// oversized window file must not be able to take the display layouts with it.
/// Not thread-safe; use from one queue (the app uses the main queue).
public final class WindowStore {
    private struct WindowFile: Codable {
        var version = 1
        var layouts: [String: WindowLayoutSnapshot] = [:]
    }

    public private(set) var recoveredFromCorruption = false
    private let url: URL
    private let readOnly: Bool
    private var file: WindowFile

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hdmi-defubar/windows.json")
    }

    /// - Parameter readOnly: Suppresses every write, so inspection tools
    ///   cannot change the store just by looking at it.
    public init(url: URL, readOnly: Bool = false) {
        self.url = url
        self.readOnly = readOnly
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode(WindowFile.self, from: data) {
                file = decoded
            } else {
                file = WindowFile()
                recoveredFromCorruption = true
                if !readOnly {
                    let aside = URL(fileURLWithPath: url.path + ".corrupt")
                    try? FileManager.default.removeItem(at: aside)
                    try? FileManager.default.moveItem(at: url, to: aside)
                }
            }
        } else {
            file = WindowFile()
        }
    }

    public func snapshot(forVariantID id: String) -> WindowLayoutSnapshot? {
        file.layouts[id]
    }

    /// Stores an arrangement. An unchanged arrangement is not written back, so
    /// the capture poll only touches the disk when something actually moved.
    /// Returns whether anything was written.
    @discardableResult
    public func save(_ windows: [WindowSnapshot], forVariantID id: String,
                     at date: Date = Date()) -> Bool {
        if file.layouts[id]?.windows == windows { return false }
        file.layouts[id] = WindowLayoutSnapshot(capturedAt: date, windows: windows)
        persist()
        return true
    }

    public func delete(forVariantID id: String) {
        guard file.layouts.removeValue(forKey: id) != nil else { return }
        persist()
    }

    /// Drops arrangements whose variant no longer exists.
    public func prune(keeping ids: Set<String>) {
        let kept = file.layouts.filter { ids.contains($0.key) }
        guard kept.count != file.layouts.count else { return }
        file.layouts = kept
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
