import Foundation

/// A persisted layout tree. Storage vocabulary — it outlives any one view
/// registry — but its two payloads are typed rather than free strings so a
/// spec, a registry and a stored tree can be compared without stringly
/// guesswork. Both types are `RawRepresentable` over exactly the strings the
/// schema already holds, so no stored layout changes meaning.
public struct LayoutNode: Sendable {
    public indirect enum Kind: Sendable {
        case split(orientation: ComposableTabsAxis, first: LayoutNode, second: LayoutNode)
        case leaf(contentType: ComposableTabsViewID, paneLabel: String?)
    }

    public let id: UUID
    public let kind: Kind

    /// This node's share of the split it sits in, `0...1`, or `nil` for a node
    /// nobody has sized — the root of a tab, or a pane the user has never
    /// dragged a divider next to.
    ///
    /// Stored per *child* rather than as a divider position on the split,
    /// because that is the form the arrangement survives a window resize in:
    /// a position is points on the display it was saved from, a fraction is
    /// the same arrangement on any display.
    public var thicknessFraction: Double?

    public static func leaf(
        id: UUID = UUID(),
        contentType: ComposableTabsViewID,
        paneLabel: String? = nil,
        thicknessFraction: Double? = nil
    ) -> LayoutNode {
        LayoutNode(
            id: id,
            kind: .leaf(contentType: contentType, paneLabel: paneLabel),
            thicknessFraction: thicknessFraction
        )
    }

    public static func split(
        id: UUID = UUID(),
        orientation: ComposableTabsAxis,
        first: LayoutNode,
        second: LayoutNode,
        thicknessFraction: Double? = nil
    ) -> LayoutNode {
        LayoutNode(
            id: id,
            kind: .split(orientation: orientation, first: first, second: second),
            thicknessFraction: thicknessFraction
        )
    }

    /// The same node, sized as whatever it is replacing.
    ///
    /// A fraction describes a *slot* in a split, not the subtree filling it, so
    /// every rewrite that moves a subtree into another one's place has to carry
    /// the slot's size across or the surrounding panes visibly jump.
    public func occupying(_ slot: LayoutNode) -> LayoutNode {
        var copy = self
        copy.thicknessFraction = slot.thicknessFraction
        return copy
    }
}

public struct TabRecord {
    public let id: UUID
    /// Tabs sharing a `groupID` are one project-level tab: one member per
    /// edge, all with the same title. Defaults to `id` (a group of one).
    public let groupID: UUID
    public var edge: Edge
    public var title: String
    public var root: LayoutNode
    public var focusedNodeID: UUID?
    /// The directory this tab's panes work in. `nil` means the project directory.
    public var workingDirectory: URL?

    public init(
        id: UUID = UUID(),
        groupID: UUID? = nil,
        edge: Edge = .top,
        title: String,
        root: LayoutNode,
        focusedNodeID: UUID? = nil,
        workingDirectory: URL? = nil
    ) {
        self.id = id
        self.groupID = groupID ?? id
        self.edge = edge
        self.title = title
        self.root = root
        self.focusedNodeID = focusedNodeID
        self.workingDirectory = workingDirectory
    }
}
