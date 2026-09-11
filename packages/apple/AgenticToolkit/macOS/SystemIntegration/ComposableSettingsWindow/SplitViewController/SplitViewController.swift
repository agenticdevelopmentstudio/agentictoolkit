import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

extension ComposableSettings {

    /// Split-pane settings container. Subclass and populate in `viewDidLoad` by
    /// calling `addPanel(_:)`. Sidebar is a `PanelListViewController`; the
    /// detail pane hosts the currently selected `any ComposableSettingsPanel`.
    @MainActor
    open class SplitViewController: ThemedSplitViewController {

        public private(set) var panels: [any ComposableSettingsPanel] = []

        /// Minimum width of the detail pane. This is the proper lever for the
        /// window's minimum width (window min = sidebar thickness + this) — it lets
        /// the detail grow freely, unlike a required width constraint on the content,
        /// which pins the window. Nested splits override it to 0 so they never
        /// re-impose the outer floor.
        open var detailMinimumThickness: CGFloat { 400 }

        /// Autosave name for the sidebar divider, so a draggable topic list
        /// persists its width. Only consulted when `contentSizedSidebar` is false.
        open var sidebarAutosaveName: String? { "ComposableSettings.RootSidebar" }

        /// When true, the sidebar is pinned to its content width (every title
        /// disclosed, never draggable, so switching panels never shifts the
        /// layout); when false it's the classic draggable band with autosave.
        ///
        /// Default false: the full-height *root* window sidebar keeps the draggable
        /// behaviour (its outline's column-fill misbehaves under a fixed width).
        /// Nested topic/detail splits opt in — they're the ones that visibly
        /// "move around" as you switch between them.
        open var contentSizedSidebar: Bool { false }

        /// External floor for the sidebar thickness. A parent split sets this on
        /// its nested-split panels so their sibling topic lists share one width —
        /// switching between panels then never moves the inner divider. `nil`
        /// sizes purely to this list's own content. Only used when
        /// `contentSizedSidebar` is true.
        open var minimumSidebarWidthOverride: CGFloat? {
            didSet { applySidebarWidth() }
        }

        /// The sidebar list controller. Inject a subclass to customize row
        /// presentation; defaults to a stock `PanelListViewController`.
        public let listViewController: PanelListViewController

        /// Title shown as a header above the sidebar's topic list; nil hides it.
        /// Forwards to the list controller, so it can be set before or after the
        /// view loads. The root settings window sets "Settings"; nested
        /// topic/detail panels default it to their own panel title.
        public var sidebarTitle: String? {
            didSet { if isViewLoaded { listViewController.setTitle(sidebarTitle) } }
        }

        /// Whether the sidebar leads with a search field that filters the panel
        /// list, as System Settings' does.
        ///
        /// Off by default and switched on only for the window's root split: a
        /// nested split's sidebar is a table of contents for one panel, and a
        /// second search field inside the first one's results is a maze.
        public var showsSidebarSearch: Bool = false

        /// Fired whenever the selection or the trail behind it changes, so a
        /// toolbar can revalidate its back/forward arrows and retitle itself.
        public var onNavigationChange: (() -> Void)?

        /// Title of the panel on screen — what the toolbar names beside the
        /// `‹ ›` control. A split whose selected panel is itself a split answers
        /// with the topic selected *inside* it: that is the panel the reader is
        /// looking at, and naming the outer container instead left the toolbar
        /// stuck on the container's name while the reader moved down its list.
        public var currentPanelTitle: String? {
            if let nested = currentPanel as? SplitViewController,
               let inner = nested.currentPanelTitle {
                return inner
            }
            return currentPanel?.descriptor.title
        }

        /// Where the `‹ ›` arrows can go from here.
        private var history = SettingsNavigationHistory()

        /// The split whose trail the `‹ ›` arrows should act on: the innermost
        /// one still able to move in the asked-for direction, else this one.
        ///
        /// Only the window's root split is wired to the toolbar, but the
        /// reader's last step may well have been taken inside a nested topic
        /// list — so "back" has to undo *that* before it backs out of the nested
        /// panel entirely.
        private func navigator(goingBack: Bool) -> SplitViewController {
            guard let inner = (currentPanel as? SplitViewController)?
                    .navigator(goingBack: goingBack),
                  goingBack ? inner.history.canGoBack : inner.history.canGoForward
            else { return self }
            return inner
        }

