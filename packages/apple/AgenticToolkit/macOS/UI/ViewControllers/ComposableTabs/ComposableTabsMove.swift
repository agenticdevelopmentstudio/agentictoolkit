import Foundation

import AgenticToolkitCore

/// Moving one pane around a tab's layout tree.
///
/// Pure tree arithmetic over `LayoutNode`, with no view controllers in sight:
/// the same rules then answer both "which arrows are live" and "what does this
/// arrow do", instead of one table of availability drifting away from the code
/// that performs the move (`dry`).
public enum ComposableTabsMove {

    public typealias Direction = ComposableTabsViewController.Direction

    /// The directions the pane may actually travel — defined as the directions
    /// that produce a tree, so an enabled arrow can never fail.
    public static func availableDirections(for leafID: UUID, in root: LayoutNode) -> Set<Direction> {
        var available: Set<Direction> = []
        for direction in [Direction.left, .right, .above, .below]
        where moving(leafID, direction, in: root) != nil {
            available.insert(direction)
        }
        return available
    }

    /// The tree that results from moving `leafID` one step in `direction`, or
    /// `nil` if there is nowhere for it to go.
    ///
    /// Two rules, in order:
    ///
    /// 1. If some ancestor splits *along* the direction and holds the pane on
    ///    the far side of it, the subtree on the near side is what the pane
    ///    moves into. The *nearest* such ancestor, so a move is one slot rather
    ///    than a jump to the edge. Sideways the pane steps across into that
    ///    slot; up and down it expands into it, keeping its own band as well.
    /// 2. Failing that, the pane may still be pulled out of the split it sits in
    ///    *across* the direction — out of a column to the left or right, out of
    ///    a row above or below. That is the whole of "right is available if
    ///    there are panes above or below", and its mirror image: a pane with
    ///    anything beside it always has an up and a down, even when nothing is
    ///    there yet.
    ///
    /// Only a pane that is alone in its tab has nowhere to go at all.
    public static func moving(
        _ leafID: UUID,
        _ direction: Direction,
        in root: LayoutNode
    ) -> LayoutNode? {
        guard let pane = leaf(leafID, in: root) else { return nil }

        // Where the pane must sit for `direction` to have a neighbour: moving
        // left means the pane is the *second* child of a horizontal split, and
        // the first child is what it moves into.
        let paneSide = direction.placesNewPaneFirst ? 1 : 0
        let ancestors = ancestry(of: leafID, in: root)

        if let split = ancestors.last(where: { $0.axis == direction.axis && $0.childIndex == paneSide }) {
            return replacing(split.node.id, in: root) { node in
                direction.axis == .vertical
                    ? expanding(node, pane: pane, paneSide: paneSide)
                    : stepAcross(node, pane: pane, paneSide: paneSide, direction: direction)
            }
        }

        guard let stack = ancestors.last(where: { $0.axis != direction.axis }) else { return nil }

        return replacing(stack.node.id, in: root) { node in
            // The pane is inside this stack, and a stack always holds two
            // children, so something always survives its departure.
            guard let survivor = removing(leafID, from: node) else { return node }
            return pair(pane, survivor, axis: direction.axis, paneFirst: direction.placesNewPaneFirst)
                .occupying(node)
        }
    }

    // MARK: - The moves

    /// Rule 1, up or down: the pane grows into the band the other side of
    /// `split` occupies, and everything it displaces is pushed to its right.
    ///
    /// The pane keeps its own band *and* gains the neighbouring one, so it ends
    /// up spanning both — which is what makes this an expansion rather than the
    /// swap up and down used to perform, where the pane came out exactly the
    /// size it went in. What it displaces stays stacked in the order it already
    /// had, in a column beside the pane: the neighbour it expanded into reduces
    /// in width to make room, and anything that shared the pane's own band was
    /// already that width and simply moves to the right.
    ///
    /// Sideways there is no equivalent — `stepAcross` below — because a pane
    /// expanding left or right would have to push its neighbour *below* it, and
    /// a row is not asking to become a column.
    private static func expanding(
        _ split: LayoutNode,
        pane: LayoutNode,
        paneSide: Int
    ) -> LayoutNode {
        guard case .split(let axis, let first, let second) = split.kind else { return split }
        let paneSubtree = paneSide == 0 ? first : second
        let neighbour = paneSide == 0 ? second : first

        // The pane was this whole band, so there is nothing left to stack with
        // the neighbour and it stands beside the pane on its own.
        guard let survivor = removing(pane.id, from: paneSubtree) else {
            return pair(pane, neighbour, axis: .horizontal, paneFirst: true).occupying(split)
        }

        let displaced = paneSide == 0
            ? LayoutNode.split(orientation: axis, first: survivor, second: neighbour)
            : LayoutNode.split(orientation: axis, first: neighbour, second: survivor)
        return pair(pane, displaced, axis: .horizontal, paneFirst: true).occupying(split)
    }

