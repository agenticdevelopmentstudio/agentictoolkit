import ColorSync
import CoreGraphics

/// Stable identity of a physical display across reboots and reconnections.
/// Keyed by the CoreGraphics display UUID when present, else vendor:model:serial.
/// Never uses the session-scoped `CGDirectDisplayID`.
public struct DisplayIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
    public let uuid: String?
    public let vendor: UInt32
    public let model: UInt32
    public let serial: UInt32

    public init(uuid: String?, vendor: UInt32, model: UInt32, serial: UInt32) {
        self.uuid = uuid
        self.vendor = vendor
        self.model = model
        self.serial = serial
    }

    /// The comparison key: UUID when known, else `vendor:model:serial`.
    public var key: String { uuid ?? "\(vendor):\(model):\(serial)" }
    public var description: String { key }

    public static func == (lhs: DisplayIdentity, rhs: DisplayIdentity) -> Bool { lhs.key == rhs.key }
    public func hash(into hasher: inout Hasher) { hasher.combine(key) }

    public static func of(_ displayID: CGDirectDisplayID) -> DisplayIdentity {
        DisplayIdentity(
            uuid: uuidString(for: displayID),
            vendor: CGDisplayVendorNumber(displayID),
            model: CGDisplayModelNumber(displayID),
            serial: CGDisplaySerialNumber(displayID)
        )
    }

    /// The CoreGraphics UUID string for a display, e.g. `A6E83318-CF7F-...`.
    public static func uuidString(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
