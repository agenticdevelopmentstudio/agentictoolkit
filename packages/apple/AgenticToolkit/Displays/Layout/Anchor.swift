/// A side of a display.
///
/// Named `DisplayEdge` rather than `Edge`: `AgenticToolkitMacOS` already
/// exports an unrelated `Edge` (tab-bar docking side, not `Codable`) from a
/// tier that depends on this one, so this tier can neither reuse it nor sit
/// behind it — dependencies here point downward only.
public enum DisplayEdge: String, Codable, CaseIterable, Sendable {
    case left, right, top, bottom
}

/// A screen of another Mac shared through Universal Control.
public struct RemoteScreenID: Hashable, Codable, Sendable {
    public let device: String
    public let display: String

    public init(device: String, display: String) {
        self.device = device
        self.display = display
    }
}

public enum DisplayRef: Hashable, Codable, Sendable {
    case local(DisplayIdentity)
    case remote(RemoteScreenID)
}

/// "The child sits against `edge` of `parent`; the point `parentFraction` along
/// that edge coincides with the point `childFraction` along the child's facing
/// edge." Fractions run top→bottom on left/right edges, left→right on top/bottom.
public struct Anchor: Hashable, Codable, Sendable {
    public var parent: DisplayRef
    public var edge: DisplayEdge
    public var parentFraction: Double
    public var childFraction: Double

    public init(parent: DisplayRef, edge: DisplayEdge, parentFraction: Double, childFraction: Double) {
        self.parent = parent
        self.edge = edge
        self.parentFraction = parentFraction
        self.childFraction = childFraction
    }
}
