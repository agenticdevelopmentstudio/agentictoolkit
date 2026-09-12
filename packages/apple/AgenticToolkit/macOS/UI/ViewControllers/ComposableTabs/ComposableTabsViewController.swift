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
    ///
    /// Not `private`: the `PaneHost` conformance in `ComposableTabsPaneHost.swift`
    /// walks it to decide what a zoom collapses.
    ///
    /// The `didSet` is what makes `host` true of a tab nobody has looked at.
    /// Which split holds a pane is a fact about *this* list, not about whether
    /// a view happens to be on screen, so it is stamped here — where the list
    /// changes — rather than on the load path.
    var layoutChildren: [any ComposableTabsChild] {
        didSet { stampOwnershipOnChildren() }
    }

    /// The split holding this one, on screen or not.
    ///
    /// Deliberately not `parent`: AppKit sets that in `addSplitViewItem` and
    /// nowhere else, so it is nil at every level of a tab nobody has switched
    /// to. `host` already covers that case for a *pane*; this is the same fact
    /// for a *split*, and without it `rootSplit()` stops at whichever split it
    /// was asked and answers questions about a subtree as if they were about
    /// the tab. Persisting is the one that bites: `persistTreeToDocument()`
    /// opens with `guard isRoot`, so the write is not wrong — it simply never
    /// happens.
    ///
    /// Weak, and stamped from `layoutChildren` beside `host`: which split holds
    /// this one is a fact about that list, not about whether a view has loaded.
    private(set) weak var layoutParent: ComposableTabsViewController?
    private weak var project: ProjectWorkspace?
    let isRoot: Bool

    /// The directory every pane in this split — and every split nested inside
    /// it — works in. Set once, from the tab's own working directory: a split
    /// or a rebuild always passes its parent's value along rather than
    /// re-deriving one, so every pane in a tab agrees.
    public let workingDirectory: URL

    /// See `ComposableTabsChild.thicknessFraction`.
    public var thicknessFraction: CGFloat?

    /// Root only: the pane currently taking over the whole tab, or `nil`.
    /// Stored on the root because a zoom is a fact about the tab rather than
    /// about one split, and weak because the tree owns its panes.
    public weak var zoomedLeaf: ComposableTabsPaneViewController?

    /// One-shot: after the first real layout the user owns the dividers, and
    /// re-imposing a fraction on every layout pass would fight them. Reset
    /// whenever the children change, because the stored fractions then
    /// describe an arrangement that is no longer on screen.
    private var hasAppliedPreferredThicknesses = false

    /// Root only, once. See `viewDidAppear()`.
    private var hasAppliedPersistedPaneState = false

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

    /// How this tree divides its space when panes come and go. Defaults to
    /// today's behaviour, so no existing host's layout moves.
    public var arranger: PaneArranger = InheritedSlotArranger() {
        didSet { stampOwnershipOnChildren() }
    }

    /// The array is the general shape, but a split here is binary or solo and
    /// `captureThicknessFractions()` now depends on that: it skips a split whole
    /// when one of its items is a rail, which is only lossless because a binary
    /// split holding a rail has no draggable divider left. A third child would
    /// have one — and would silently stop being persisted, since `snapshotNode`
    /// serialises two. The invariant was true of every call site by
    /// construction; this makes it something a new one trips over rather than
    /// something a future reader has to rediscover.
    public init(
        nodeID: UUID,
        axis: ComposableTabsAxis,
        children: [any ComposableTabsChild],
        project: ProjectWorkspace?,
        workingDirectory: URL,
        isRoot: Bool
    ) {
        assert(children.count <= 2, "a split is binary or solo; nest instead of appending")
        self.nodeID = nodeID
        self.axis = axis
        self.layoutChildren = children
        self.project = project
        self.workingDirectory = workingDirectory
        self.isRoot = isRoot
        super.init(nibName: nil, bundle: nil)
        // Not redundant with `layoutChildren`'s `didSet`, and deleting it costs
        // every pane in a freshly built tree its host: Swift runs no property
        // observer during initialization, and the assignment above happens
        // before `super.init` because it has to. This is the same stamping,
        // done at the one moment the observer cannot fire.
        stampOwnershipOnChildren()
    }

    /// Tells every child this split holds directly that this is the split
    /// holding it — `host` for a pane, `layoutParent` for a nested split.
    /// Nested splits stamp their own children the same way, from their own
    /// `init` and their own `didSet`, so one pass per level covers the tree.
    ///
    /// A nested split also inherits `arranger` here: an arranger governs a
    /// whole tree, not one node, so a split that appeared after the root's was
    /// installed — or picked up a new one — has to pass it on the same way.
    private func stampOwnershipOnChildren() {
        for child in layoutChildren {
            if let pane = child as? ComposableTabsPaneViewController {
                pane.host = self
                pane.layoutOverride = layoutOverride
                pane.stateOwnerNodeID = stateOwnerNodeID
            }
            if let split = child as? ComposableTabsViewController {
                split.layoutParent = self
                split.arranger = arranger
                split.layoutOverride = layoutOverride
                split.stateOwnerNodeID = stateOwnerNodeID
                split.clampsToContainer = clampsToContainer
            }
        }
    }

    /// Reassigns thickness fractions from the installed arranger.
    ///
    /// Applied onto the live children rather than through `rebuild(from:)`:
    /// the tree shape is already correct by the time this runs, and rebuilding
    /// would tear down and re-adopt every pane to change two numbers.
    public func applyArrangement() {
        guard !(arranger is InheritedSlotArranger) else { return }
        let arranged = arranger.arrange(snapshotNode(), along: axis)
        applyFractions(from: arranged)
        if isViewLoaded {
            hasAppliedPreferredThicknesses = false
            view.needsLayout = true
        }
    }

    /// Matches the arranged tree back onto the live one by node id. A node the
    /// arranger did not describe keeps whatever fraction it had.
    ///
    /// A split holding exactly one child is arranged the same way it is
    /// snapshotted: `snapshotNode()` skips the wrapper and hands the arranger
    /// that child's own subtree directly, so `node` here describes the child,
    /// not this split. Matching that unwrap is what lets a tab's root — which
    /// always holds its whole tree under one wrapping split — apply an
    /// arrangement at all; without it every id compares a wrapper against the
    /// thing it wraps and nothing below the wrapper is ever reached.
    private func applyFractions(from node: LayoutNode) {
        if layoutChildren.count == 1, let onlyChild = layoutChildren.first {
            onlyChild.thicknessFraction = node.thicknessFraction.map { CGFloat($0) }
            (onlyChild as? ComposableTabsViewController)?.applyFractions(from: node)
            return
        }
        guard case .split(_, let first, let second) = node.kind else { return }
        for (child, arranged) in zip(layoutChildren, [first, second]) {
            guard child.nodeID == arranged.id else { continue }
            child.thicknessFraction = arranged.thicknessFraction.map { CGFloat($0) }
            (child as? ComposableTabsViewController)?.applyFractions(from: arranged)
        }
    }

    public convenience init(
        nodeID: UUID,
        axis: ComposableTabsAxis,
        first: any ComposableTabsChild,
        second: any ComposableTabsChild,
        project: ProjectWorkspace?,
        workingDirectory: URL,
        isRoot: Bool
    ) {
        self.init(
            nodeID: nodeID,
            axis: axis,
            children: [first, second],
            project: project,
            workingDirectory: workingDirectory,
            isRoot: isRoot
        )
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// A layout this subtree uses instead of the project's.
    ///
    /// The Document pane's tabs may hold editors and nothing else, and the
    /// File Browser beside it lives in the same project — so the restriction
    /// cannot be expressed at project level. Assigning here stamps the whole
    /// subtree, which is what makes the constraint hold on restore as well as
    /// on the menus.
    public var layoutOverride: ComposableTabsLayout? {
        didSet { stampOwnershipOnChildren() }
    }

    /// The layout node every pane in this subtree should remember its state
    /// against, when the panes here are not layout nodes themselves — the
    /// Document pane's tabs, whose editors live only inside its own stored
    /// layout. `nil` for a window's own tree, where each pane *is* a layout
    /// node. See `ProjectPaneStateStore.ownerNodeID`.
    ///
    /// Assigning stamps the whole subtree, the same way `layoutOverride` does
    /// and for the same reason: it is a fact about a tree, not about a node,
    /// and a split that appears later has to inherit it.
    public var stateOwnerNodeID: UUID? {
        didSet { stampOwnershipOnChildren() }
    }

    /// Whether this tree's width is the container's to decide rather than its
    /// own — true for a tree living inside one pane of a bigger tree.
    ///
    /// A split item's `minimumThickness` is a **required** constraint on the
    /// split view holding it, and constraints do not stop at a view controller
    /// boundary. A window's own tree wants exactly that: the window can grow, so
    /// a pane that needs 400pt gets them. A tree nested inside a single pane
    /// cannot — growing means taking width from the pane's neighbours — so the
    /// same constraint instead pushes the enclosing pane wider, and switching
    /// between two tabs with different pane counts resizes the pane holding
    /// them. Here the panes divide the width the container has, however little
    /// that is, which is what `ProportionalArranger` already assumes.
    ///
    /// Stamped down the subtree like the two above, and for the same reason.
    public var clampsToContainer: Bool = false {
        didSet { stampOwnershipOnChildren() }
    }

    /// The layout governing this tree — this subtree's own, the project's, or
    /// the placeholder-only fallback if the project has gone away.
    var layout: ComposableTabsLayout {
        layoutOverride ?? project?.layout ?? ComposableTabsLayout.placeholderOnly()
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

    /// A pane restores its own chrome in its `viewDidLoad`, off its own store.
    /// The other half — pinning a minimized pane's split item, collapsing the
    /// ancestors of a zoomed one — is the host's, and it waits for the first
    /// layout pass.
    ///
    /// Not because the tree is not built yet. `viewDidLoad` adds a split item
    /// for every child, and `NSSplitViewController` installs an item's view as
    /// it is added, so the whole controller tree loads recursively out of the
    /// root's `viewDidLoad` — `ComposableTabsPaneHostTests` demonstrates it on
    /// its nested trees, which vend split items for splits nothing ever loaded
    /// by hand. (Its fixture does call `loadViewIfNeeded()` on the root and on
    /// every leaf; the intermediate splits are the ones nobody loads, and they
    /// are the ones the claim is about.)
    ///
    /// It is the divider positions. `applyPersistedPaneState()` goes through
    /// `paneDidRequestMinimize`, which calls `captureThicknessFractions()` —
    /// and that *writes* each child's `thicknessFraction` from the geometry
    /// currently on screen. Before the first real layout that geometry is
    /// `loadView`'s placeholder, so running the restore any earlier would
    /// overwrite every persisted fraction with a placeholder, and
    /// `applyPreferredThicknessesIfNeeded()` would then hand back the clobbered
    /// values: relaunching with one minimized pane would forget every divider
    /// position in the tab. `viewDidLayout` runs before `viewDidAppear` on both
    /// mount paths — a root set as a window's `contentViewController`, and a
    /// root added by `MultiTabbedViewController.refreshCenterContent()` into a
    /// container already on screen — so by here the preferred thicknesses are
    /// applied and the capture reads the real arrangement. The tab path is
    /// measured rather than assumed, because it is the one where the ordering
    /// is not obvious: in `ProjectPaneStateStoreTests`,
    /// `testTheTabMountPathLaysOutBeforeItAppears` records the callback order
    /// a tab-mounted controller actually receives, and
    /// `testARootMountedAsATabRestoresOnlyOnceItIsLaidOut` pins the consequence
    /// for a real tree — the shares the capture writes tile the split, which
    /// they only do once layout has run. (AppKit delivers `viewDidAppear` on a
    /// later run-loop turn there than on the window path; the layout pass still
    /// comes first.)
    ///
    /// The latch is this restore's alone. `reapplyPaneState()` re-states what
    /// the *live* panes already say about themselves and deliberately holds no
    /// latch, because it has to run on every rebuild — see its own comment.
    public override func viewDidAppear() {
        super.viewDidAppear()
        guard isRoot, !hasAppliedPersistedPaneState else { return }
        hasAppliedPersistedPaneState = true
        applyPersistedPaneState()
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
    ///
    /// **A capture may only read geometry the user actually arranged** — never a
    /// rail, never a collapsed or just-uncollapsed frame. Everything below is
    /// that one rule, and so are the two call sites in `PaneHost` that decline
    /// to call this at all.
    ///
    /// A *zoomed* tree is left alone entirely. A zoom collapses every pane but
    /// one, which is an arrangement of the screen rather than a decision about
    /// sizes — and reading it back would record the one visible pane at the full
    /// thickness and its siblings at nothing, so a layout saved while zoomed
    /// would restore unzoomed and wrong. Skipping leaves the pre-zoom fractions
    /// exactly where they were, which is what unzooming has to give back.
    ///
    /// A split holding a *rail* is skipped whole — every item in it, not just
    /// the pinned one. Minimizing takes the pane down to 32pt and hands the
    /// space it gave up to its sibling, so neither number describes anything the
    /// user chose. Skipping only the pinned item protects its own fraction and
    /// still loses the layout, because `applyPreferredThicknessesIfNeeded`
    /// places the dividers from the *non-last* children and gives the last one
    /// whatever is left: minimize the second slot and it is the sibling's
    /// inflated fraction that decides where the rail comes back to. Recording
    /// either is invisible while the session lasts, because AppKit's untouched
    /// `preferredThicknessFraction` still remembers — but after a rebuild the
    /// stored fraction wins and is clamped up to the minimum, so a pane the user
    /// dragged to 200 reopens at its floor. The debounce fires on any window
    /// resize while a pane is minimized, so this needs no unusual gesture.
    ///
    /// Nothing capturable is given up by widening the skip from the item to the
    /// split, and what carries that is the *runtime* shape of a split rather
    /// than the persisted one. Every split here is binary or solo: the
    /// array-taking init asserts it, `first:`/`second:` is the only way one is
    /// built with siblings, `split(_:adding:)` nests rather than appends, and
    /// `rebuild(from:)` assigns two children or one. A binary split holding a
    /// rail has no divider left to drag, so there is nothing here to read.
    /// (`snapshotNode()` serialises exactly two children as well, but that leg
    /// proves nothing on its own — a live split with three would persist its
    /// first two and a real divider between them would be lost. The invariant
    /// above is the one this gate stands on.) The recursion into child splits
    /// stays: a nested split's fractions are relative to its own bounds, so a
    /// rail in the parent does not distort them.
    ///
    /// `maximumThickness != unspecifiedDimension` is an exact test rather than a
    /// heuristic: `pin(_:to:)` is the only thing that sets it and
    /// `restoreSizing(of:)` the only thing that puts it back.
    func captureThicknessFractions() {
        guard rootSplit()?.zoomedLeaf == nil else { return }
        let showsRail = isViewLoaded && splitViewItems.contains {
            $0.maximumThickness != NSSplitViewItem.unspecifiedDimension
        }
        if !showsRail, isViewLoaded, layoutChildren.count > 1,
           splitViewItems.count == layoutChildren.count {
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

    // MARK: - Wearing another tab's sizes

    /// Takes `template`'s divider positions without rebuilding anything.
    ///
    /// One arrangement per project means a divider dragged in one tab is that
    /// divider dragged in all of them, and a drag posts a change per mouse
    /// event — so the tabs that merely *follow* must not pay a `rebuild(from:)`
    /// per frame, which would discard and re-host every pane in them. Sizes
    /// are all that differ here, and a size is a number on a child plus a
    /// divider to put back.
    ///
    /// `template` is a snapshot, so a root holding one child is that child
    /// (see `snapshotNode()`), and any split with siblings has exactly two.
    /// A tree that does not line up is left alone rather than half-applied:
    /// the caller reaches for `rebuild(from:)` when the structures differ, and
    /// this is only ever asked of a tab that already matches.
    public func applySizes(from template: LayoutNode) {
        adoptSizes(from: template)
        replaceDividers()
    }

    private func adoptSizes(from template: LayoutNode) {
        switch layoutChildren.count {
        case 1:
            adopt(template, into: layoutChildren[0])
        case 2:
            guard case .split(_, let first, let second) = template.kind else { return }
            adopt(first, into: layoutChildren[0])
            adopt(second, into: layoutChildren[1])
        default:
            return
        }
    }

    private func adopt(_ node: LayoutNode, into child: any ComposableTabsChild) {
        child.thicknessFraction = node.thicknessFraction.map { CGFloat($0) }
        (child as? ComposableTabsViewController)?.adoptSizes(from: node)
    }

    /// Puts the dividers back where the newly adopted fractions say.
    ///
    /// Unlatching alone would do it eventually — `viewDidLayout` applies the
    /// fractions on the next pass — and for a tab that is off screen (another
    /// edge's bar, or a tab nobody has selected) that is exactly right: its
    /// bounds are stale, `applyPreferredThicknessesIfNeeded` declines a
    /// zero-thickness pass, and the latch stays down until the tab is really
    /// laid out. A tab that *is* on screen has its bounds now, so it moves now.
    private func replaceDividers() {
        guard isViewLoaded else { return }
        hasAppliedPreferredThicknesses = false
        applyPreferredThicknessesIfNeeded()
        for child in layoutChildren {
            (child as? ComposableTabsViewController)?.replaceDividers()
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

    /// Writes a divider the user has already let go of, instead of waiting out
    /// the rest of the debounce.
    ///
    /// The 300 ms delay is there to collapse a gesture into one write, and the
    /// gesture is over the moment the host says so. A closing window is the
    /// case that matters: the pending item is about to be cancelled outright —
    /// or to run against a controller nothing holds any more — so the divider
    /// the user just dragged is lost for having been dragged too close to the
    /// close. Nothing is written unless a persist was actually pending, and
    /// `persistThicknessesIfChanged()` still drops a write that changes
    /// nothing, so a caller can flush unconditionally (`idempotency`).
    ///
    /// It cannot tell *whose* resize armed the pending item, though — the
    /// first layout pass arms one too — so the caller owes it the judgement
    /// that there is a saved arrangement here to refine. See
    /// `ComposableTabsWindowController.windowWillClose(_:)`.
    public func flushPendingThicknessPersist() {
        guard let pending = pendingThicknessPersist else { return }
        pending.cancel()
        pendingThicknessPersist = nil
        persistThicknessesIfChanged()
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
            project: project,
            workingDirectory: workingDirectory
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
            workingDirectory: workingDirectory,
            isRoot: false
        )
        // The inner split takes over the slot the pane held, so it inherits its
        // size; the two panes inside it start out sharing that slot evenly.
        inner.thicknessFraction = child.thicknessFraction
        child.thicknessFraction = nil
        inner.arranger = arranger
        inner.layoutOverride = layoutOverride
        inner.stateOwnerNodeID = stateOwnerNodeID
        inner.clampsToContainer = clampsToContainer

        layoutChildren[index] = inner
        if isViewLoaded {
            insertSplitViewItem(makeItem(for: inner), at: index)
            hasAppliedPreferredThicknesses = false
        }

        // Propagate to root, which persists the full tree.
        rootSplit()?.applyArrangement()
        rootSplit()?.persistTreeToDocument()
    }

    /// Removes a leaf pane. The surviving sibling expands into the vacated
    /// space; the enclosing tab is never resized. A non-root split left with
    /// one child is a degenerate split, so it collapses into its parent, which
    /// adopts the survivor at the same position. The *root* may legitimately
    /// hold a single child — that is a tab reduced to one full-size pane.
    ///
    /// `child` must be a **direct** child of this split. Every caller reaches
    /// this as `enclosingSplitOnScreen.remove(self)`, so any other pane — a descendant
    /// of this split included — is ignored rather than searched for, and
    /// `testRemovingAPaneNotInThisSplitIsANoOp` pins that. To close a pane you
    /// do not already own, go through its host's `paneDidRequestClose(_:)`,
    /// which asks the split that actually holds it — that routing is safe
    /// because `host` tracks `layoutChildren`, the same list this method
    /// searches. It is stamped where that list changes rather than where its
    /// split items are built, so a pane's host is the split that can actually
    /// remove it whether or not the tab has ever loaded a view.
    public func remove(_ child: ComposableTabsPaneViewController) {
        guard let index = layoutChildren.firstIndex(where: { $0.viewController === child }) else { return }

        // `rootSplit()` walks up the tree, so it has to be resolved before a
        // collapse detaches this controller from it — `layoutParent` is cleared
        // on the way out (see `replaceChild`), exactly so a detached split
        // stops answering for a tab it has left.
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
        // Nothing holds it now, and `host` is how everything else asks. Cleared
        // before the content is released, so the control refresh the setter
        // triggers still runs against a live pane.
        child.host = nil
        // The pane is gone from the tree for good, so its content releases what
        // it holds now — otherwise a closed pane's shells and file watchers run
        // on until the last reference happens to drop.
        child.paneWillBeRemoved()

        // The survivors divide up the space the pane was using; whatever
        // fractions they were carrying describe a split that no longer exists.
        for remaining in layoutChildren { remaining.thicknessFraction = nil }
        if isViewLoaded { hasAppliedPreferredThicknesses = false }

        if layoutChildren.count == 1, !isRoot, let parentSplit = enclosingSplit {
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
        root?.applyArrangement()
        root?.persistTreeToDocument()
    }

    private func replaceChild(
        _ old: ComposableTabsViewController,
        with replacement: any ComposableTabsChild
    ) {
        guard let index = layoutChildren.firstIndex(where: { $0.viewController === old }) else { return }
        replacement.thicknessFraction = old.thicknessFraction
        layoutChildren[index] = replacement
        // `old` is out of the tree now. `layoutChildren`'s `didSet` stamps what
        // is in the list and says nothing about what left, so the back-pointer
        // is cleared here — the same honesty `remove(_:)` gives a closed pane's
        // `host`, and it matters more, because `rootSplit()` trusts it.
        old.layoutParent = nil
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

        // Most of what was just un-parented is re-hosted a few lines below, but
        // a shape with fewer leaves than this tree has leaves some of them out,
        // and `detachSubtree()` deliberately says nothing to any of them. A pane
        // the new shape has no slot for was therefore dropped without ever being
        // told it was gone — and the mirror takes this branch on a real user
        // gesture (closing a pane in the front tab reshapes every other tab
        // down), so each of those tabs quietly leaked a live `/bin/zsh` and a
        // file-system watcher for the life of the window. `host` is already
        // `nil` by now, matching the order `remove(_:)` tears down in.
        let surviving = node.leafIDs
        for (nodeID, leaf) in reusable where !surviving.contains(nodeID) {
            leaf.paneWillBeRemoved()
        }

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
    ///
    /// "Not closed" is not "still held". `rebuild(from:)` re-stamps whatever
    /// lands in the new tree, and only that; a child the new shape leaves out is
    /// held by nothing, so its back-pointer goes out with it. Same rule as
    /// `remove(_:)` and `replaceChild(_:with:)` — `layoutChildren`'s `didSet`
    /// speaks for what is in the list and never for what left.
    private func detachSubtree() {
        for child in layoutChildren {
            if let split = child as? ComposableTabsViewController {
                split.detachSubtree()
                split.layoutParent = nil
            } else if let leaf = child as? ComposableTabsPaneViewController {
                leaf.host = nil
            }
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
                workingDirectory: workingDirectory,
                isRoot: false
            )
        case .leaf(let viewID, _):
            child = leaves[node.id] ?? ComposableTabsPaneViewController(
                nodeID: node.id,
                paneNumber: project.allocatePaneNumber(),
                viewID: viewID,
                project: project,
                workingDirectory: workingDirectory
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

    /// The split holding this one: AppKit's answer when there is one, ours
    /// otherwise. See `layoutParent` for why there are two.
    var enclosingSplit: ComposableTabsViewController? {
        (parent as? ComposableTabsViewController) ?? layoutParent
    }

    func rootSplit() -> ComposableTabsViewController? {
        var current: ComposableTabsViewController? = self
        // `isRoot` is set at construction and never changes, so the walk stops
        // at the node that actually is the tab's root rather than at the first
        // node with no visible parent — which on an unloaded tab is every node.
        while let node = current, !node.isRoot, let parent = node.enclosingSplit {
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
        reapplyPaneState()
        refreshPaneControls()
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
        // Sizing only. This used to be where a pane was told which split holds
        // it, and that was the bug: every call here is on the load path, so a
        // restored tab nobody switched to left its panes hostless and every
        // scripted action on them did nothing. `layoutChildren` owns that now.
        let item = NSSplitViewItem(viewController: viewController)
        let registry = layout.registry
        let descriptor = (viewController as? ComposableTabsPaneViewController)
            .map { registry.descriptor(for: $0.viewID) }
        item.minimumThickness = minimumThickness(of: viewController, registry: registry)
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

    /// Undoes a minimize's pinning, putting the item back on the sizing
    /// `makeItem(for:)` gave it. It lives here rather than with the `PaneHost`
    /// conformance because it is that method's knowledge read backwards, and
    /// two copies of it would drift.
    ///
    /// The ceiling comes off *before* the floor goes up. Each assignment is a
    /// separate constraint update, so raising the minimum first would leave the
    /// item, for that instant, asking AppKit for a width at least its
    /// registered minimum and at most the rail it is still pinned to — a pair
    /// AppKit cannot satisfy, logs, and recovers from by breaking one of them.
    /// Lifting the ceiling first makes the intermediate state merely wide,
    /// which is always satisfiable. (`pin` is this read backwards and is
    /// already safe: it lowers the floor before it lowers the ceiling.)
    func restoreSizing(of item: NSSplitViewItem) {
        let registry = layout.registry
        item.maximumThickness = NSSplitViewItem.unspecifiedDimension
        item.minimumThickness = minimumThickness(
            of: item.viewController, registry: registry)
        let descriptor = (item.viewController as? ComposableTabsPaneViewController)
            .map { registry.descriptor(for: $0.viewID) }
        item.holdingPriority = descriptor?.resolvedHoldingPriority ?? .defaultLow
    }

    /// What an item in *this* split may be shrunk to.
    ///
    /// One wrapper over the recursive answer, so the two call sites that set
    /// `minimumThickness` cannot disagree about whether this tree imposes one
    /// (`dry`). `unspecifiedDimension` rather than zero: it is AppKit's own word
    /// for "no constraint", the same one `restoreSizing(of:)` uses to lift a
    /// ceiling, and it keeps `applyPreferredThicknessesIfNeeded`'s
    /// `max(item.minimumThickness, …)` picking the fraction.
    private func minimumThickness(
        of viewController: NSViewController,
        registry: ComposableTabsViewRegistry
    ) -> CGFloat {
        guard !clampsToContainer else { return NSSplitViewItem.unspecifiedDimension }
        return Self.minimumThickness(of: viewController, along: axis, registry: registry)
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
        workingDirectory: URL,
        isRoot: Bool
    ) -> ComposableTabsViewController {
        switch node.kind {
        case .split:
            return buildSplit(node, project: project, workingDirectory: workingDirectory, isRoot: isRoot)
        case .leaf:
            return ComposableTabsViewController(
                nodeID: UUID(),
                axis: .horizontal,
                children: [buildChild(node, project: project, workingDirectory: workingDirectory)],
                project: project,
                workingDirectory: workingDirectory,
                isRoot: isRoot
            )
        }
    }

    private static func buildSplit(
        _ node: LayoutNode,
        project: ProjectWorkspace,
        workingDirectory: URL,
        isRoot: Bool
    ) -> ComposableTabsViewController {
        guard case .split(let axis, let first, let second) = node.kind else {
            // Unreachable given `make(from:)` routes leaves elsewhere — fail loudly if violated.
            fatalError("buildSplit called with non-split node")
        }
        return ComposableTabsViewController(
            nodeID: node.id,
            axis: axis,
            first: buildChild(first, project: project, workingDirectory: workingDirectory),
            second: buildChild(second, project: project, workingDirectory: workingDirectory),
            project: project,
            workingDirectory: workingDirectory,
            isRoot: isRoot
        )
    }

    private static func buildChild(
        _ node: LayoutNode,
        project: ProjectWorkspace,
        workingDirectory: URL
    ) -> any ComposableTabsChild {
        let child: any ComposableTabsChild
        switch node.kind {
        case .split:
            child = buildSplit(node, project: project, workingDirectory: workingDirectory, isRoot: false)
        case .leaf(let viewID, _):
            child = ComposableTabsPaneViewController(
                nodeID: node.id,
                paneNumber: project.allocatePaneNumber(),
                viewID: viewID,
                project: project,
                workingDirectory: workingDirectory
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