        public var canGoBack: Bool { navigator(goingBack: true).history.canGoBack }
        public var canGoForward: Bool { navigator(goingBack: false).history.canGoForward }

        private let detailContainer = NSViewController()

        /// The detail pane's persistent chrome — panel content plus the help
        /// button. Outlives every panel switch, so the button never flickers just
        /// because the selection moved.
        private let panelHost = PanelHostView()

        /// Where this split's panels show their help. The settings window sets it
        /// on its root split and nowhere else, which is what keeps a nested split
        /// from opening a second drawer: with no presenter, its help button never
        /// appears and the *outer* split shows the nested panel's help instead.
        public var helpPresenter: (any SettingsHelpPresenting)? {
            didSet { panelHost.helpPresenter = helpPresenter }
        }

        /// Whether the detail pane draws the `?` itself. A window that carries
        /// help in its toolbar — where a window-level control belongs — turns
        /// it off and drives help through `toggleHelp()` instead. A split shown
        /// in a sheet has no toolbar and leaves it on.
        public var showsInlineHelpButton: Bool = true {
            didSet { panelHost.showsHelpButton = showsInlineHelpButton }
        }

        /// Fired when help is disclosed or dismissed, so a toolbar button can
        /// report the same state the inline one does. Separate from
        /// `onNavigationChange` because a drawer moves without the selection
        /// moving — including on its own, when a remembered preference is
        /// re-applied or the reader drags it shut.
        public var onHelpVisibilityChange: (() -> Void)? {
            didSet {
                panelHost.onHelpVisibilityChange = { [weak self] in
                    self?.onHelpVisibilityChange?()
                }
            }
        }

        /// Shows or hides help. For chrome outside this split; the detail
        /// pane's own button goes straight to the presenter.
        public func toggleHelp() { panelHost.toggleHelp() }

        public var isHelpVisible: Bool { panelHost.isHelpVisible }

        // Repaints the window chrome and detail pane on every theme change.
        private var themeObserver: ThemePaletteObserver?

        /// The sidebar's search field, built only if `showsSidebarSearch` asks
        /// for it. Filtering happens in the list controller — this is just the
        /// control that feeds it.
        private lazy var searchField: ThemedSearchField = {
            let field = ThemedSearchField(placeholder: "Search")
            field.translatesAutoresizingMaskIntoConstraints = false
            // Filter as the user types rather than on Return: the list is short
            // enough that the narrowing *is* the feedback.
            field.sendsWholeSearchString = false
            field.sendsSearchStringImmediately = true
            field.target = self
            field.action = #selector(searchQueryChanged(_:))
            return field
        }()

        @objc private func searchQueryChanged(_ sender: NSSearchField) {
            listViewController.searchQuery = sender.stringValue
        }

        public init(listViewController: PanelListViewController = PanelListViewController()) {
            self.listViewController = listViewController
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError() }

        open override func viewDidLoad() {
            super.viewDidLoad()

            listViewController.setTitle(sidebarTitle)
            if showsSidebarSearch {
                listViewController.setHeaderAccessoryView(searchField)
            }

            let detailView = NSView()
            detailView.wantsLayer = true
            detailContainer.view = detailView
            detailView.addSubview(panelHost)
            // Top against the safe area, the rest against the view: the detail
            // pane's fill reaches up behind the toolbar so the colour is
            // continuous, but its content starts below the band. Outside a
            // full-height-content window the inset is zero.
            NSLayoutConstraint.activate([
                panelHost.topAnchor.constraint(equalTo: detailView.safeAreaLayoutGuide.topAnchor),
                panelHost.leadingAnchor.constraint(equalTo: detailView.leadingAnchor),
                panelHost.trailingAnchor.constraint(equalTo: detailView.trailingAnchor),
                panelHost.bottomAnchor.constraint(equalTo: detailView.bottomAnchor)
            ])

            let sidebarItem = NSSplitViewItem(sidebarWithViewController: listViewController)
            // The topic list must never auto-hide — it's the only way to switch
            // panels, so a collapse (from a narrow window or the toolbar toggle)
            // would strand the user in the detail pane.
            sidebarItem.canCollapse = false
            // Higher holding priority than the detail so, on window resize, the
            // detail absorbs the change and the sidebar keeps its width.
            sidebarItem.holdingPriority = .defaultLow + 1
            addSplitViewItem(sidebarItem)

            let detailItem = NSSplitViewItem(viewController: detailContainer)
            detailItem.minimumThickness = detailMinimumThickness
            detailItem.holdingPriority = .defaultLow
            addSplitViewItem(detailItem)

            if contentSizedSidebar {
                // Content-sized, fixed-width sidebar: exactly as wide as the widest
                // row needs (every title disclosed) and never draggable, so
                // switching panels never shifts the layout. No autosave — the width
                // is derived from content, not a remembered drag.
                applySidebarWidth()
            } else {
                // Classic draggable band, width persisted via autosave.
                sidebarItem.minimumThickness = 160
                sidebarItem.maximumThickness = 360
                splitView.autosaveName = sidebarAutosaveName
            }

            listViewController.onSelectPanel = { [weak self] panel in
                guard let self else { return }
                // A click is a navigation step like any other, so it joins the
                // trail here rather than in `selectPanel(at:)` — that one is the
                // programmatic door, and routing the click through it would
                // re-select the row the user just clicked.
                if let panel, let index = self.panels.firstIndex(where: { $0 === panel }) {
                    self.history.record(index)
                }
                self.show(panel)
                self.notifyNavigationChange()
            }

            applyDetailMinimumThickness()

            themeObserver = ThemePaletteObserver(host: view) { [weak self] palette in
                self?.applyTheme(palette)
            }
        }

