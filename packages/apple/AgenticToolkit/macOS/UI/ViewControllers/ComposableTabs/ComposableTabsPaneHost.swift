import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// What a split-view tree does when one of its panes asks for something.
///
/// The pane knows none of this. It makes five requests and is told what
/// happened, which is what lets the same `PaneViewController` sit in a
/// container with completely different rules.
///
/// Two decisions are made here and nowhere else:
///
/// - **Minimizing pins a split item** rather than collapsing it.
///   `minimumThickness == maximumThickness` freezes the pane at the thickness
///   of whatever chrome is left showing, and `holdingPriority = .defaultHigh`
///   makes AppKit take a window resize out of the neighbours instead of out of
///   the frozen pane. `preferredThicknessFraction` is left untouched: it is
///   what the pane gets back when it is restored.
/// - **Zooming collapses; it does not reparent.** Every split item off the path
///   from the root down to the zoomed pane collapses, and nothing moves in the
///   tree — so unzooming is un-collapsing, and a layout saved while zoomed
///   restores unzoomed and correct.
///
/// The two states are exclusive. A zoomed tab has every other pane collapsed,
/// so a minimized pane's space would have nowhere to go; a minimized pane that
/// zoomed would take over the tab as a 28pt rail. Each operation clears the
/// other and tells the panes involved, rather than disabling a button and
/// leaving the user to work out why.
extension ComposableTabsViewController: PaneHost {

    // MARK: - Close

    public func paneDidRequestClose(_ pane: PaneViewController) {
        guard let leaf = pane as? ComposableTabsPaneViewController else { return }
        // The pane is about to stop existing; a zoom pointing at it would leave
        // every other pane collapsed with nothing to restore them.
        if rootSplit()?.zoomedLeaf === leaf { setZoomedLeaf(nil) }
        // `remove` owns every rule about removal — the spec's veto, the
        // degenerate-split collapse, re-homing the first responder. Asking it
        // is the whole implementation.
        remove(leaf)
    }

    // MARK: - Minimizing

    public func availableMinimizeEdges(for pane: PaneViewController) -> Set<PaneEdge> {
        guard let leaf = pane as? ComposableTabsPaneViewController,
              let root = rootSplit() else { return [] }
        return PaneMinimizeGeometry.availableEdges(forNode: leaf.nodeID, in: root.snapshotNode())
    }

    public func paneDidRequestMinimize(_ pane: PaneViewController, to edge: PaneEdge) {
        guard let leaf = pane as? ComposableTabsPaneViewController,
              let root = rootSplit(),
              // The arrow the user clicked chooses the axis; the tree chooses
              // the side, and refuses outright if the axis is not the one the
              // parent split is laid out along.
              let resolved = PaneMinimizeGeometry.resolvedEdge(
                  forNode: leaf.nodeID, in: root.snapshotNode(), requested: edge),
              let owner = leaf.parent as? ComposableTabsViewController,
              let item = owner.splitViewItem(for: leaf)
        else { return }

        if root.zoomedLeaf != nil { setZoomedLeaf(nil) }

        // Read the dividers off the screen while the arrangement they describe
        // is still on it, so restoring gives back what the user had.
        root.captureThicknessFractions()
        owner.pin(item, to: leaf.minimizedThickness(for: resolved))
        leaf.setMinimized(to: resolved)
    }

    public func paneDidRequestRestore(_ pane: PaneViewController) {
        guard let leaf = pane as? ComposableTabsPaneViewController,
              let owner = leaf.parent as? ComposableTabsViewController,
              let item = owner.splitViewItem(for: leaf) else { return }
        owner.restoreSizing(of: item)
        leaf.setMinimized(to: nil)
    }

    /// Freezes an item at `thickness`. Deliberately does not touch
    /// `preferredThicknessFraction` — see the type comment.
    private func pin(_ item: NSSplitViewItem, to thickness: CGFloat) {
        item.minimumThickness = thickness
        item.maximumThickness = thickness
        item.holdingPriority = .defaultHigh
    }

    // MARK: - Zooming

    public func paneDidRequestZoom(_ pane: PaneViewController) {
        guard let leaf = pane as? ComposableTabsPaneViewController else { return }
        // A minimized pane that zoomed would take over the tab as a rail.
        if leaf.minimizedEdge != nil { paneDidRequestRestore(leaf) }
        setZoomedLeaf(leaf.isZoomed ? nil : leaf)
    }

    /// Applies a zoom from the root, whichever split is asked: a zoomed pane
    /// takes over the tab, not the half of it that happens to hold the pane.
    public func setZoomedLeaf(_ leaf: ComposableTabsPaneViewController?) {
        guard let root = rootSplit() else { return }
        root.zoomedLeaf?.setZoomed(false)
        root.zoomedLeaf = leaf
        leaf?.setZoomed(true)
        root.applyZoom(target: leaf?.nodeID)
    }

    /// Collapses every item in this subtree that is not on the path down to
    /// `target`; `nil` un-collapses the lot.
    ///
    /// A subtree that is itself collapsed is recursed into with `nil`, because
    /// its correct *interior* is the un-zoomed one — that is what makes
    /// unzooming a single pass rather than a remembered shadow tree.
    ///
    /// Set directly rather than through `animator()`: a collapse that has not
    /// finished animating is a collapse the next line of code cannot see, and
    /// `isCollapsed` is settable in code regardless of `canCollapse`, which
    /// governs only what a divider drag may do.
    func applyZoom(target: UUID?) {
        for child in layoutChildren {
            let onPath = target == nil || Self.subtree(child, contains: target!)
            if let item = splitViewItem(for: child.viewController) {
                item.isCollapsed = !onPath
            }
            (child as? ComposableTabsViewController)?.applyZoom(target: onPath ? target : nil)
        }
    }

    private static func subtree(_ child: any ComposableTabsChild, contains id: UUID) -> Bool {
        if let leaf = child as? ComposableTabsPaneViewController { return leaf.nodeID == id }
        guard let split = child as? ComposableTabsViewController else { return false }
        return split.layoutChildren.contains { subtree($0, contains: id) }
    }

    // MARK: - Re-applying what was persisted

    /// Puts the tree back into the shape each pane's store remembers.
    ///
    /// A pane restores its own *chrome* as it loads — it reads its own store
    /// and needs nobody's help. Only the host can pin a split item or collapse
    /// the ancestors of a zoomed pane, so that half waits until the whole tree
    /// exists and happens here, once, from the root.
    ///
    /// Minimize first, then zoom: a zoom collapses items, and pinning an item
    /// that is already collapsed reads as a pane that never came back.
    public func applyPersistedPaneState() {
        guard isRoot else { return }
        let leaves = allLeaves()
        for leaf in leaves {
            guard let edge = leaf.persistedMinimizeEdge else { continue }
            paneDidRequestMinimize(leaf, to: edge)
        }
        if let zoomed = leaves.first(where: { $0.persistedZoomed }) {
            setZoomedLeaf(zoomed)
        }
    }

    /// Re-asks every pane which edges it may minimize toward. The answer is a
    /// fact about the tree, so it is re-asked whenever the tree changes.
    func refreshPaneControls() {
        for leaf in allLeaves() { leaf.refreshControlAvailability() }
    }
}
