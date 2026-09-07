import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

@MainActor
public final class ComposableTabsViewController: ThemedSplitViewController {

    public enum Direction: Hashable, CaseIterable {
        case left, right, above, below

        public var axis: ComposableTabsAxis {
            switch self {
            case .left, .right: return .horizontal
            case .above, .below: return .vertical
            }
        }

        /// How a *placement* reads: where the new pane goes relative to this one.
        public var placementName: String {
            switch self {
            case .left: return "Left"
            case .right: return "Right"
            case .above: return "Above"
            case .below: return "Below"
            }
        }

        /// How a *movement* reads. Same four directions, but "move this pane
        /// above" is the arrow key the user pressed, so it is called Up.
        public var movementName: String {
            switch self {
            case .left: return "Left"
            case .right: return "Right"
            case .above: return "Up"
            case .below: return "Down"
            }
        }

        /// The SF Symbol for the arrow that performs this move.
        public var arrowSymbolName: String {
            switch self {
            case .left: return "arrow.left"
            case .right: return "arrow.right"
            case .above: return "arrow.up"
            case .below: return "arrow.down"
            }
        }

        /// The arrow key that performs this move, as a `keyCode`.
        public var arrowKeyCode: UInt16 {
            switch self {
            case .left: return 123
            case .right: return 124
            case .below: return 125
            case .above: return 126
            }
        }

        /// Where the *new* pane goes relative to the one being split.
        public var placesNewPaneFirst: Bool {
            self == .left || self == .above
        }

        /// The two directions that offer `axis`, near side first.
        public static func directions(along axis: ComposableTabsAxis) -> [Direction] {
            axis == .horizontal ? [.right, .left] : [.below, .above]
        }
    }

    /// Posted after any change to a tab's tree, with the *root*
    /// `ComposableTabsViewController` as the object. Arrange mode's toolbars
    /// listen: one pane moving changes which moves every other pane has.
    public static let layoutDidChangeNotification =
        Notification.Name("AgenticToolkit.ComposableTabsViewController.layoutDidChange")

    public let nodeID: UUID
    /// Mutable because `rebuild(from:)` may re-lay the root along the other
    /// axis: moving the only pane in a row to the right of a column turns the
    /// row into a column, and the controller stays the same object.
    public private(set) var axis: ComposableTabsAxis
    /// The live child list, and the single source of truth for the tree —
    /// `splitViewItems` only exists once the view has loaded, and a restored
    /// but never-displayed tab never loads its view.
    private var layoutChildren: [any ComposableTabsChild]
    private weak var project: ProjectWorkspace?
    private let isRoot: Bool

    /// See `ComposableTabsChild.thicknessFraction`.
    public var thicknessFraction: CGFloat?

    /// One-shot: after the first real layout the user owns the dividers, and
    /// re-imposing a fraction on every layout pass would fight them. Reset
    /// whenever the children change, because the stored fractions then
    /// describe an arrangement that is no longer on screen.
    private var hasAppliedPreferredThicknesses = false

    /// Root only: the pending write for a divider the user is still dragging.
    private var pendingThicknessPersist: DispatchWorkItem?
    /// Root only: the sizes last written, so a window resize that ends where it
    /// began — or the layout passes AppKit runs while a tab is switched — do
    /// not each cost a transaction (`idempotency`).
    private var lastPersistedThicknesses = ""
    private static let thicknessPersistDelay: DispatchTimeInterval = .milliseconds(300)

    /// Keeps the gutters live: `dividerThickness` is computed from the setting,
    /// so something has to tell AppKit the answer moved.
    private var spacingObservers: [UserSettingObserver<Int>] = []

    /// Callback the host (e.g. window controller) installs on the *root*
    /// `ComposableTabsViewController` of each tab. Fires whenever a layout
    /// change happens that should be persisted, with a fresh snapshot of
    /// the tree. The host is responsible for routing this snapshot into
    /// the project's tab list.
    public var onLayoutDidChange: ((LayoutNode) -> Void)?