        open override func viewWillAppear() {
            super.viewWillAppear()
            // The first `applyTheme` runs from `viewDidLoad`, where there is no
            // window yet to paint — so without this the window keeps its stock
            // grey, which a transparent titlebar puts on show along the top.
            applyTheme(ThemePaletteObserver.currentPalette)
            updateSidebarLayout()
            // Auto-select the first panel so the detail pane is never blank.
            if currentPanel == nil, let first = panels.first {
                selectPanel(first)
            }
        }

        /// Re-unifies sibling nested sidebars and re-pins this split's own sidebar.
        /// Called on appearance and whenever the panel set changes, so panels added
        /// while the window is already open still share one width (rather than the
        /// new split sizing to its own content while its siblings keep the old one).
        private func updateSidebarLayout() {
            unifyNestedSidebars()
            applySidebarWidth()
        }

        /// Pins the content-sized sidebar to a single width (min == max), so the
        /// topic list fully discloses its rows and can never be dragged.
        private func applySidebarWidth() {
            guard contentSizedSidebar, isViewLoaded, let sidebarItem = splitViewItems.first else { return }
            // When a parent has unified sibling widths, `minimumSidebarWidthOverride`
            // is already the authoritative (widest) width, so use it directly rather
            // than re-measuring this list. Capped so a pathologically long row
            // truncates instead of blowing out the sidebar (and the window minimum).
            let width = min(minimumSidebarWidthOverride ?? listViewController.preferredWidth(),
                            Self.maximumContentSidebarWidth)
            sidebarItem.minimumThickness = width
            sidebarItem.maximumThickness = width
        }

        /// When this split's panels are themselves nested splits (siblings that
        /// swap into the detail slot), give them all one width — the widest any of
        /// their topic lists needs — so switching between them never moves the
        /// inner divider. Force-loads each so its list is populated enough to
        /// report a content width (they otherwise load lazily on first show).
        private func unifyNestedSidebars() {
            let nested = panels.compactMap { $0 as? SplitViewController }
            guard nested.count > 1 else { return }
            let widest = min(
                nested.map { split -> CGFloat in
                    _ = split.view
                    return split.listViewController.preferredWidth()
                }.max() ?? 0,
                Self.maximumContentSidebarWidth)
            for split in nested {
                split.minimumSidebarWidthOverride = widest
            }
            // Widen the detail pane hosting these nested splits so the widest one
            // (its now-fixed sidebar + its own detail floor) can't be squeezed
            // below that floor at the window's minimum size; this lifts the
            // window's effective minimum width to fit the content instead.
            nestedDetailFloor = nested.map { widest + $0.detailMinimumThickness }.max() ?? 0
            applyDetailMinimumThickness()
        }

        /// Floor the nested splits need, or 0 when this split hosts none. Held
        /// separately from `detailMinimumThickness` so the nested-sidebar pass can
        /// be re-run without overwriting the subclass's own floor.
        private var nestedDetailFloor: CGFloat = 0

        /// The detail item's floor: whichever of the two floors is larger. Help
        /// contributes nothing — the drawer opens *outside* the window, so it
        /// costs the panel no width at all.
        private func applyDetailMinimumThickness() {
            guard isViewLoaded else { return }
            splitViewItems.last?.minimumThickness = max(detailMinimumThickness, nestedDetailFloor)
        }

