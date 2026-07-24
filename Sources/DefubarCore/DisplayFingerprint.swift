import Foundation

/// Stable hardware identity of a display, independent of the churned
/// WindowServer display UUID.
public struct DisplayFingerprint: Codable, Equatable, Hashable {
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var isBuiltin: Bool

    public init(vendor: UInt32, model: UInt32, serial: UInt32, isBuiltin: Bool) {
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.isBuiltin = isBuiltin
    }

    /// Matching identity. Serial 0 means "not exposed" and is omitted so the
    /// fingerprint degrades to vendor + model.
    public var matchKey: String {
        let prefix = isBuiltin ? "b" : "e"
        let base = "\(prefix)-\(vendor)-\(model)"
        return serial != 0 ? "\(base)-\(serial)" : base
    }

    /// Key identifying a set of simultaneously connected displays.
    public static func setKey(for fingerprints: [DisplayFingerprint]) -> String {
        fingerprints.map(\.matchKey).sorted().joined(separator: "+")
    }
}
