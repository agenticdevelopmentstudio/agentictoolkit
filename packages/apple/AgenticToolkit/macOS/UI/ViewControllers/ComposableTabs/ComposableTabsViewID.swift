import AppKit
import Foundation

/// Names one kind of view a tab can hold.
///
/// A bare `String` could not carry the rule "only views registered in the
/// registry are allowed" — every identifier looked like every other string, so
/// a typo in a layout spec was indistinguishable from a deliberate reference to
/// content this app doesn't have. Wrapping it lets `ComposableTabLayoutSpec`
/// state that rule in its own signatures and lets `validate(against:)` check it
/// (`explicit-over-implicit`, `fail-fast`).
public struct ComposableTabsViewID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    /// The numbered, tinted rectangle shown for a pane whose content type this
    /// app doesn't register. The raw value is a storage format — it is written
    /// into saved layouts — so it keeps the spelling it was first persisted
    /// under, whatever the host app is called now.
    public static let placeholder = ComposableTabsViewID("whippet.placeholder")
}

extension ComposableTabsViewID: CustomStringConvertible {
    public var description: String { rawValue }
}

/// Which way a split arranges its children.
///
/// `NSUserInterfaceLayoutOrientation` reads backwards here — its `.horizontal`
/// means "lay out horizontally", which AppKit spells `NSSplitView.isVertical ==
/// true` — so the layout vocabulary gets its own spelling, and the raw values
/// are the ones already written into every stored layout tree.
public enum ComposableTabsAxis: String, Sendable, CaseIterable {
    /// Children sit side by side, left to right.
    case horizontal
    /// Children are stacked, top to bottom.
    case vertical

    public var perpendicular: ComposableTabsAxis {
        self == .horizontal ? .vertical : .horizontal
    }

    public init(_ orientation: NSUserInterfaceLayoutOrientation) {
        self = (orientation == .horizontal) ? .horizontal : .vertical
    }

    public var orientation: NSUserInterfaceLayoutOrientation {
        self == .horizontal ? .horizontal : .vertical
    }
}
