#if canImport(UIKit)
import UIKit

/// Regular width: rails side by side in a horizontal scroll view with the detail pane on the right.
/// Compact width: expects to live inside a `UINavigationController`; pushes one rail per level and the
/// detail on top, popping when the controller truncates.
public final class HTDVViewController: UIViewController, UINavigationControllerDelegate {
    public let controller: HTDVController
    public let layoutEngine: HTDVLayoutEngine
    public private(set) var detailViewController: UIViewController?

    private var rails: [HTDVRailViewController] = []
    private let railScrollView = UIScrollView()
    private let railStack = UIStackView()
    private let detailContainer = UIView()
    private let splitStack = UIStackView()
    private var renderedDetailID: String?
    private var isCompact: Bool { traitCollection.horizontalSizeClass == .compact }
    /// Identity snapshot of the last `navigationController.viewControllers` this instance itself
    /// produced (via `setViewControllers` or `popToViewController`). Compared against the stack a
    /// `didShow` delegate callback observes so a transition this instance caused is never mistaken
    /// for a user-driven pop and fed back through the reconciliation path a second time.
    private var lastAppliedCompactStack: [ObjectIdentifier] = []
    /// Guards against a second selection opening a second discard prompt while the first
    /// `confirmDiscard()` is still awaiting the user.
    @MainActor private var isConfirmingDiscard = false
    /// Whether this host has ever rendered a non-empty model. Separates "emptied by a pop" — which
    /// the recovery net below exists for — from "never loaded", which is by value identical and must
    /// NOT trigger a fetch the app never asked for. See `isEmptyDeadEnd`.
    private var hasEverHadLevels = false
    /// The delegate that was on the navigation controller before this instance took the slot over,
    /// and the navigation controller it was taken from. `UINavigationController.delegate` is a
    /// single slot: taking it silently disables whatever the host app had installed (interactive
    /// transitions, analytics, a coordinator's own pop handling), so it is handed back when this
    /// HTDV leaves the stack. The navigation controller is remembered separately because by the
    /// time the restore runs, `self.navigationController` is already nil.
    private weak var previousNavigationDelegate: (any UINavigationControllerDelegate)?
    private weak var navigationControllerWeTookOver: UINavigationController?