        /// Upper bound on a content-sized sidebar, so one unusually long row
        /// truncates rather than pushing the window's minimum width arbitrarily wide.
        private static let maximumContentSidebarWidth: CGFloat = 480

        private func applyTheme(_ palette: SemanticPalette) {
            // One background under everything — sidebar, detail pane, and the
            // window itself, which shows at the rounded corners and behind the
            // transparent titlebar. Depth in this window comes from the cards
            // being raised off that ground, so a second, subtly different ground
            // under the detail pane only reads as a seam down the middle.
            let background = palette.windowBackgroundColor
            view.window?.backgroundColor = background
            detailContainer.view.layer?.backgroundColor = background.cgColor
        }

        // MARK: - Panel management

        public func setPanels(_ panels: [any ComposableSettingsPanel]) {
            self.panels = panels
            // The trail is a list of positions in `panels`; a different list makes
            // every one of them point somewhere else.
            history.reset()
            listViewController.setPanels(panels)
            updateSidebarLayout()
            restoreSelectionAfterRebuild()
            notifyNavigationChange()
        }

        public func addPanel(_ panel: any ComposableSettingsPanel) {
            // Appending leaves every existing position where it was, so the trail
            // still points at the panels it was recorded for.
            panels.append(panel)
            listViewController.setPanels(panels)
            updateSidebarLayout()
            // The arrows' reach changed even though the selection did not: a
            // toolbar that isn't told keeps its forward arrow disabled past the
            // panel that would now answer it.
            notifyNavigationChange()
        }

        public func removePanel(_ panel: any ComposableSettingsPanel) {
            panels.removeAll { $0 === panel }
            history.reset()
            listViewController.setPanels(panels)
            updateSidebarLayout()
            // Removing the panel on screen used to be the only case handled
            // here, and it is the *rarer* one. Removing any panel above it in
            // the list shifts every row below by one — the sidebar's row ids
            // are positions in `panels` — so the id `setSections` preserves
            // across the rebuild now names the panel *after* the one the user
            // was reading: the highlight sits on Advanced while the detail
            // pane shows Themes, and `history.reset()` above has already
            // emptied the trail the arrows would have used to get back. The
            // shared restore below covers both cases.
            restoreSelectionAfterRebuild()
            notifyNavigationChange()
        }

        /// Puts the sidebar highlight and the navigation trail back onto the
        /// panel that is still in the detail pane, after a rebuild that
        /// renumbered the rows — or empties the detail pane when that panel is
        /// no longer in the list.
        ///
        /// A panel that is gone must not stay on screen: no row names it any
        /// more, so it would sit there unreachable and unhighlighted. One that
        /// survived keeps its place, and its row is re-selected at its *new*
        /// index — which is the whole point, since `setSections` restores the
        /// old selection by id and those ids are positions.
        ///
        /// The trail is re-seeded with that index because the callers reset it
        /// (a list that changed shape makes every recorded position mean
        /// something else); without the re-record, Back and Forward are dead
        /// until the user clicks a row.
        private func restoreSelectionAfterRebuild() {
            guard let current = currentPanel else { return }
            guard let index = panels.firstIndex(where: { $0 === current }) else {
                show(nil)
                return
            }
            history.record(index)
            // A filter that hides the surviving panel would make the selection
            // a silent no-op and leave the stale highlight in place, so the
            // query goes — the same trade `navigate(to:)` makes, and only when
            // it is actually needed.
            if !listViewController.isPanelVisible(at: index) { clearSidebarSearch() }
            listViewController.selectPanel(at: index)
        }

        public func clear() {
            panels.removeAll()
            history.reset()
            listViewController.setPanels(panels)
            show(nil)
            notifyNavigationChange()
        }

        public func selectPanel(_ panel: any ComposableSettingsPanel) {
            guard let index = panels.firstIndex(where: { $0 === panel }) else { return }
            selectPanel(at: index)
        }

        public func selectPanel(at index: Int) {
            guard panels.indices.contains(index) else { return }
            history.record(index)
            navigate(to: index)
        }

        /// Steps back to the previously shown panel. No-op at the start of the trail.
        public func goBack() {
            let target = navigator(goingBack: true)
            guard let index = target.history.goBack() else { return }
            target.navigate(to: index)
        }

