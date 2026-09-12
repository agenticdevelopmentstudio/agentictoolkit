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

    /// Every leaf id in this tree.
    ///
    /// A pane is addressed by its leaf id everywhere it is remembered — the
    /// focused pane of a tab, the rows `ProjectPaneStateStore` writes, the
    /// live controllers a rebuild reuses — so "is this id still in this tree?"
    /// gets asked from several places. It is answered here, once (`dry`):
    /// three private copies of this walk had already appeared, and a tree
    /// rewrite that one of them learned about and the others did not is
    /// exactly how a stale id outlives the pane it named.
    public var leafIDs: Set<UUID> {
        switch kind {
        case .leaf:
            return [id]
        case .split(_, let first, let second):
            return first.leafIDs.union(second.leafIDs)
        }
    }

    // MARK: - Sharing one arrangement

    /// This tree rebuilt to `template`'s shape, keeping its own node ids.
    ///
    /// The arrangement belongs to the project, but the ids in it belong to the
    /// tab: `layout_nodes.id` is a primary key, so two tabs holding one id
    /// cannot both be saved, and `rebuild(from:)` reuses a live pane by looking
    /// its node id up — hand a tab another tab's ids and every pane in it is
    /// discarded and built again from storage. So what travels between tabs is
    /// the shape, and each tab wears it in its own ids.
    ///
    /// Ids are handed out from this tree in reading order, a leaf's only to a
    /// leaf showing the same thing. A tab already in the template's shape
    /// therefore gets every one of its own ids back in the place it had it —
    /// the mirror of an arrangement onto a tab that already matches changes
    /// nothing — and a pane that merely moved is recognised where it lands and
    /// keeps what it remembered.
    public func reshaped(toMatch template: LayoutNode) -> LayoutNode {
        var ids = SpareIDs(harvestedFrom: self)
        return Self.reshape(template, drawingFrom: &ids)
    }

    /// This arrangement in ids nobody is using yet — a tab about to be made,
    /// wearing what the tabs beside it already wear.
    public func inFreshIDs() -> LayoutNode {
        var ids = SpareIDs()
        return Self.reshape(self, drawingFrom: &ids)
    }

    /// Whether the two trees differ only in the sizes they carry.
    ///
    /// The question a mirror asks before it acts: same structure means the tab
    /// can take the new sizes where it stands, and a tab whose panes are not
    /// torn down and rebuilt is a tab whose terminal keeps its shell. Ids are
    /// part of the answer — a tree with another tab's ids is another tab's
    /// panes, however alike the two shapes look.
    public func hasSameStructure(as other: LayoutNode) -> Bool {
        guard id == other.id else { return false }
        switch (kind, other.kind) {
        case (.split(let axis, let first, let second), .split(let otherAxis, let otherFirst, let otherSecond)):
            return axis == otherAxis
                && first.hasSameStructure(as: otherFirst)
                && second.hasSameStructure(as: otherSecond)
        case (.leaf(let contentType, let label), .leaf(let otherContentType, let otherLabel)):
            return contentType == otherContentType && label == otherLabel
        default:
            return false
        }
    }

    private static func reshape(_ template: LayoutNode, drawingFrom ids: inout SpareIDs) -> LayoutNode {
        switch template.kind {
        case .split(let orientation, let first, let second):
            return LayoutNode(
                id: ids.takeSplit(),
                kind: .split(
                    orientation: orientation,
                    first: reshape(first, drawingFrom: &ids),
                    second: reshape(second, drawingFrom: &ids)
                ),
                thicknessFraction: template.thicknessFraction
            )
        case .leaf(let contentType, let paneLabel):
            return LayoutNode(
                id: ids.take(forLeafShowing: contentType),
                kind: .leaf(contentType: contentType, paneLabel: paneLabel),
                thicknessFraction: template.thicknessFraction
            )
        }
    }

    /// The ids of one tree, queued to be worn by another of the same shape.
    ///
    /// A queue that runs out mints: the template may hold more panes than the
    /// tab being reshaped to it, and a node with no id is not a node.
    private struct SpareIDs {
        private var splits: ArraySlice<UUID>
        private var leaves: [ComposableTabsViewID: ArraySlice<UUID>]

        /// Nothing to hand out, so everything is minted.
        init() {
            splits = ArraySlice<UUID>()
            leaves = [:]
        }

        init(harvestedFrom node: LayoutNode) {
            var splits: [UUID] = []
            var leaves: [ComposableTabsViewID: [UUID]] = [:]
            Self.harvest(node, splits: &splits, leaves: &leaves)
            self.splits = splits[...]
            self.leaves = leaves.mapValues { $0[...] }
        }

        private static func harvest(
            _ node: LayoutNode,
            splits: inout [UUID],
            leaves: inout [ComposableTabsViewID: [UUID]]
        ) {
            switch node.kind {
            case .split(_, let first, let second):
                splits.append(node.id)
                harvest(first, splits: &splits, leaves: &leaves)
                harvest(second, splits: &splits, leaves: &leaves)
            case .leaf(let contentType, _):
                leaves[contentType, default: []].append(node.id)
            }
        }

        mutating func takeSplit() -> UUID {
            splits.popFirst() ?? UUID()
        }

        mutating func take(forLeafShowing contentType: ComposableTabsViewID) -> UUID {
            leaves[contentType]?.popFirst() ?? UUID()
        }
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