    public init(
        nodeID: UUID,
        axis: ComposableTabsAxis,
        children: [any ComposableTabsChild],
        project: ProjectWorkspace?,
        isRoot: Bool
    ) {
        self.nodeID = nodeID
        self.axis = axis
        self.layoutChildren = children
        self.project = project
        self.isRoot = isRoot
        super.init(nibName: nil, bundle: nil)
    }

    public convenience init(
        nodeID: UUID,
        axis: ComposableTabsAxis,
        first: any ComposableTabsChild,
        second: any ComposableTabsChild,
        project: ProjectWorkspace?,
        isRoot: Bool
    ) {
        self.init(
            nodeID: nodeID,
            axis: axis,
            children: [first, second],
            project: project,
            isRoot: isRoot
        )
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The layout governing this tree — the project's, or the placeholder-only
    /// fallback if the project has gone away.
    var layout: ComposableTabsLayout {
        project?.layout ?? ComposableTabsLayout.placeholderOnly()
    }

    /// Panes are separated by a gap the user sets, not by AppKit's seam — see
    /// `PaneSplitView`.
    public override func makeSplitView() -> ThemedSplitView { PaneSplitView() }

    public override func viewDidLoad() {
        super.viewDidLoad()

        splitView.isVertical = (axis == .horizontal)
        splitView.dividerStyle = .thin

        spacingObservers = PaneSpacing.gutterSettings.values.map { setting in
            UserSettingObserver(setting) { [weak self] _ in
                (self?.splitView as? PaneSplitView)?.spacingDidChange()
            }
        }

        for child in layoutChildren {
            addSplitViewItem(makeItem(for: child.viewController))
        }

        if isRoot { reassignPaneIdentifiers() }
    }

    /// Where a dragged divider becomes a saved layout. AppKit has no "the user
    /// let go" notification, so the write is debounced instead — see
    /// `scheduleThicknessPersist()`. Nothing is written before the preferred
    /// thicknesses have been applied: until then what is on screen is AppKit's
    /// placeholder geometry, not the user's layout.
    ///
    /// The delegate method AppKit already calls, rather than a block observer
    /// on the same notification: a block observer is `@Sendable`, and this
    /// controller is not `Sendable` — its superclass is `open` in another
    /// module, so no implicit conformance reaches it — which makes capturing
    /// `self` in one an error under complete concurrency checking.
    public override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard hasAppliedPreferredThicknesses else { return }
        rootSplit()?.scheduleThicknessPersist()
    }

    /// `preferredThicknessFraction` alone is not enough. AppKit resolves it
    /// against whatever thickness the split view has when the item is installed,
    /// and in `viewDidLoad` that is still the placeholder frame from `loadView`
    /// — where a 22% sidebar clamps to its minimum and then grows with the
    /// window, ending up at more than half of it. By the first real layout pass
    /// the thickness is the window's, so the fraction means what it says.
    public override func viewDidLayout() {
        super.viewDidLayout()
        applyPreferredThicknessesIfNeeded()
    }

    private func applyPreferredThicknessesIfNeeded() {
        guard !hasAppliedPreferredThicknesses else { return }
        let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        // A zero-thickness pass carries no information; wait for a real one.
        guard total > 1, splitViewItems.count == layoutChildren.count else { return }
        hasAppliedPreferredThicknesses = true

        var offset: CGFloat = 0
        for index in 0..<max(splitViewItems.count - 1, 0) {
            let item = splitViewItems[index]
            var thickness = self.thickness(of: item.viewController.view)
            // A size the user dragged to outranks the one the view registered:
            // the fraction in the descriptor is only ever a first guess, and
            // re-imposing it over a saved layout is exactly the bug where a
            // window "forgets" how it was arranged.
            let fraction = layoutChildren[index].thicknessFraction ?? item.preferredThicknessFraction
            if fraction > 0 {
                thickness = max(item.minimumThickness, total * fraction)
                splitView.setPosition(offset + thickness, ofDividerAt: index)
            }
            offset += thickness
        }
    }

