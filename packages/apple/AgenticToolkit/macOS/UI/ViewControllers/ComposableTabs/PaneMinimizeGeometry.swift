import AgenticDeveloperToolkitUI
import Foundation

/// Which way a pane may shrink, and which side it docks to when it does.
///
/// Both answers are already in the layout tree, so nothing else has to hold an
/// opinion about them. A `LayoutNode` split is binary: the pane's *parent*
/// split fixes the axis, and the pane's *slot* in it fixes the side. A pane in
/// the `second` slot of a side-by-side split cannot dock leading — its sibling
/// is there — so offering that would be a control the user can press and
/// nothing sensible can happen.
///
/// Pure functions over the persisted tree: no AppKit, no view controller, no
/// split view. That is what makes the rules testable before any of the chrome
/// exists, and it is why this type sits in `ComposableTabs/` rather than next
/// to the pane — `LayoutNode` is layout-tree vocabulary, and a pane must stay
/// deployable somewhere that has no layout tree at all.
public enum PaneMinimizeGeometry {

    /// The split immediately containing `nodeID`, or `nil` when the node is the
    /// tree's root (or is not in the tree at all).
    ///
    /// `isFirst` distinguishes the two slots, which is the whole of the docking
    /// rule: `first` is the leading/top child, `second` the trailing/bottom one.
    public static func parentSplit(
        of nodeID: UUID,
        in root: LayoutNode
    ) -> (axis: ComposableTabsAxis, isFirst: Bool)? {
        guard case let .split(orientation, first, second) = root.kind else { return nil }

        if first.id == nodeID { return (orientation, true) }
        if second.id == nodeID { return (orientation, false) }

        return parentSplit(of: nodeID, in: first) ?? parentSplit(of: nodeID, in: second)
    }

    /// The edges the minimize picker should enable for this pane.
    ///
    /// Both edges of the live axis, so "shrink sideways" reads as one intent
    /// rather than a puzzle about which of the two arrows is legal. Which side
    /// the pane actually ends up on is `resolvedEdge`'s answer.
    ///
    /// A root leaf offers nothing: there is no sibling to take the space.
    public static func availableEdges(forNode nodeID: UUID, in root: LayoutNode) -> Set<PaneEdge> {
        guard let parent = parentSplit(of: nodeID, in: root) else { return [] }
        return parent.axis == .horizontal ? [.leading, .trailing] : [.top, .bottom]
    }

    /// The edge this pane actually docks to when `requested` is clicked, or
    /// `nil` when the request cannot be honoured.
    ///
    /// The arrow selects the axis; the slot selects the side. `nil` means
    /// either the pane has no parent split or the requested edge is off the
    /// live axis — both of which `availableEdges` already prevents in the UI,
    /// so a `nil` here is a caller that skipped it rather than a user action.
    public static func resolvedEdge(
        forNode nodeID: UUID,
        in root: LayoutNode,
        requested: PaneEdge
    ) -> PaneEdge? {
        guard let parent = parentSplit(of: nodeID, in: root) else { return nil }

        let axisIsHorizontal = parent.axis == .horizontal
        guard requested.isHorizontal == axisIsHorizontal else { return nil }

        if axisIsHorizontal {
            return parent.isFirst ? .leading : .trailing
        } else {
            return parent.isFirst ? .top : .bottom
        }
    }
}
