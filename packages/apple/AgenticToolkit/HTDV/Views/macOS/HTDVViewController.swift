#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

/// Hosts the rails (in a horizontally scrolling stack) beside the detail pane, with a breadcrumb bar on top.
/// Observes `HTDVController.onChange` and re-renders; forwards rail selection back to the controller.
public final class HTDVViewController: NSViewController {
    public let controller: HTDVController
    public let layoutEngine: HTDVLayoutEngine
    public private(set) var detailViewController: NSViewController?
    public var railViews: [HTDVRailView] { railStack.arrangedSubviews.compactMap { $0 as? HTDVRailView } }

    let breadcrumbBar = HTDVBreadcrumbBar(frame: .zero)
    let railStack = NSStackView()
    let railScrollView = NSScrollView()
    let detailContainer = NSView()
    private let splitStack = NSStackView()
    private var detailWidthConstraint: NSLayoutConstraint?
    private var renderedDetailID: String?
    /// Guards against a second selection opening a second discard prompt while the first
    /// `confirmDiscard()` is still awaiting the user.
    @MainActor private var isConfirmingDiscard = false
    /// Whether this host has ever rendered a non-empty model. Separates "emptied by a pop" — which
    /// the recovery net below exists for — from "never loaded", which is by value identical and must
    /// NOT trigger a fetch the app never asked for. See `isEmptyDeadEnd`.
    private var hasEverHadLevels = false

    public init(controller: HTDVController, layoutEngine: HTDVLayoutEngine = HTDVLayoutEngine()) {
        self.controller = controller
        self.layoutEngine = layoutEngine
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override public func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        railStack.orientation = .horizontal
        railStack.spacing = 0
        railStack.alignment = .top
        railStack.translatesAutoresizingMaskIntoConstraints = false
        let railDocument = NSView()
        railDocument.translatesAutoresizingMaskIntoConstraints = false
        railDocument.addSubview(railStack)
        railScrollView.documentView = railDocument
        railScrollView.hasHorizontalScroller = true
        railScrollView.hasVerticalScroller = false
        railScrollView.drawsBackground = false
        railScrollView.translatesAutoresizingMaskIntoConstraints = false

        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        splitStack.orientation = .horizontal
        splitStack.spacing = 0
        splitStack.alignment = .top
        splitStack.translatesAutoresizingMaskIntoConstraints = false
        splitStack.addArrangedSubview(railScrollView)
        splitStack.addArrangedSubview(detailContainer)

        breadcrumbBar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(breadcrumbBar)
        root.addSubview(splitStack)
        let widthConstraint = detailContainer.widthAnchor.constraint(
            greaterThanOrEqualToConstant: layoutEngine.minDetailWidth
        )
        detailWidthConstraint = widthConstraint
        NSLayoutConstraint.activate([
            breadcrumbBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            breadcrumbBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            breadcrumbBar.topAnchor.constraint(equalTo: root.topAnchor),
            splitStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            splitStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            splitStack.topAnchor.constraint(equalTo: breadcrumbBar.bottomAnchor),
            splitStack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            railScrollView.heightAnchor.constraint(equalTo: splitStack.heightAnchor),
            detailContainer.heightAnchor.constraint(equalTo: splitStack.heightAnchor),
            railStack.leadingAnchor.constraint(equalTo: railDocument.leadingAnchor),
            railStack.trailingAnchor.constraint(equalTo: railDocument.trailingAnchor),
            railStack.topAnchor.constraint(equalTo: railDocument.topAnchor),
            railStack.bottomAnchor.constraint(equalTo: railDocument.bottomAnchor),
            railDocument.heightAnchor.constraint(equalTo: railScrollView.heightAnchor),
            widthConstraint
        ])
        view = root

        breadcrumbBar.onSelectCrumb = { [weak self] index in self?.crumbSelected(index) }
        controller.onChange = { [weak self] _ in self?.render() }
        render()
    }

    override public func viewDidLayout() {
        super.viewDidLayout()
        applyLayoutMode()
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
        for (index, rail) in railViews.enumerated() {
            let selectedID = index < controller.selection.count ? controller.selection[index] : nil
            if index < controller.levels.count {
                rail.apply(level: controller.levels[index], selectedID: selectedID)
            }
            if controller.loadingLevelIndex == index {
                rail.showLoading()
            }
            if let error = controller.error, error.levelIndex == index {
                rail.showError(error.message) { [weak self] in
                    guard let self else { return }
                    Task { await self.controller.retry() }
                }
            }
        }
        breadcrumbBar.apply(titles: controller.levels.map(\.title))
        renderDetail()
        applyLayoutMode()
        recoverFromEmptyModelIfNeeded()
    }