    /// A gutter set to zero would otherwise be a divider with no grab area —
    /// an arrangement the mouse cannot undo. The drawn gap stays exactly what
    /// was asked for; only the region that responds to a drag is widened.
    public override func splitView(
        _ splitView: NSSplitView,
        effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        let base = super.splitView(
            splitView,
            effectiveRect: proposedEffectiveRect,
            forDrawnRect: drawnRect,
            ofDividerAt: dividerIndex
        )
        let grab = PaneSpacing.minimumDividerGrab
        if splitView.isVertical {
            guard base.width < grab else { return base }
            return base.insetBy(dx: -(grab - base.width) / 2, dy: 0)
        }
        guard base.height < grab else { return base }
        return base.insetBy(dx: 0, dy: -(grab - base.height) / 2)
    }

    private func thickness(of view: NSView) -> CGFloat {
        splitView.isVertical ? view.frame.width : view.frame.height
    }

    /// Reads the live divider positions into the tree, so the next snapshot
    /// describes what is on screen rather than what was last restored.
    ///
    /// Recursive, because one gesture — a window resize, a tab appearing — is
    /// felt by every split at once, and the root is the only one that saves.
    /// A split whose view has never loaded is left alone: it keeps the sizes it
    /// was restored with, which is the whole point of storing them on the child.
    func captureThicknessFractions() {
        if isViewLoaded, layoutChildren.count > 1, splitViewItems.count == layoutChildren.count {
            let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            if total > 1 {
                for (child, item) in zip(layoutChildren, splitViewItems) where !item.isCollapsed {
                    child.thicknessFraction = thickness(of: item.viewController.view) / total
                }
            }
        }
        for child in layoutChildren {
            (child as? ComposableTabsViewController)?.captureThicknessFractions()
        }
    }

