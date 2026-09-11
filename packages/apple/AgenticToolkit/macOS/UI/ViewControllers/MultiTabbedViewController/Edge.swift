import Foundation

/// Which side of `MultiTabbedViewController`'s container a tab bar is docked to.
/// The raw value doubles as the persistence and scripting name.
public enum Edge: String, CaseIterable, Sendable {
    case top
    case right
    case bottom
    case left

    /// Whether a bar on this edge lays its tabs out down a column rather than
    /// across a row.
    ///
    /// Which is also what decides whether its tabs have room to be a stack:
    /// a column of cards can overlap and recede down its length, while a row
    /// of them runs out of the window long before it has any depth to show.
    public var isVertical: Bool {
        switch self {
        case .left, .right: return true
        case .top, .bottom: return false
        }
    }

    /// What to call the edge in menus and settings. Separate from `rawValue`
    /// because that one is a persisted key — it may not change when the words
    /// on screen do.
    public var displayName: String {
        switch self {
        case .top: return "Top"
        case .right: return "Right"
        case .bottom: return "Bottom"
        case .left: return "Left"
        }
    }
}