        /// Steps forward again after a `goBack()`. No-op at the end of the trail.
        public func goForward() {
            let target = navigator(goingBack: false)
            guard let index = target.history.goForward() else { return }
            target.navigate(to: index)
        }

        /// Shows a panel the history has already accounted for — the one path
        /// that must never record a step, or going back would append the place
        /// it came from and the arrows would ping-pong.
        private func navigate(to index: Int) {
            guard panels.indices.contains(index) else { return }
            // Going somewhere the current filter hides would select a row that
            // isn't there: the panel arrives in the detail pane with nothing
            // highlighted beside it in the sidebar. A step taken by the arrows
            // is a step out of the search results, so the field empties with it.
            clearSidebarSearch()
            listViewController.selectPanel(at: index)
            show(panels[index])
            notifyNavigationChange()
        }

        /// Empties the sidebar's search field and the filter it drives. No-op on
        /// a split that has no search field, so the lazy control is never built
        /// just to be cleared.
        private func clearSidebarSearch() {
            guard showsSidebarSearch, !listViewController.searchQuery.isEmpty else { return }
            searchField.stringValue = ""
            listViewController.searchQuery = ""
        }

        /// Announces a navigation to this split's observer and to every split
        /// above it. The toolbar's arrows are wired to the window's root split
        /// only, so a step taken inside a nested topic list has to travel
        /// outwards or they stay stale — describing a trail nobody is on.
        private func notifyNavigationChange() {
            onNavigationChange?()
            enclosingSettingsSplit?.notifyNavigationChange()
        }

        // MARK: - Detail pane

        private var currentPanel: (any ComposableSettingsPanel)? {
            detailContainer.children.first as? any ComposableSettingsPanel
        }

        /// The help the drawer should show while this split is on screen: the
        /// *innermost* selected panel's, not this level's. A panel that holds a
        /// selection of its own answers for what is selected inside it — see
        /// `ComposableSettingsPanel.effectiveHelpContent`.
        public var effectiveHelp: PanelHelp? {
            currentPanel?.effectiveHelpContent
        }

        /// Re-reads the selected panel's help and hands it to the presenter.
        /// Called up the chain when a *nested* split changes topic: only the
        /// outermost split has a presenter, so a nested selection has to travel
        /// there or the drawer keeps showing the topic the user just left.
        public func refreshHelp() {
            panelHost.setHelp(effectiveHelp)
            enclosingSettingsSplit?.refreshHelp()
        }

        private func show(_ panel: (any ComposableSettingsPanel)?) {
            for child in detailContainer.children {
                child.removeFromParent()
            }
            // `setContent` drops every hosted view. A scroll-wrapped panel's view
            // lives inside a wrapper NSScrollView (added below), so removing only
            // the panel's own view would orphan that wrapper on each switch.
            guard let panel else {
                panelHost.setContent(nil)
                panelHost.setHelp(nil)
                enclosingSettingsSplit?.refreshHelp()
                applyDetailMinimumThickness()
                return
            }
            detailContainer.addChild(panel)
            panel.view.translatesAutoresizingMaskIntoConstraints = false

            // Nested splits manage their own layout and self-scrolling panels
            // scroll themselves — both are hosted directly. Every other panel is
            // wrapped in a `PanelScrollView`, so content fills the detail,
            // wrapping labels wrap, tall content scrolls, and the content's
            // fitting size never drives the window — its size is the user's alone.
            if panel is SplitViewController || panel.hostsOwnScroll {
                panelHost.setContent(panel.view)
            } else {
                let scroll = PanelScrollView()
                scroll.setContent(panel.view)
                panelHost.setContent(scroll)
            }

            panelHost.setHelp(effectiveHelp)
            enclosingSettingsSplit?.refreshHelp()
            applyDetailMinimumThickness()
        }
    }
}

extension NSViewController {

    /// The nearest `ComposableSettings.SplitViewController` above this one.
    ///
    /// Found by walking `parent` rather than stored, so nesting stays a matter
    /// of who adds whom as a child and nothing has to be wired up twice. It is
    /// how an inner selection's help reaches the one presenter, which lives at
    /// the outermost split.
    @MainActor
    var enclosingSettingsSplit: ComposableSettings.SplitViewController? {
        var candidate = self.parent
        while let current = candidate {
            if let split = current as? ComposableSettings.SplitViewController { return split }
            candidate = current.parent
        }
        return nil
    }
}
