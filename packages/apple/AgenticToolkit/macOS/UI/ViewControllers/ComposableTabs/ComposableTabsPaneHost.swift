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
        // `remove` owns every rule about removal — the spec's veto, the
        // degenerate-split collapse, re-homing the first responder — and a
        // refused close has to leave the pane exactly as it found it. Clearing
        // the zoom is not free: `setZoomedLeaf(nil)` calls `setZoomed(false)`
        // on the pane, which deletes the row that remembers it was zoomed. So
        // the two conditions `remove` refuses on are asked here first, and a
        // pane the spec will not let go of keeps its zoom instead of quietly
        // losing it on every rejected click.
        //
        // And a refusal is said out loud. `PaneHost` gives the pane no
        // `canClose` to grey its button with, deliberately — the host decides,
        // and it may decide differently a moment later — so the only place the
        // "no" can be reported is here, where it is made. Arrange mode's
        // `confirmAndRemove()` already beeps at exactly this refusal; the title
        // bar's close button reached the same rule and said nothing, which
        // reads as a dead button rather than a protected pane.
        guard layoutChildren.contains(where: { $0.viewController === leaf }),
              (rootSplit() ?? self).canRemoveLeaf(leaf) else {
            NSSound.beep()
            return
        }
        // The pane is about to stop existing; a zoom pointing at it would leave
        // every other pane collapsed with nothing to restore them.
        if rootSplit()?.zoomedLeaf === leaf { setZoomedLeaf(nil) }
        remove(leaf)
    }

    // MARK: - Minimizing

    public func availableMinimizeEdges(for pane: PaneViewController) -> Set<PaneEdge> {
        guard let leaf = pane as? ComposableTabsPaneViewController,
              let root = rootSplit() else { return [] }
        return PaneMinimizeGeometry.availableEdges(forNode: leaf.nodeID, in: root.snapshotNode())
    }

    /// The split holding `leaf`, on screen or not.
    ///
    /// Deliberately not `leaf.parent`: a pane only becomes a child view
    /// controller when a split view item is built for it, so `parent` is nil
    /// for every pane on a tab that has never been displayed. `host` is stamped
    /// from `layoutChildren` — see its `didSet` — which is true of a tab
    /// nobody has switched to.
    private func owningSplit(of leaf: ComposableTabsPaneViewController)
        -> ComposableTabsViewController? {
        leaf.host as? ComposableTabsViewController
    }

    /// A minimize is two halves, and only one of them needs a view.
    ///
    /// The pane's own state — and the row `setMinimized(to:)` writes — is set
    /// unconditionally, because a tab that has never been displayed has no
    /// split items and refusing on that basis is how a scripted minimize on a
    /// background tab used to vanish without a trace. The geometry half is
    /// applied here when there *is* an item, and otherwise by
    /// `applyPersistedPaneState()` on the tab's first display: that reads
    /// `persistedMinimizeEdge`, which is exactly what was just written. So the
    /// request survives to the screen either way.
    ///
    /// The `resolvedEdge` guard stays a guard. A tree that has no such edge is
    /// a real refusal — a genuine answer to a genuine question — not a
    /// consequence of nothing having loaded yet.
    public func paneDidRequestMinimize(_ pane: PaneViewController, to edge: PaneEdge) {
        guard let leaf = pane as? ComposableTabsPaneViewController,
              let root = rootSplit(),
              // The arrow the user clicked chooses the axis; the tree chooses
              // the side, and refuses outright if the axis is not the one the
              // parent split is laid out along.
              let resolved = PaneMinimizeGeometry.resolvedEdge(
                  forNode: leaf.nodeID, in: root.snapshotNode(), requested: edge)
        else { return }

        // Unzooming un-collapses items, and AppKit has not laid them out again
        // by the next line — so the frames still describe the zoom. The
        // fractions captured on the way *into* the zoom are the truth, and they
        // are still sitting in the tree untouched, so the capture is skipped
        // rather than allowed to overwrite them with the zoomed arrangement.
        let wasZoomed = root.zoomedLeaf != nil
        if wasZoomed { setZoomedLeaf(nil) }

        // Otherwise read the dividers off the screen while the arrangement they
        // describe is still on it, so restoring gives back what the user had.
        // On an unloaded tree this writes nothing — it guards `isViewLoaded`
        // and a real thickness — which is what keeps the persisted fractions
        // from being overwritten with geometry that does not exist yet.
        if !wasZoomed { root.captureThicknessFractions() }
        if let owner = owningSplit(of: leaf), let item = owner.splitViewItem(for: leaf) {
            owner.pin(item, to: leaf.minimizedThickness(for: resolved))
        }
        leaf.setMinimized(to: resolved)
    }

    /// The mirror of `paneDidRequestMinimize`, and unconditional for the same
    /// reason: clearing the pane's row is the half that must land, or the tab's
    /// first display re-minimizes a pane the script just restored. Un-pinning
    /// needs an item and waits for one.
    public func paneDidRequestRestore(_ pane: PaneViewController) {
        guard let leaf = pane as? ComposableTabsPaneViewController else { return }
        if let owner = owningSplit(of: leaf), let item = owner.splitViewItem(for: leaf) {
            owner.restoreSizing(of: item)
        }
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
        // Before the zoom goes up, for the same reason `paneDidRequestMinimize`
        // captures first: a divider dragged in the last 300ms is still sitting
        // in the debounce, and once `zoomedLeaf` is set the capture refuses to
        // run at all — so the drag would be dropped. On the way back *out* of a
        // zoom this is a no-op, which is correct: what is on screen then is the
        // collapsed arrangement, not sizes worth keeping.
        //
        // Unconditional, including when `leaf` is minimized. The restore below
        // has not been laid out yet, so that pane's split is still showing its
        // rail — and `captureThicknessFractions` skips a split showing a rail,
        // which is exactly the case this used to guard by hand. Declining the
        // whole call instead would suppress the walk over every *other* split
        // too, dropping a drag somewhere unrelated for the sake of a split that
        // now declines itself.
        rootSplit()?.captureThicknessFractions()
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
        // One snapshot for the whole pass, for the same reason
        // `reapplyPaneState()` takes one: pinning an item moves nothing in the
        // tree, so the shape cannot change underneath it.
        let tree = snapshotNode()
        for leaf in leaves {
            guard let edge = leaf.persistedMinimizeEdge else { continue }
            // The edge was resolved against the tree the pane lived in last
            // launch, and the layout spec can have changed the axis under it
            // since. `paneDidRequestMinimize` refuses an edge the tree no
            // longer admits — by returning, silently — while the pane's own
            // `restorePersistedState()` has *already* drawn its rail off the
            // same row. Ignoring the refusal would leave a pane holding its
            // full share of the split with nothing but a 28pt rail in it and
            // empty space beside it, and no control able to undo that. Giving
            // the pane back is the only outcome the user can act on, and it is
            // what `reapplyPaneState()` already does with the identical case.
            // It also clears the row, so the next launch does not re-try an
            // edge the layout has already refused once.
            guard PaneMinimizeGeometry.resolvedEdge(
                forNode: leaf.nodeID, in: tree, requested: edge) != nil else {
                paneDidRequestRestore(leaf)
                continue
            }
            paneDidRequestMinimize(leaf, to: edge)
        }
        if let zoomed = leaves.first(where: { $0.persistedZoomed }) {
            setZoomedLeaf(zoomed)
        }
    }

    /// Re-states the pane state onto split items that have just been rebuilt.
    ///
    /// `split`, `remove` and `replaceChild` all re-create `NSSplitViewItem`s
    /// through `makeItem(for:)`, which vends them uncollapsed and unpinned.
    /// Minimize and zoom live on the *panes*, not on the items, so without this
    /// a minimized pane comes back full size while `minimizedEdge` still reads
    /// non-nil, and closing a pane while another is zoomed leaves the tab
    /// visibly unzoomed with `zoomedLeaf` still set — the screen and the model
    /// disagreeing, and the zoom button a no-op in one direction.
    ///
    /// Unlike `applyPersistedPaneState()`, which reads each pane's *store* and
    /// is a one-time restore, this runs on every rebuild and holds no latch: it
    /// only re-applies what the live panes already say about themselves.
    ///
    /// Both operations are idempotent, and setting `isCollapsed` to the value it
    /// already has posts nothing, so re-running this settles rather than
    /// re-triggering the resize notification that led here.
    func reapplyPaneState() {
        guard isRoot else { return }
        let leaves = allLeaves()

        // A zoom pointing at a pane that is no longer in the tree can never be
        // undone by clicking anything, and it leaves every surviving pane
        // collapsed. Removing the pane removes the zoom with it.
        if let zoomed = zoomedLeaf, !leaves.contains(where: { $0 === zoomed }) {
            zoomed.setZoomed(false)
            zoomedLeaf = nil
            applyZoom(target: nil)
        }

        // One snapshot for the whole pass: re-resolving an edge does not move
        // anything in the tree, so the shape cannot change underneath it.
        let tree = snapshotNode()
        for leaf in leaves {
            guard let edge = leaf.minimizedEdge else { continue }
            let owner = owningSplit(of: leaf)
            let item = owner.flatMap { $0.splitViewItem(for: leaf) }
            // The stored edge was resolved against the tree the pane used to
            // live in, and a rebuild can change the axis under it — a close
            // that promotes a pane out of a vertical split into a horizontal
            // one leaves it carrying `.top`. Pinning that would freeze the pane
            // at the vertical thickness on the horizontal axis: 30pt *wide*,
            // narrower than the title-bar controls that would restore it, and
            // AppKit reports nothing. So the edge is re-asked, never trusted.
            //
            // Re-asked whether or not there is an item to pin, because the
            // answer is a fact about the tree: a tab nobody has displayed can
            // still have been rearranged under a minimized pane, and leaving
            // the stale edge on it means its first display draws a rail on a
            // side the pane is no longer docked to.
            guard let resolved = PaneMinimizeGeometry.resolvedEdge(
                forNode: leaf.nodeID, in: tree, requested: edge) else {
                // Nowhere left to minimize toward. Giving the pane back is the
                // only outcome that leaves the user able to act on it.
                if let owner, let item { owner.restoreSizing(of: item) }
                leaf.setMinimized(to: nil)
                continue
            }
            if let owner, let item {
                owner.pin(item, to: leaf.minimizedThickness(for: resolved))
            }
            // A promotion can also keep the axis and change the side. Telling
            // the pane keeps its chrome on the edge it is actually docked to.
            if resolved != edge { leaf.setMinimized(to: resolved) }
        }
        // After the pinning, for the same reason `applyPersistedPaneState()`
        // orders them this way: pinning an item the zoom has collapsed reads as
        // a pane that never came back.
        if let zoomed = zoomedLeaf { applyZoom(target: zoomed.nodeID) }
    }

    /// Re-asks every pane which edges it may minimize toward. The answer is a
    /// fact about the tree, so it is re-asked whenever the tree changes.
    func refreshPaneControls() {
        for leaf in allLeaves() { leaf.refreshControlAvailability() }
    }
}
