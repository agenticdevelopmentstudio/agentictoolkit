import Foundation

/// Platform-neutral view model for one rail row; both `HTDVRailCellView`
/// (AppKit) and the UIKit cell render it.
public struct HTDVCellContent: Hashable, Sendable {
    public let label: String
    public let sublabel: String?
    public let systemImage: String?
    public let badge: HTDVBadge?
    /// True when the row leads to another rail (shows a chevron).
    public let isDisclosing: Bool

    public init(item: HTDVItem) {
        label = item.label
        sublabel = item.sublabel
        systemImage = item.systemImage
        badge = item.badge
        isDisclosing = item.leadsTo == .list
    }
}