    /// Saves the dividers once they have stopped moving.
    ///
    /// A drag posts a resize notification per mouse event and a window resize
    /// posts one per frame, so writing on each would put the database in the
    /// middle of a gesture. The delay collapses the gesture into one write, and
    /// the signature check drops the ones that changed nothing.
    private func scheduleThicknessPersist() {
        guard isRoot else { return }
        pendingThicknessPersist?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistThicknessesIfChanged()
        }
        pendingThicknessPersist = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.thicknessPersistDelay, execute: work)
    }

    private func persistThicknessesIfChanged() {
        captureThicknessFractions()
        let node = snapshotNode()
        let signature = Self.thicknessSignature(of: node)
        guard signature != lastPersistedThicknesses else { return }
        lastPersistedThicknesses = signature
        onLayoutDidChange?(node)
    }

    /// The sizes in a tree, rounded to where a pixel could tell them apart.
    private static func thicknessSignature(of node: LayoutNode) -> String {
        let own = "\(node.id.uuidString):\(((node.thicknessFraction ?? -1) * 1000).rounded())"
        switch node.kind {
        case .leaf:
            return own
        case .split(_, let first, let second):
            return "\(own)(\(thicknessSignature(of: first)),\(thicknessSignature(of: second)))"
        }
    }

    // MARK: - Mutation

    /// Splits `child`, putting a pane showing `viewID` beside it.
    ///
    /// The view to add is a parameter rather than a copy of what the pane
    /// already shows: which views may go here is the spec's answer, and a pane
    /// that duplicated its own content would walk straight through a `max: 1`.
    public func split(
        _ child: ComposableTabsPaneViewController,
        adding viewID: ComposableTabsViewID,
        direction: Direction
    ) {
        guard let index = layoutChildren.firstIndex(where: { $0.viewController === child }),
              let project = project else { return }

        // Before anything moves: what is on screen now is the last chance to
        // read the sizes the user set, and the arrangement is about to change
        // under them.
        rootSplit()?.captureThicknessFractions()

        let sibling = ComposableTabsPaneViewController(
            nodeID: UUID(),
            paneNumber: project.allocatePaneNumber(),
            viewID: viewID,
            project: project
        )

        let firstChildVC: ComposableTabsPaneViewController
        let secondChildVC: ComposableTabsPaneViewController
        if direction.placesNewPaneFirst {
            firstChildVC = sibling
            secondChildVC = child
        } else {
            firstChildVC = child
            secondChildVC = sibling
        }

        // The child moves *into* the new inner split, so detach it from this
        // one first — `removeSplitViewItem` is what un-parents the controller.
        if isViewLoaded, let item = splitViewItems.first(where: { $0.viewController === child }) {
            removeSplitViewItem(item)
        }

        let inner = ComposableTabsViewController(
            nodeID: UUID(),
            axis: direction.axis,
            first: firstChildVC,
            second: secondChildVC,
            project: project,
            isRoot: false
        )
        // The inner split takes over the slot the pane held, so it inherits its
        // size; the two panes inside it start out sharing that slot evenly.
        inner.thicknessFraction = child.thicknessFraction
        child.thicknessFraction = nil

        layoutChildren[index] = inner
        if isViewLoaded {
            insertSplitViewItem(makeItem(for: inner), at: index)
            hasAppliedPreferredThicknesses = false
        }

        // Propagate to root, which persists the full tree.
        rootSplit()?.persistTreeToDocument()
    }

    /// Removes a leaf pane. The surviving sibling expands into the vacated
    /// space; the enclosing tab is never resized. A non-root split left with
    /// one child is a degenerate split, so it collapses into its parent, which
    /// adopts the survivor at the same position. The *root* may legitimately
    /// hold a single child — that is a tab reduced to one full-size pane.
    public func remove(_ child: ComposableTabsPaneViewController) {
        guard let index = layoutChildren.firstIndex(where: { $0.viewController === child }) else { return }

        // `rootSplit()` walks up through `parent`, so it has to be resolved
        // before a collapse detaches this controller from the tree.
        let root = rootSplit()
        // Every removal rule — the tab's last pane, a fixed region, a view the
        // spec requires — lives in the spec, so the tree asks it rather than
        // trusting whichever UI happened to call in.
        guard (root ?? self).canRemoveLeaf(child) else { return }
        // Same reason as `split(_:adding:direction:)`: read the sizes off the
        // screen while the arrangement they describe is still on it.
        root?.captureThicknessFractions()
        let hadFocus = child.containsFirstResponder

        layoutChildren.remove(at: index)
        if isViewLoaded, let item = splitViewItems.first(where: { $0.viewController === child }) {
            removeSplitViewItem(item)
        }
        // The pane is gone from the tree for good, so its content releases what
        // it holds now — otherwise a closed pane's shells and file watchers run
        // on until the last reference happens to drop.
        child.paneWillBeRemoved()

        // The survivors divide up the space the pane was using; whatever
        // fractions they were carrying describe a split that no longer exists.
        for remaining in layoutChildren { remaining.thicknessFraction = nil }
        if isViewLoaded { hasAppliedPreferredThicknesses = false }

        if layoutChildren.count == 1, !isRoot, let parentSplit = parent as? ComposableTabsViewController {
            let survivor = layoutChildren[0]
            // The survivor is promoted into this split's slot, so it is that
            // slot's size it now has to fill.
            survivor.thicknessFraction = thicknessFraction
            if isViewLoaded,
               let item = splitViewItems.first(where: { $0.viewController === survivor.viewController }) {
                removeSplitViewItem(item)
            }
            layoutChildren.removeAll()
            parentSplit.replaceChild(self, with: survivor)
        }

        if hadFocus, let root, let leaf = root.firstLeaf() {
            root.view.window?.makeFirstResponder(leaf.view)
        }
        root?.persistTreeToDocument()
    }

    private func replaceChild(
        _ old: ComposableTabsViewController,
        with replacement: any ComposableTabsChild
    ) {
        guard let index = layoutChildren.firstIndex(where: { $0.viewController === old }) else { return }
        replacement.thicknessFraction = old.thicknessFraction
        layoutChildren[index] = replacement
        guard isViewLoaded,
              let item = splitViewItems.first(where: { $0.viewController === old }) else { return }
        removeSplitViewItem(item)
        insertSplitViewItem(makeItem(for: replacement.viewController), at: index)
        hasAppliedPreferredThicknesses = false
    }

    // MARK: - Moving a pane

    /// The directions `leaf` may travel. Asked of the root, since a move is a
    /// fact about the whole tab, not about one split.
    public func availableMoveDirections(
        for leaf: ComposableTabsPaneViewController
    ) -> Set<Direction> {
        guard let root = rootSplit() else { return [] }
        let tree = root.snapshotNode()
        return ComposableTabsMove.availableDirections(for: leaf.nodeID, in: tree)
            .filter { direction in
                guard let moved = ComposableTabsMove.moving(leaf.nodeID, direction, in: tree) else {
                    return false
                }
                return allowsBySpec(moved)
            }
    }

    /// Whether the layout would keep every pane it has if it were arranged like
    /// `tree`.
    ///
    /// A move is pure arithmetic on the tree and knows nothing about which
    /// views a region allows, so a pane can be walked into a subtree whose spec
    /// does not permit it — where the next load quietly replaces it with a
    /// placeholder. Asking the spec here is what keeps an offered arrow from
    /// being a way to lose a pane. No spec means no constraint.
    private func allowsBySpec(_ tree: LayoutNode) -> Bool {
        guard let spec = (rootSplit()?.project ?? project)?.layout.spec else { return true }
        return spec.allows(tree)
    }

    /// Moves `leaf` one step in `direction`, or reports that it could not.
    ///
    /// The move itself is arithmetic on the snapshot — see `ComposableTabsMove`
    /// — and the controller tree is then rebuilt to match. Doing it that way
    /// round means the enabled arrows and the move they perform are the same
    /// code, so a live arrow can never turn out to be a no-op.
    @discardableResult
    public func move(_ leaf: ComposableTabsPaneViewController, _ direction: Direction) -> Bool {
        guard let root = rootSplit(),
              let moved = ComposableTabsMove.moving(
                leaf.nodeID, direction, in: root.snapshotNode()),
              allowsBySpec(moved) else { return false }
        root.rebuild(from: moved)
        return true
    }

    /// Re-hosts this tree so it matches `node`, reusing the panes it already
    /// has: a moved terminal keeps its shell and a moved editor keeps its
    /// undo stack, because the pane controller is carried across rather than
    /// rebuilt from the persisted view ID.
    public func rebuild(from node: LayoutNode) {
        guard let project = project else { return }

        var reusable: [UUID: ComposableTabsPaneViewController] = [:]
        collectLeaves(into: &reusable)
        // Un-parent everything first: AppKit will not adopt a view controller
        // that still belongs to another parent, and the old inner splits are
        // about to be discarded anyway.
        detachSubtree()

        let newAxis: ComposableTabsAxis
        let children: [any ComposableTabsChild]
        switch node.kind {
        case .split(let axis, let first, let second):
            newAxis = axis
            children = [
                rebuildChild(first, reusing: reusable, project: project),
                rebuildChild(second, reusing: reusable, project: project)
            ]
        case .leaf:
            // A tab reduced to one pane; the root hosts it full-size, and the
            // axis of a single-child split is not observable.
            newAxis = axis
            children = [rebuildChild(node, reusing: reusable, project: project)]
        }

        axis = newAxis
        layoutChildren = children

        if isViewLoaded {
            splitView.isVertical = (newAxis == .horizontal)
            // The divider positions described the old arrangement; let the
            // preferred fractions speak once more for the new one.
            hasAppliedPreferredThicknesses = false
            for child in children {
                addSplitViewItem(makeItem(for: child.viewController))
            }
        }

        rootSplit()?.persistTreeToDocument()
    }

    private func collectLeaves(into leaves: inout [UUID: ComposableTabsPaneViewController]) {
        for child in layoutChildren {
            if let leaf = child as? ComposableTabsPaneViewController {
                leaves[leaf.nodeID] = leaf
            } else if let split = child as? ComposableTabsViewController {
                split.collectLeaves(into: &leaves)
            }
        }
    }

    /// Empties this subtree without telling any pane it is going away — every
    /// pane here is about to be re-hosted, not closed.
    private func detachSubtree() {
        for child in layoutChildren {
            (child as? ComposableTabsViewController)?.detachSubtree()
        }
        if isViewLoaded {
            for item in splitViewItems {
                removeSplitViewItem(item)
            }
        }
        layoutChildren = []
    }

    private func rebuildChild(
        _ node: LayoutNode,
        reusing leaves: [UUID: ComposableTabsPaneViewController],
        project: ProjectWorkspace
    ) -> any ComposableTabsChild {
        let child: any ComposableTabsChild
        switch node.kind {
        case .split(let axis, let first, let second):
            child = ComposableTabsViewController(
                nodeID: node.id,
                axis: axis,
                first: rebuildChild(first, reusing: leaves, project: project),
                second: rebuildChild(second, reusing: leaves, project: project),
                project: project,
                isRoot: false
            )
        case .leaf(let viewID, _):
            child = leaves[node.id] ?? ComposableTabsPaneViewController(
                nodeID: node.id,
                paneNumber: project.allocatePaneNumber(),
                viewID: viewID,
                project: project
            )
        }
        child.thicknessFraction = node.thicknessFraction.map { CGFloat($0) }
        return child
    }

    // MARK: - Spec-driven legal moves

    /// Views that may be added beside `leaf`, with the direction to offer each
    /// one first. Asked of the root, because a `max` declared at the top of the
    /// spec counts across the whole tab.
    public func allowedInsertions(
        beside leaf: ComposableTabsPaneViewController
    ) -> [ComposableTabLayoutSpec.Insertion] {
        guard let root = rootSplit() else { return [] }
        return layout.spec.allowedInsertions(
            at: leaf.nodeID,
            in: root.snapshotNode(),
            registry: layout.registry
        )
    }

    public func canRemoveLeaf(_ leaf: ComposableTabsPaneViewController) -> Bool {
        guard let root = rootSplit() else { return false }
        return layout.spec.canRemove(leaf.nodeID, from: root.snapshotNode())
    }

    // MARK: - Tree walking

    func rootSplit() -> ComposableTabsViewController? {
        var current: ComposableTabsViewController? = self
        while let parent = current?.parent as? ComposableTabsViewController {
            current = parent
        }
        return current
    }

    /// Number of leaf panes in this subtree.
    public func leafCount() -> Int {
        layoutChildren.reduce(0) { total, child in
            if let split = child as? ComposableTabsViewController {
                return total + split.leafCount()
            }
            return total + 1
        }
    }

    /// First leaf in depth-first order, used to re-home first responder after
    /// the focused pane is removed.
    public func firstLeaf() -> ComposableTabsPaneViewController? {
        for child in layoutChildren {
            if let leaf = child as? ComposableTabsPaneViewController { return leaf }
            if let split = child as? ComposableTabsViewController, let leaf = split.firstLeaf() {
                return leaf
            }
        }
        return nil
    }

    /// Every leaf in this subtree, depth first — the order the user reads the
    /// panes in, which is the order that has to number them.
    public func allLeaves() -> [ComposableTabsPaneViewController] {
        layoutChildren.flatMap { child -> [ComposableTabsPaneViewController] in
            if let leaf = child as? ComposableTabsPaneViewController { return [leaf] }
            if let split = child as? ComposableTabsViewController { return split.allLeaves() }
            return []
        }
    }

    /// Stamps `pane.<content-type>` on every leaf, numbering only the kinds
    /// that appear more than once.
    ///
    /// A number that appeared on every pane would make the common identifier
    /// — one terminal in the tab — depend on how many panes happen to be open,
    /// so a test addressing "the terminal" would break when a second one was
    /// added elsewhere. Numbering only the ambiguous kinds keeps the simple
    /// case simple and still leaves nothing unaddressable.
    public func reassignPaneIdentifiers() {
        let leaves = allLeaves()
        var counts: [String: Int] = [:]
        for leaf in leaves { counts[leaf.paneTypeIdentifier, default: 0] += 1 }

        var seen: [String: Int] = [:]
        for leaf in leaves {
            let type = leaf.paneTypeIdentifier
            guard counts[type, default: 0] > 1 else {
                leaf.assignPaneIndex(nil)
                continue
            }
            let index = seen[type, default: 0] + 1
            seen[type] = index
            leaf.assignPaneIndex(index)
        }
    }

    fileprivate func persistTreeToDocument() {
        guard isRoot else { return }
        reassignPaneIdentifiers()
        onLayoutDidChange?(snapshotNode())
        NotificationCenter.default.post(name: Self.layoutDidChangeNotification, object: self)
    }

    /// Value-type snapshot of the live controller tree.
    ///
    /// A root holding a single child snapshots *as* that child: the extra
    /// wrapper is a runtime detail of hosting a lone pane in a split view
    /// controller, not part of the persisted layout.
    public func snapshotNode() -> LayoutNode {
        let snapshots = layoutChildren.map { snapshotChild($0) }
        switch snapshots.count {
        case 0:
            return LayoutNode.leaf(contentType: .placeholder)
        case 1:
            return snapshots[0]
        default:
            return LayoutNode.split(
                id: nodeID,
                orientation: axis,
                first: snapshots[0],
                second: snapshots[1],
                thicknessFraction: thicknessFraction.map(Double.init)
            )
        }
    }

    private func snapshotChild(_ child: any ComposableTabsChild) -> LayoutNode {
        if let split = child as? ComposableTabsViewController {
            return split.snapshotNode()
        }
        if let leaf = child as? ComposableTabsPaneViewController {
            return LayoutNode.leaf(
                id: leaf.nodeID,
                contentType: leaf.viewID,
                thicknessFraction: leaf.thicknessFraction.map(Double.init)
            )
        }
        // Fallback — should not occur under the current class hierarchy.
        return LayoutNode.leaf(id: UUID(), contentType: .placeholder)
    }

    /// Sizing comes from whatever the leaf's view registered — or, for a
    /// nested split, from everything underneath it.
    private func makeItem(for viewController: NSViewController) -> NSSplitViewItem {
        let item = NSSplitViewItem(viewController: viewController)
        let registry = layout.registry
        let descriptor = (viewController as? ComposableTabsPaneViewController)
            .map { registry.descriptor(for: $0.viewID) }
        item.minimumThickness = Self.minimumThickness(
            of: viewController, along: axis, registry: registry)
        item.canCollapse = descriptor?.isCollapsible ?? false
        if let fraction = descriptor?.preferredThicknessFraction {
            item.preferredThicknessFraction = fraction
        }
        // A pane that asked for a share of the window keeps the width it gets;
        // a higher holding priority makes AppKit take a window resize out of
        // its neighbours instead of spreading it around. A sidebar that grew
        // with the window would be a third of a wide display.
        item.holdingPriority = descriptor?.resolvedHoldingPriority ?? .defaultLow
        return item
    }

    /// What a subtree needs along `axis`. A leaf answers from its registration;
    /// a nested split answers from its children — summed when they are arranged
    /// along that axis, maxed when they are stacked across it.
    ///
    /// Without this a split is just "some view controller" and takes the bare
    /// default, so an outer split believes a half holding a 320pt notes pane
    /// beside a 400pt terminal can be squeezed to 120.
    private static func minimumThickness(
        of viewController: NSViewController,
        along axis: ComposableTabsAxis,
        registry: ComposableTabsViewRegistry
    ) -> CGFloat {
        if let leaf = viewController as? ComposableTabsPaneViewController {
            return registry.descriptor(for: leaf.viewID).minimumThickness
        }
        guard let split = viewController as? ComposableTabsViewController,
              !split.layoutChildren.isEmpty else {
            return ComposableTabsViewDescriptor.placeholder.minimumThickness
        }
        let thicknesses = split.layoutChildren.map {
            minimumThickness(of: $0.viewController, along: axis, registry: registry)
        }
        return split.axis == axis
            ? thicknesses.reduce(0, +)
            : (thicknesses.max() ?? ComposableTabsViewDescriptor.placeholder.minimumThickness)
    }

    // MARK: - Construction from persisted layout

    /// Builds a root or nested `ComposableTabsViewController` +
    /// `ComposableTabsPaneViewController` tree from a value-type `LayoutNode`.
    /// A leaf at the top level is a tab that was reduced to a single pane; it is
    /// hosted in a root split holding that one child, which fills the tab.
    public static func make(
        from node: LayoutNode,
        project: ProjectWorkspace,
        isRoot: Bool
    ) -> ComposableTabsViewController {
        switch node.kind {
        case .split:
            return buildSplit(node, project: project, isRoot: isRoot)
        case .leaf:
            return ComposableTabsViewController(
                nodeID: UUID(),
                axis: .horizontal,
                children: [buildChild(node, project: project)],
                project: project,
                isRoot: isRoot
            )
        }
    }

    private static func buildSplit(
        _ node: LayoutNode,
        project: ProjectWorkspace,
        isRoot: Bool
    ) -> ComposableTabsViewController {
        guard case .split(let axis, let first, let second) = node.kind else {
            // Unreachable given `make(from:)` routes leaves elsewhere — fail loudly if violated.
            fatalError("buildSplit called with non-split node")
        }
        return ComposableTabsViewController(
            nodeID: node.id,
            axis: axis,
            first: buildChild(first, project: project),
            second: buildChild(second, project: project),
            project: project,
            isRoot: isRoot
        )
    }

    private static func buildChild(
        _ node: LayoutNode,
        project: ProjectWorkspace
    ) -> any ComposableTabsChild {
        let child: any ComposableTabsChild
        switch node.kind {
        case .split:
            child = buildSplit(node, project: project, isRoot: false)
        case .leaf(let viewID, _):
            child = ComposableTabsPaneViewController(
                nodeID: node.id,
                paneNumber: project.allocatePaneNumber(),
                viewID: viewID,
                project: project
            )
        }
        // The saved size travels with the child, so the first layout pass can
        // hand each pane the share it had when the window was last closed.
        child.thicknessFraction = node.thicknessFraction.map { CGFloat($0) }
        return child
    }
}

/// Type-erasing protocol so `ComposableTabsViewController` can hold either a
/// leaf or a nested split.
@MainActor
public protocol ComposableTabsChild: AnyObject {
    var viewController: NSViewController { get }
    var nodeID: UUID { get }

    /// This child's share of the split holding it, `0...1`, or `nil` for one
    /// nobody has sized yet.
    ///
    /// Kept on the child rather than in a map on the parent so it survives
    /// every rearrangement for free: a pane carried into a new inner split, or
    /// promoted when its sibling closes, arrives with the size it had.
    var thicknessFraction: CGFloat? { get set }
}

extension ComposableTabsPaneViewController: ComposableTabsChild {
    public var viewController: NSViewController { self }
}

extension ComposableTabsViewController: ComposableTabsChild {
    public var viewController: NSViewController { self }
}