    public init(controller: HTDVController, layoutEngine: HTDVLayoutEngine = HTDVLayoutEngine()) {
        self.controller = controller
        self.layoutEngine = layoutEngine
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        railStack.axis = .horizontal
        railStack.spacing = 0
        railStack.translatesAutoresizingMaskIntoConstraints = false
        railScrollView.addSubview(railStack)
        railScrollView.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        splitStack.axis = .horizontal
        splitStack.spacing = 0
        splitStack.translatesAutoresizingMaskIntoConstraints = false
        splitStack.addArrangedSubview(railScrollView)
        splitStack.addArrangedSubview(detailContainer)
        view.addSubview(splitStack)
        NSLayoutConstraint.activate([
            splitStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            splitStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            splitStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            splitStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            railStack.leadingAnchor.constraint(equalTo: railScrollView.contentLayoutGuide.leadingAnchor),
            railStack.trailingAnchor.constraint(equalTo: railScrollView.contentLayoutGuide.trailingAnchor),
            railStack.topAnchor.constraint(equalTo: railScrollView.contentLayoutGuide.topAnchor),
            railStack.bottomAnchor.constraint(equalTo: railScrollView.contentLayoutGuide.bottomAnchor),
            railStack.heightAnchor.constraint(equalTo: railScrollView.frameLayoutGuide.heightAnchor),
            detailContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: layoutEngine.minDetailWidth)
        ])
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (self: Self, _) in self.render() }
        controller.onChange = { [weak self] _ in self?.render() }
        render()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyColumnsLayout()
    }

    // MARK: HTDVDetailHosting passthrough

    public var hasUnsavedChanges: Bool {
        (detailViewController as? HTDVDetailHosting)?.hasUnsavedChanges ?? false
    }

    public func confirmDiscard() async -> Bool {
        guard let hosting = detailViewController as? HTDVDetailHosting, hosting.hasUnsavedChanges else { return true }
        return await hosting.confirmDiscard()
    }

    // MARK: Rendering

    private func render() {
        if !controller.levels.isEmpty { hasEverHadLevels = true }
        syncRailCount()
        for (index, rail) in rails.enumerated() {
            let selectedID = index < controller.selection.count ? controller.selection[index] : nil
            if index < controller.levels.count {
                rail.apply(level: controller.levels[index], selectedID: selectedID)
            }
            if controller.loadingLevelIndex == index { rail.showLoading() }
            if let error = controller.error, error.levelIndex == index {
                rail.showError(error.message) { [weak self] in
                    guard let self else { return }
                    Task { await self.controller.retry() }
                }
            }
        }
        renderDetail()
        if isCompact { renderCompactStack() } else { renderColumns() }
        recoverFromEmptyModelIfNeeded()
    }

    /// An emptied model (`popToLevel(-1)`, or an interactive pop that reconciles to it) left the host
    /// rendering one blank placeholder rail with no spinner, no error, no retry and no reload — a dead
    /// end the user could not leave. Re-issue the root load instead, so the next render shows a
    /// spinner, then either content or an error with a retry. Mirrors the AppKit host.
    ///
    /// Recursion is broken twice over, by state rather than by a re-entrancy flag. `load()` publishes
    /// `loadingLevelIndex` (and fires `onChange`) inside `beginRequest`, BEFORE its first `await`, so
    /// the `render()` it re-enters already fails the guard below; and the post-hop re-check inside the
    /// `Task` catches the same thing again from the other side, so this holds even if that ordering
    /// ever changes.
    private func recoverFromEmptyModelIfNeeded() {
        guard isEmptyDeadEnd else { return }
        Task { [weak self] in
            guard let self else { return }
            // Re-checked after the hop: an app-driven `load()` may have started in the meantime, and
            // re-issuing would bump the generation and throw that fetch away.
            guard self.isEmptyDeadEnd else { return }
            await self.controller.load()
        }
    }

    /// `hasEverHadLevels` is what distinguishes the dead end from a pristine host. `render()` runs
    /// from `viewDidLoad()`, when `levels` is empty, `error` is nil and nothing is loading — by value
    /// identical to the emptied-by-pop state — so without it merely BUILDING the view issued a root
    /// fetch, and a host that loads from `viewDidAppear` (or defers until the user picks a
    /// workspace) got that fetch unasked, plus a second one when it did load. Not
    /// `controller.generation > 0`: that is an internal request counter, and reading it from a host
    /// would make a private sequencing detail a load-bearing contract.
    private var isEmptyDeadEnd: Bool {
        hasEverHadLevels && controller.levels.isEmpty && controller.error == nil
            && controller.loadingLevelIndex == nil
    }

    private func syncRailCount() {
        var wanted = controller.levels.count
        if let loading = controller.loadingLevelIndex, loading >= wanted { wanted = loading + 1 }
        if let error = controller.error, error.levelIndex >= wanted { wanted = error.levelIndex + 1 }
        wanted = max(wanted, 1)
        while rails.count > wanted {
            let rail = rails.removeLast()
            // In compact width the rail may currently be owned by the navigation controller
            // (pushed, not a child of `self`). Only tear down containment we set up ourselves;
            // `renderCompactStack()`'s subsequent `setViewControllers` handles the other case
            // through the navigation controller's own containment API.
            detachIfChild(rail)
        }
        while rails.count < wanted {
            let rail = HTDVRailViewController(levelIndex: rails.count)
            let index = rail.levelIndex
            rail.onSelect = { [weak self] itemID in self?.railSelected(itemID: itemID, level: index) }
            rail.onCreate = { [weak self] in self?.createTapped(level: index) }
            rails.append(rail)
        }
    }

    private func renderDetail() {
        guard controller.detail?.id != renderedDetailID else { return }
        // Same caveat as `syncRailCount`: the outgoing detail may be owned by the navigation
        // controller rather than `self` if we are (or just were) in compact width.
        if let outgoing = detailViewController { detachIfChild(outgoing) }
        detailViewController = nil
        renderedDetailID = controller.detail?.id
        guard let detail = controller.detail else { return }
        let child = detail.make()
        attachFormCallbacks(to: child)
        child.title = detail.title
        detailViewController = child
    }

    /// A saved or deleted form changes the row that owns it, so the last level is re-fetched: labels
    /// follow the edit, and `reload(level:)` drops the selection when the row is gone. Chains onto
    /// whatever the detail factory already installed rather than replacing it, so a module that does
    /// its own bookkeeping on save still gets called.
    private func attachFormCallbacks(to child: UIViewController) {
        guard let form = child as? FormViewController else { return }
        let existingSaved = form.onSaved
        form.onSaved = { [weak self] in
            existingSaved()
            self?.reloadOwningLevel()
        }
        let existingDeleted = form.onDeleted
        form.onDeleted = { [weak self] in
            existingDeleted()
            self?.reloadOwningLevel()
        }
    }

    /// Reads the depth at call time, not at attach time: the rail may have grown or shrunk while the
    /// detail was open.
    private func reloadOwningLevel() {
        let index = max(controller.levels.count - 1, 0)
        Task { [weak self] in await self?.controller.reload(level: index) }
    }

    /// Removes `child` from `self`'s containment, but only if `self` actually owns it. A view
    /// controller currently pushed on a `UINavigationController` has that navigation controller as
    /// its parent, not `self`; forcing containment off outside the navigation controller's own API
    /// would desync its internal state, so such cases are left for `setViewControllers`/
    /// `popToViewController` to resolve properly.
    private func detachIfChild(_ child: UIViewController) {
        guard child.parent === self else { return }
        // A rail leaving `self`'s containment is also leaving columns layout (it is either being
        // discarded entirely by `syncRailCount`, or about to be pushed by `renderCompactStack`,
        // which detaches before pushing). Either way its fixed column width must not survive.
        (child as? HTDVRailViewController)?.deactivateColumnWidth()
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
    }

    /// Regular width: every rail is a child in the horizontal stack; the detail is a child in `detailContainer`.
    private func renderColumns() {
        splitStack.isHidden = false
        detachFromNavigationStackIfNeeded()
        for rail in rails where rail.parent !== self {
            rail.willMove(toParent: nil)
            rail.removeFromParent()
            addChild(rail)
            rail.view.translatesAutoresizingMaskIntoConstraints = false
            rail.activateColumnWidth(layoutEngine.railWidth)
            railStack.addArrangedSubview(rail.view)
            rail.didMove(toParent: self)
        }
        if let child = detailViewController, child.parent !== self {
            addChild(child)
            child.view.translatesAutoresizingMaskIntoConstraints = false
            detailContainer.addSubview(child.view)
            NSLayoutConstraint.activate([
                child.view.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
                child.view.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
                child.view.topAnchor.constraint(equalTo: detailContainer.topAnchor),
                child.view.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor)
            ])
            child.didMove(toParent: self)
        }
        applyColumnsLayout()
    }

    /// When switching from compact to regular width mid-navigation, any pushed rails/detail are
    /// still owned by the navigation controller, not `self`. Popping back to `self` through its own
    /// API (rather than manually reparenting pushed view controllers) keeps the navigation
    /// controller's containment state consistent before `renderColumns()` re-parents them as columns.
    private func detachFromNavigationStackIfNeeded() {
        guard let nav = navigationController, nav.viewControllers.contains(where: { $0 === self }) else { return }
        guard nav.topViewController !== self else { return }
        nav.popToViewController(self, animated: false)
        // Self-caused: record the resulting stack so the `didShow` callback this triggers is
        // recognized as our own change, not a user-driven pop.
        lastAppliedCompactStack = nav.viewControllers.map(ObjectIdentifier.init)
    }

    private func applyColumnsLayout() {
        guard !isCompact else { return }
        let mode = layoutEngine.layout(
            availableWidth: view.bounds.width, levelCount: rails.count,
            hasDetail: controller.detail != nil, isCompact: false
        )
        guard case .columns(let visible, let showsDetail) = mode else { return }
        detailContainer.isHidden = !showsDetail
        if let first = visible.first {
            railScrollView.setContentOffset(CGPoint(x: CGFloat(first) * layoutEngine.railWidth, y: 0), animated: false)
        }
    }

    /// Compact width: the navigation stack is [self, rail0, rail1, …, detail?]. Rails are detached from
    /// the column stack first so each has a single parent.
    private func renderCompactStack() {
        // `self` must actually BE on the stack before any of this rebuilds it. `navigationController`
        // is non-nil for a child view controller of a host that is itself pushed — UIKit walks the
        // parent chain and does not require membership in `viewControllers` — and it is also non-nil
        // transiently during a `setViewControllers` animation and on the render after a
        // `popToViewController` that removed `self`. In every one of those cases the prefix below
        // comes back empty and `setViewControllers` would wipe the host's own screens. Same shape as
        // `detachFromNavigationStackIfNeeded()`.
        guard let nav = navigationController,
              nav.viewControllers.contains(where: { $0 === self }) else { return }
        if nav.delegate !== self {
            previousNavigationDelegate = nav.delegate
            navigationControllerWeTookOver = nav
            nav.delegate = self
        }
        splitStack.isHidden = true
        for rail in rails where rail.parent === self {
            rail.deactivateColumnWidth()
            rail.willMove(toParent: nil)
            rail.view.removeFromSuperview()
            rail.removeFromParent()
        }
        if let child = detailViewController, child.parent === self {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        // Everything below `self` belongs to the host app, which may have pushed the HTDV onto a
        // stack of its own. Rebuilding as `[self] + rails` would silently discard those screens, so
        // the prefix is preserved. Recomputed from the LIVE stack on every render and never cached:
        // the host may push or pop below the HTDV between renders.
        //
        // `firstIndex(of:)` rather than `prefix(while: { $0 !== self })`: with the containment guard
        // above, `self` is on the stack and the two agree. Without it they failed in opposite
        // directions — `prefix(while:)` returning the WHOLE stack and grafting this HTDV on top of
        // someone else's screens, `firstIndex(of:)` returning nothing and wiping them. The guard is
        // what makes either correct; keep it if this expression is ever revisited.
        let prefix = nav.viewControllers.firstIndex(of: self).map { Array(nav.viewControllers[..<$0]) } ?? []
        // When this HTDV is the navigation stack's own root, Back from rail0 would land on `self`'s
        // own view — which is hidden above (`splitStack.isHidden = true`) — stranding the user on a
        // blank screen. Suppress the Back button on rail0 only in that configuration; when a parent
        // controller pushed the HTDV, Back from rail0 must keep working to head toward that parent.
        // Computed from the prefix BEFORE the stack is rewritten: reading it back off
        // `nav.viewControllers.first` afterwards made it flip between renders, because by the second
        // render the stack had already been rewritten to start at `self`. Rails are recreated and
        // destroyed across renders, so this must be re-applied every render, never set once. Do not
        // simplify this to an unconditional hide.
        let hidesRootBackButton = prefix.isEmpty
        for (index, rail) in rails.enumerated() {
            rail.navigationItem.hidesBackButton = index == 0 && hidesRootBackButton
        }
        var stack: [UIViewController] = prefix
        stack.append(self)
        stack.append(contentsOf: rails)
        if let child = detailViewController { stack.append(child) }
        if nav.viewControllers != stack { nav.setViewControllers(stack, animated: true) }
        // Self-caused: record the intended stack so the `didShow` callback this triggers (whether
        // or not the array actually changed above) is recognized as our own change.
        lastAppliedCompactStack = stack.map(ObjectIdentifier.init)
    }

    // MARK: UINavigationControllerDelegate

    /// Fires after every push, pop, or `setViewControllers` update completes — including a
    /// user-driven Back tap or edge swipe, which UIKit otherwise resolves entirely on its own with
    /// no callback into `HTDVController`. Updates this instance caused itself are recognized via
    /// `lastAppliedCompactStack` and ignored so a programmatic stack change never re-enters
    /// reconciliation a second time.
    public func navigationController(
        _ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool
    ) {
        let currentStack = navigationController.viewControllers
        let currentIdentities = currentStack.map(ObjectIdentifier.init)
        guard currentIdentities != lastAppliedCompactStack else { return }
        lastAppliedCompactStack = currentIdentities
        reconcileAfterInteractivePop(currentStack: currentStack)
    }

    /// Reconciles `rails`, `detailViewController`, and `HTDVController` with a compact-stack change
    /// that UIKit already performed on its own. Only rails still present in `currentStack` survive;
    /// the level index of the deepest surviving rail becomes the model's new depth.
    ///
    /// Popping rail0 is NOT a level pop and is handled separately by `leaveCompactStack(currentStack:)`.
    /// Routing it through `popToLevel` cannot work: `popToLevel(-1)` is total and empties the model
    /// (deliberately, and tested), while clamping it to `popToLevel(0)` hits that method's
    /// `levelIndex < levels.count - 1` guard with a single loaded level and does NOTHING — no state
    /// change, no `onChange`, no re-render — leaving the user on `self`'s own view, which
    /// `renderCompactStack()` hid. Rail0 going away means the user is leaving the HTDV, not asking the
    /// browser to forget its root.
    ///
    /// A rail-count change and a detail-only dismissal are mutually exclusive on the controller side —
    /// popping a rail always pops everything pushed above it (including any detail), so `popToLevel`
    /// alone already clears `controller.detail` via `truncate(toLevel:)` in that case. Only when the
    /// rail count is unchanged and just the detail was dismissed does `clearDetail()` need to run.
    /// Never call both: either would race the other's `onChange` and the model must settle in one step.
    private func reconcileAfterInteractivePop(currentStack: [UIViewController]) {
        let originalRailCount = rails.count
        let survivingRails = rails.filter { currentStack.contains($0) }
        let detailWasPopped = detailViewController.map { !currentStack.contains($0) } ?? false
        guard survivingRails.count < originalRailCount || detailWasPopped else { return }
        rails = survivingRails
        if detailWasPopped {
            detailViewController = nil
            renderedDetailID = nil
        }
        if survivingRails.count < originalRailCount {
            // `survivingRails.count - 1` is >= 0 in this branch: the empty case leaves above it.
            if survivingRails.isEmpty {
                leaveCompactStack(currentStack: currentStack)
            } else {
                controller.popToLevel(survivingRails.count - 1)
            }
        } else if detailWasPopped {
            controller.clearDetail()
        }
    }

    /// Rail0 was popped off the compact stack, so `self` is now the top of it — showing its own view,
    /// which `renderCompactStack()` hid, i.e. a blank screen. Two configurations, two answers:
    ///
    /// - A host pushed the HTDV (there is a prefix below `self`): the user is leaving the HTDV, so
    ///   take `self` off too and land them on the screen that pushed it, which is where the Back
    ///   button `renderCompactStack()` deliberately left enabled was pointing.
    /// - The HTDV is the stack root: there is nowhere to leave to, which is exactly why
    ///   `hidesRootBackButton` was true and rail0 had no Back button — so this is only reachable via
    ///   an edge swipe UIKit did not suppress. Restore rather than strand: re-render, which rebuilds
    ///   rail0 (`syncRailCount()` always wants at least one) and re-hides `splitStack`.
    private func leaveCompactStack(currentStack: [UIViewController]) {
        guard let nav = navigationController,
              let selfIndex = currentStack.firstIndex(where: { $0 === self }) else { return }
        guard selfIndex > 0 else {
            render()
            return
        }
        nav.popToViewController(currentStack[selfIndex - 1], animated: true)
        // Self-caused: record the resulting stack so the `didShow` callback this triggers is
        // recognized as our own change, not a user-driven pop.
        lastAppliedCompactStack = nav.viewControllers.map(ObjectIdentifier.init)
    }

    // MARK: Containment

    /// The restore point for the navigation delegate taken over in `renderCompactStack()`. Fires when
    /// this HTDV is popped off (or otherwise removed from) the navigation controller. `deinit` is not
    /// used as a backstop: the slot is weak, so by then it may already read nil, and a `@MainActor`
    /// deinit cannot safely touch isolated state under Swift 6 concurrency checking.
    override public func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        guard parent == nil else { return }
        restoreNavigationDelegate()
    }

    private func restoreNavigationDelegate() {
        let previous = previousNavigationDelegate
        previousNavigationDelegate = nil
        guard let nav = navigationControllerWeTookOver else { return }
        navigationControllerWeTookOver = nil
        // Only hand the slot back if it is still ours. Someone who installed their own delegate after
        // us owns it now, and clobbering it would be the very bug this fixes, with the roles swapped.
        guard nav.delegate === self else { return }
        nav.delegate = previous
    }

    // MARK: Actions

    private func railSelected(itemID: String, level: Int) {
        guard !isConfirmingDiscard else { return }
        isConfirmingDiscard = true
        Task { [weak self] in
            guard let self else { return }
            let proceed = await self.confirmDiscard()
            self.isConfirmingDiscard = false
            guard proceed else {
                self.render()
                return
            }
            await self.controller.select(itemID: itemID, atLevel: level)
        }
    }

    private func createTapped(level index: Int) {
        guard index < controller.levels.count, let action = controller.levels[index].createAction else { return }
        let host: UIViewController = isCompact ? (rails[index]) : self
        Task { [weak self] in
            guard let self else { return }
            await action.perform(host)
            await self.controller.reload(level: index)
        }
    }
}
#endif
