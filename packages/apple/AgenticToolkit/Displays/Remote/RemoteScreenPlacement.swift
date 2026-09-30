/// Whether the adapter can write placements, and why not when it cannot.
public enum RemoteSupport: Equatable, Sendable {
    case supported
    case unsupported(String)
}

/// A screen belonging to another Mac, shared through Universal Control.
public struct RemoteScreen: Equatable, Sendable {
    public let id: RemoteScreenID
    public init(id: RemoteScreenID) { self.id = id }
}

public enum RemoteScreenError: Error, Equatable, Sendable {
    case unsupported(String)
    case notFound(RemoteScreenID)
    case unreadable(String)
}

/// One remote screen and its current anchor (nil when it has none).
public struct RemoteScreenAnchor: Equatable, Sendable {
    public let screen: RemoteScreenID
    public let anchor: Anchor?

    public init(screen: RemoteScreenID, anchor: Anchor?) {
        self.screen = screen
        self.anchor = anchor
    }
}

/// Placement of screens that belong to other Macs (Universal Control).
/// Nothing outside a `RemoteScreenPlacement` implementation knows how
/// remote placements are discovered or written.
///
/// The per-machine inputs that change at runtime are passed on every call,
/// never stored: `localDisplayUUIDs` are the CoreGraphics UUIDs of this
/// Mac's online displays (they change with hotplug), and
/// `preferredParentUUID` picks the parent when a remote screen touches
/// several local displays.
@MainActor
public protocol RemoteScreenPlacement: AnyObject {
    var support: RemoteSupport { get }
    /// Every remote screen currently anchored against one of
    /// `localDisplayUUIDs`, then each of `including` not already listed,
    /// each with its current anchor (nil when it has none), all read from
    /// one snapshot of the backing store. `preferredParentUUID` gives the
    /// preferred parent per screen, for a screen touching several displays.
    func placements(
        including screens: [RemoteScreenID], localDisplayUUIDs: Set<String>,
        preferredParentUUID: (RemoteScreenID) -> String?
    ) throws(RemoteScreenError) -> [RemoteScreenAnchor]
    func setPlacement(
        _ anchor: Anchor, for screen: RemoteScreenID, localDisplayUUIDs: Set<String>
    ) throws(RemoteScreenError)
}