    /// Rule 1, left or right: lift the pane out of its side of `split` and put
    /// it into the other side.
    private static func stepAcross(
        _ split: LayoutNode,
        pane: LayoutNode,
        paneSide: Int,
        direction: Direction
    ) -> LayoutNode {
        guard case .split(let axis, let first, let second) = split.kind else { return split }
        let paneSubtree = paneSide == 0 ? first : second
        let targetSubtree = paneSide == 0 ? second : first

        let newTarget = inserting(pane, into: targetSubtree, direction: direction)
        // The pane was this whole side, so the side goes with it and the split
        // collapses into the target.
        guard let newSide = removing(pane.id, from: paneSubtree) else {
            return newTarget.occupying(split)
        }

        return paneSide == 0
            ? .split(id: split.id, orientation: axis, first: newSide, second: newTarget,
                     thicknessFraction: split.thicknessFraction)
            : .split(id: split.id, orientation: axis, first: newTarget, second: newSide,
                     thicknessFraction: split.thicknessFraction)
    }

    /// Where the pane lands inside the subtree it moved into.
    ///
    /// Along the direction's own axis it keeps descending toward the pane's old
    /// position, so a move is one slot rather than a jump to the far edge.
    /// Across it — a vertical stack entered from the left or right — the pane
    /// goes on top of the stack, which is the only placement that does not have
    /// to guess which of the stacked panes the user meant.
    private static func inserting(
        _ pane: LayoutNode,
        into node: LayoutNode,
        direction: Direction
    ) -> LayoutNode {
        guard case .split(let axis, let first, let second) = node.kind else {
            return pair(pane, node, axis: direction.axis, paneFirst: direction.placesNewPaneFirst)
                .occupying(node)
        }
        guard axis == direction.axis else {
            return pair(pane, node, axis: axis, paneFirst: true).occupying(node)
        }
        return direction.placesNewPaneFirst
            ? .split(
                id: node.id, orientation: axis,
                first: first, second: inserting(pane, into: second, direction: direction),
                thicknessFraction: node.thicknessFraction)
            : .split(
                id: node.id, orientation: axis,
                first: inserting(pane, into: first, direction: direction), second: second,
                thicknessFraction: node.thicknessFraction)
    }

    /// Puts two subtrees side by side in a brand new split — and drops the size
    /// each was carrying.
    ///
    /// A `thicknessFraction` is a share of one particular split, so it means
    /// nothing in a split that did not exist a moment ago: the pane's came from
    /// the arrangement it just left (often on the other axis), and `other`'s was
    /// its share of the slot this new split now fills. Keeping either would put
    /// two unrelated numbers on the same divider, and they would not add up.
    /// Cleared, the descriptors' preferred fractions size the new divider; the
    /// slot around it is preserved by the `occupying` at every call site.
    private static func pair(
        _ pane: LayoutNode,
        _ other: LayoutNode,
        axis: ComposableTabsAxis,
        paneFirst: Bool
    ) -> LayoutNode {
        var pane = pane, other = other
        pane.thicknessFraction = nil
        other.thicknessFraction = nil
        return paneFirst
            ? .split(orientation: axis, first: pane, second: other)
            : .split(orientation: axis, first: other, second: pane)
    }

    // MARK: - Tree utilities

    /// One step of the path from the root down to a leaf.
    private struct Step {
        let node: LayoutNode
        let axis: ComposableTabsAxis
        /// Which of `node`'s children the leaf is under.
        let childIndex: Int
    }

    /// The splits above `leafID`, outermost first — so `last(where:)` finds the
    /// *nearest* ancestor matching a rule.
    private static func ancestry(of leafID: UUID, in node: LayoutNode) -> [Step] {
        guard case .split(let axis, let first, let second) = node.kind else { return [] }
        if contains(leafID, first) {
            return [Step(node: node, axis: axis, childIndex: 0)] + ancestry(of: leafID, in: first)
        }
        if contains(leafID, second) {
            return [Step(node: node, axis: axis, childIndex: 1)] + ancestry(of: leafID, in: second)
        }
        return []
    }

    private static func contains(_ id: UUID, _ node: LayoutNode) -> Bool {
        if node.id == id { return true }
        guard case .split(_, let first, let second) = node.kind else { return false }
        return contains(id, first) || contains(id, second)
    }

    public static func leaf(_ id: UUID, in node: LayoutNode) -> LayoutNode? {
        if node.id == id, case .leaf = node.kind { return node }
        guard case .split(_, let first, let second) = node.kind else { return nil }
        return leaf(id, in: first) ?? leaf(id, in: second)
    }

    /// The tree without `id`. A split left with one child collapses into it,
    /// which is what keeps a move from leaving one-legged splits behind.
    public static func removing(_ id: UUID, from node: LayoutNode) -> LayoutNode? {
        if node.id == id { return nil }
        guard case .split(let axis, let first, let second) = node.kind else { return node }
        let newFirst = removing(id, from: first)
        let newSecond = removing(id, from: second)
        switch (newFirst, newSecond) {
        case (nil, nil): return nil
        case (let survivor?, nil), (nil, let survivor?): return survivor.occupying(node)
        case (let left?, let right?):
            return .split(id: node.id, orientation: axis, first: left, second: right,
                          thicknessFraction: node.thicknessFraction)
        }
    }

    /// Rewrites the subtree with `id` in place, leaving the rest untouched.
    private static func replacing(
        _ id: UUID,
        in node: LayoutNode,
        with transform: (LayoutNode) -> LayoutNode
    ) -> LayoutNode {
        if node.id == id { return transform(node).occupying(node) }
        guard case .split(let axis, let first, let second) = node.kind else { return node }
        return .split(
            id: node.id,
            orientation: axis,
            first: replacing(id, in: first, with: transform),
            second: replacing(id, in: second, with: transform),
            thicknessFraction: node.thicknessFraction
        )
    }
}