    /// An emptied model (`popToLevel(-1)`, or an interactive pop that reconciles to it) left the host
    /// rendering one blank placeholder rail with no spinner, no error, no retry and no reload — a dead
    /// end the user could not leave. Re-issue the root load instead, so the next render shows a
    /// spinner, then either content or an error with a retry.
    ///
    /// Recursion is broken twice over, by state rather than by a re-entrancy flag. `load()` publishes
    /// `loadingLevelIndex` (and fires `onChange`) inside `beginRequest`, BEFORE its first `await`, so
    /// the `render()` it re-enters already fails the guard below; and the post-hop re-check inside the
    /// `Task` catches the same thing again from the other side, so this holds even if that ordering
    /// ever changes. `testEmptyModelRecoveryFiresExactlyOnce` pins the pair: remove both and this
    /// spins, re-fetching the root on every render.
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
    /// from `loadView()`, when `levels` is empty, `error` is nil and nothing is loading — by value
    /// identical to the emptied-by-pop state — so without it merely BUILDING the view issued a root
    /// fetch, and a host that loads from `viewDidAppear` (or defers until the user picks a
    /// workspace) got that fetch unasked, plus a second one when it did load. Not
    /// `controller.generation > 0`: that is an internal request counter, and reading it from a host
    /// would make a private sequencing detail a load-bearing contract.
    private var isEmptyDeadEnd: Bool {
        hasEverHadLevels && controller.levels.isEmpty && controller.error == nil
            && controller.loadingLevelIndex == nil
    }

    /// One rail per loaded level, plus one placeholder rail while the next level is loading or errored.
    private func syncRailCount() {
        var wanted = controller.levels.count
        if let loading = controller.loadingLevelIndex, loading >= wanted { wanted = loading + 1 }
        if let error = controller.error, error.levelIndex >= wanted { wanted = error.levelIndex + 1 }
        wanted = max(wanted, 1)
        while railViews.count > wanted {
            railStack.arrangedSubviews.last?.removeFromSuperview()
        }
        while railViews.count < wanted {
            let rail = HTDVRailView(levelIndex: railViews.count)
            rail.widthAnchor.constraint(equalToConstant: layoutEngine.railWidth).isActive = true
            let index = rail.levelIndex
            rail.onSelect = { [weak self] itemID in self?.railSelected(itemID: itemID, level: index) }
            rail.onCreate = { [weak self] in self?.createTapped(level: index) }
            railStack.addArrangedSubview(rail)
        }
    }

    private func renderDetail() {
        guard controller.detail?.id != renderedDetailID else { return }
        detailViewController?.view.removeFromSuperview()
        detailViewController?.removeFromParent()
        detailViewController = nil
        renderedDetailID = controller.detail?.id
        guard let detail = controller.detail else { return }
        let child = detail.make()
        attachFormCallbacks(to: child)
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor)
        ])
        detailViewController = child
    }

    /// A saved or deleted form changes the row that owns it, so the last level is re-fetched: labels
    /// follow the edit, and `reload(level:)` drops the selection when the row is gone. Chains onto
    /// whatever the detail factory already installed rather than replacing it, so a module that does
    /// its own bookkeeping on save still gets called.
    private func attachFormCallbacks(to child: NSViewController) {
        guard let form = child as? FormViewController else { return }
        // `HTDVDetail.make`'s contract does not require a fresh `FormViewController` per call, so a
        // memoized instance re-attached on every render would otherwise accumulate one chained closure
        // per attach and fire N reloads per save. The marker is carried BY the form: a host-side set
        // keyed on `ObjectIdentifier` mistook a recycled address for the previous, already-freed form.
        guard !form.hasHostLevelReloadAttached else { return }
        form.hasHostLevelReloadAttached = true
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

    private func applyLayoutMode() {
        let mode = layoutEngine.layout(
            availableWidth: view.bounds.width, levelCount: railViews.count,
            hasDetail: controller.detail != nil, isCompact: false
        )
        guard case .columns(let visible, let showsDetail) = mode else { return }
        detailContainer.isHidden = !showsDetail
        detailWidthConstraint?.isActive = showsDetail
        // Scroll so the rightmost visible rails are on screen.
        if let first = visible.first {
            let scrollOriginX = CGFloat(first) * layoutEngine.railWidth
            railScrollView.contentView.scroll(to: NSPoint(x: scrollOriginX, y: 0))
            railScrollView.reflectScrolledClipView(railScrollView.contentView)
        }
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

    /// A breadcrumb names a level that is ALREADY loaded, so selecting crumb `i` pops back to level
    /// `i`. It used to call `railSelected(level: i)`, which re-selected the item at level `i` and
    /// pushed its child back on — navigating one level DEEPER than the crumb the user clicked, and
    /// growing the breadcrumb bar on a control whose entire purpose is to shrink it.
    ///
    /// `popToLevel` no-ops at or beyond the deepest level; the second guard makes the deepest crumb
    /// explicitly a no-op so it does not put up a discard prompt for a navigation that cannot happen.
    private func crumbSelected(_ index: Int) {
        guard index >= 0, index < controller.levels.count - 1 else { return }
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
            self.controller.popToLevel(index)
        }
    }

    private func createTapped(level index: Int) {
        guard index < controller.levels.count, let action = controller.levels[index].createAction else { return }
        Task { [weak self] in
            guard let self else { return }
            await action.perform(self)
            await self.controller.reload(level: index)
        }
    }
}
#endif
