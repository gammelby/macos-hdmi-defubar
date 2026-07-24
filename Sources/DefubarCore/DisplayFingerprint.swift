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

    /// Matching identity. The model number is excluded whenever a serial is
    /// present because some monitors (Samsung Odyssey G7 family) report a
    /// different EDID product id across reconnects; the serial is the more
    /// stable of the two. Serial 0 means "not exposed" and falls back to the
    /// model number.
    public var matchKey: String {
        let prefix = isBuiltin ? "b" : "e"
        return serial != 0 ? "\(prefix)-\(vendor)-s\(serial)" : "\(prefix)-\(vendor)-m\(model)"
    }

    /// Key identifying a set of simultaneously connected displays.
    public static func setKey(for fingerprints: [DisplayFingerprint]) -> String {
        fingerprints.map(\.matchKey).sorted().joined(separator: "+")
    }
}
