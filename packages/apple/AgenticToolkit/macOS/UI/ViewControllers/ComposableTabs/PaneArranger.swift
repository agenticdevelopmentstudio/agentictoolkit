import Foundation

/// How a split tree's space is divided when panes are added or removed.
///
/// Injected rather than decided inside `ComposableTabsViewController`, because
/// two hosts in this app want different answers and neither is more correct:
/// the project window gives a new pane half of its neighbour's slot, and the
/// Document pane spreads every editor evenly. Fractions in, fractions out —
/// so an arranger is testable without a window, and a third rule later is a
/// new type rather than an edit to the container.
@MainActor
public protocol PaneArranger: AnyObject {

    /// The tree with thickness fractions as this arranger wants them.
    /// Node identities must be preserved: the live panes are matched back by
    /// `id`.
    func arrange(_ node: LayoutNode, along axis: ComposableTabsAxis) -> LayoutNode
}

/// Today's behaviour, and the default: a new pane takes the slot its
/// neighbour had, and the two inside share it. `ComposableTabsViewController`
/// already assigns those fractions as it splits, so there is nothing left to
/// do here — which is the point. The project window's layouts do not move.
@MainActor
public final class InheritedSlotArranger: PaneArranger {

    public init() {}

    public func arrange(_ node: LayoutNode, along axis: ComposableTabsAxis) -> LayoutNode { node }
}

/// Every pane along the arrangement axis gets an equal share of the whole.
///
/// The tree is binary, so equal thirds are not "three children at 1/3" — they
/// are an outer split at 1/3 and 2/3 whose larger half divides evenly again.
/// Weighting each child by how many leaves it contains produces that at any
/// depth.
@MainActor
public final class ProportionalArranger: PaneArranger {

    public init() {}

    public func arrange(_ node: LayoutNode, along axis: ComposableTabsAxis) -> LayoutNode {
        guard case .split(let orientation, let first, let second) = node.kind else { return node }

        // Walked whichever way this split runs. A split *across* the arrangement
        // axis is the user's own doing — an editor split downward inside a row of
        // editors — so its two halves keep the sizes they were given; but the
        // halves themselves are still visited, because a split along the axis
        // nested under a cross-axis one is as much a row of editors as any other.
        // Returning here instead left every pane below the first cross-axis split
        // arranged by nothing at all, so a fourth editor added to such a tab took
        // half of whichever divider the user had last dragged.
        var arrangedFirst = arrange(first, along: axis)
        var arrangedSecond = arrange(second, along: axis)

        let firstCount = Double(Self.leafCount(first))
        let secondCount = Double(Self.leafCount(second))
        let total = firstCount + secondCount
        if orientation == axis, total > 0 {
            arrangedFirst.thicknessFraction = firstCount / total
            arrangedSecond.thicknessFraction = secondCount / total
        }

        return LayoutNode.split(
            id: node.id,
            orientation: orientation,
            first: arrangedFirst,
            second: arrangedSecond,
            thicknessFraction: node.thicknessFraction
        )
    }

    private static func leafCount(_ node: LayoutNode) -> Int {
        switch node.kind {
        case .leaf:
            return 1
        case .split(_, let first, let second):
            return leafCount(first) + leafCount(second)
        }
    }
}
