import AppKit
import Combine

import AgenticDeveloperToolkitUI
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// The toolbar's item identifiers. Private to this file, exactly as
/// `NotesWindowToolbar` keeps its own: nothing outside names them in code, and
/// the UI suite reaches these controls by the string value.
private extension NSToolbarItem.Identifier {
    static let projectSearch = NSToolbarItem.Identifier("project.toolbar.search")
    static let projectHelp = NSToolbarItem.Identifier("project.toolbar.help")
}

/// What a project remembers about its window, under `project_setting`.
///
/// Namespaced by hand rather than by a wrapper: unlike pane state, these keys
/// are not shared with anything a pane writes, so the prefix is documentation
/// rather than a collision guard.
private enum ProjectWindowSetting {
    static let drawerOpen = "drawer.open"
    static let drawerTab = "drawer.tab"
    static let drawerWidth = "drawer.width"
}

/// A project's window. Its geometry persists per project, under a window id
/// built from the repo id: two projects open side by side are two windows the
/// user has placed differently, and one id for both would mean each remembers
/// only where the other was closed. (`WindowRegistry` also assumes one live
/// controller per id, which a shared id quietly broke.) Content layout — the
/// per-tab nested split tree, tab arrangement, active tab — lives in the
/// project database, keyed by the same repo id.
///
/// The window's content view is a generic `MultiTabbedViewController` from the
/// toolkit. Each tab hosts its own `ComposableTabsViewController` rooted at
/// the layout tree persisted for that tab.
///
/// The tab count is global across edges: one project-level "tab" is a
/// group with one member tab per enabled edge, all sharing a title.
/// Creating a tab creates a member on every enabled edge, closing any
/// member closes its whole group, and a newly enabled edge is topped up
/// to one member per group.
@MainActor
public final class ComposableTabsWindowController: WindowController<NSViewController>, NSMenuItemValidation {

    /// The window-id prefix, and the id every project window used before
    /// geometry became per-project. Kept as the prefix so a stored frame is
    /// recognisably a project window's in `UserDefaults`.
    public static let windowIDPrefix = "projectWindow"

    /// The window id for one project. Deleting the project is what deletes the
    /// frame — see `WindowFrameManager.clearSavedState(for:)`.
    public static func windowID(for repoID: UUID) -> String {
        "\(windowIDPrefix).\(repoID.uuidString)"
    }

    private struct TabGroup {
        let id: UUID
        var title: String
        var members: [Edge: UUID]
    }

    public let project: ProjectWorkspace
    private let tabbed: MultiTabbedViewController

    /// The window's content: the tabs, with the footer under them. Held so the
    /// footer can be reached without walking `window?.contentViewController`,
    /// which is nil until the window loads.
    private let content: WindowFooterContentViewController

    /// Stored, never a local in `configureWindow`: `NSToolbar.delegate` is
    /// `weak`, so a delegate with no other owner is deallocated the instant
    /// configuration returns, leaving a toolbar with no items and no error.
    ///
    /// `lazy` so the whole wiring is one initialiser call: a `let` cannot name
    /// `self` before `super.init`, which is what pushed target, search delegate
    /// and availability onto three separate later assignments. It is first
    /// forced during `init` itself — `installInitialTabs()` reaches it through
    /// the `activeTabDidChange` refresh, and the tail of `init` asks again —
    /// which is after `super.init`, and being after `super.init` is all `lazy`
    /// needs.
    ///
    /// Internal rather than private because a custom-view item only exists once
    /// the delegate has been asked for it, and a test with no window on screen
    /// has to do the asking itself.
    lazy var toolbarDelegate = WindowToolbarBuilder.Delegate(
        items: [
            .flexibleSpace,
            .search(identifier: .projectSearch, placeholder: "Search"),
            .button(
                identifier: .projectHelp,
                symbol: "questionmark.circle",
                label: "Help",
                action: #selector(ComposableTabsWindowController.toggleHelp))
        ],
        target: self,
        searchDelegate: self,
        onSearchFieldCreated: { [weak self] field in
            self?.applySearchAvailability(to: field)
        }
    )

    /// The titlebar search field, once the toolbar has built it.
    public var searchField: NSSearchField? { toolbarDelegate.searchField }

    /// The window's help, behind the protocol that keeps `NSDrawer`'s
    /// deprecation out of the chrome that asks for it: the toolbar descriptor,
    /// its `#selector` and the glyph refresh all talk to `HelpPresenting`,
    /// whose requirements carry no annotation. Built in `configureWindow(_:)`,
    /// because a drawer needs a window that exists.
    private var helpPresenter: (any HelpPresenting)?

    /// The pane the search field is currently pointed at, so a redundant
    /// refresh does not throw away what the user has typed.
    private var searchTargetNodeID: UUID?

    /// The strip across the bottom. Public because the UI suite and the
    /// scripting bridge both address it, and neither should have to know it
    /// arrived by composition.
    public var footer: WindowFooterBar { content.footer }

    /// Project-level tabs, in creation order.
    private var tabGroups: [TabGroup] = []

    /// Live mapping from a tab's UUID to the tab's root `ComposableTabsViewController`.
    /// Used by the layout-change callback to rebuild a tab's `TabRecord`
    /// when the user splits / closes panes inside a tab.
    private var splitControllersByTabID: [UUID: ComposableTabsViewController] = [:]

    /// Last focused leaf nodeID per tab — written through every time the
    /// window's first responder changes inside the active tab. Persisted
    /// alongside the layout tree on the next save.
    private var focusedLeafByTabID: [UUID: UUID] = [:]

    private var firstResponderObserver: NSObjectProtocol?
    private var pendingFocusPersist: DispatchWorkItem?
    private static let focusPersistDelay: DispatchTimeInterval = .milliseconds(250)

    private var titlebarAccessory: NSTitlebarAccessoryViewController?
    private var arrangeButton: NSButton?
    private var cancellables = Set<AnyCancellable>()

    /// Keeps the room around the panes following the setting while the window
    /// is open, so the Spacing panel previews on the window behind its sheet.
    private var spacingObservers: [UserSettingObserver<Int>] = []

    /// Keeps the plane behind the panes following the theme.
    private var backdropObserver: ThemePaletteObserver?

    public init(project: ProjectWorkspace) {
        self.project = project
        // Locals first: a stored property cannot be read back before
        // `super.init`, and the host needs the tab controller to wrap.
        let tabbed = MultiTabbedViewController()
        let content = WindowFooterContentViewController(
            contentViewController: tabbed,
            accessibilityPrefix: "project.footer"
        )
        self.tabbed = tabbed
        self.content = content
        super.init(windowID: Self.windowID(for: project.id), contentViewController: content)

        self.windowSpec = WindowSpec(
            defaultSize: NSSize(width: 800, height: 500),
            minSize: NSSize(width: 400, height: 300),
            defaultPosition: .center,
            persistsFrame: true
        )
        self.windowTitle = project.displayName
        self.windowStyleMask = [.titled, .closable, .resizable, .miniaturizable]
        self.minSize = NSSize(width: 400, height: 300)

        tabbed.delegate = self
        tabbed.contentInsets = PaneSpacing.contentInsets
        backdropObserver = ThemePaletteObserver(host: tabbed.view) { [weak self] palette in
            self?.tabbed.centerBackgroundColor = NSColor(palette.projectPaneBackdrop)
        }
        spacingObservers = PaneSpacing.edgeSettings.values.map { setting in
            UserSettingObserver(setting) { [weak self] _ in
                self?.tabbed.contentInsets = PaneSpacing.contentInsets
            }
        }
        installInitialTabs()

        // The pane the user is working in is tracked once for the whole app;
        // this window only cares when the change is its own.
        NotificationCenter.default.publisher(for: ComposableTabsActivePane.didChangeNotification)
            .sink { [weak self] notification in
                // Unwrap before comparing: a notification with no window and a
                // controller whose window is still nil would otherwise match
                // as `nil === nil`, and every such post would refresh this
                // window. Same shape as `ComposableTabsActivePane`'s observer.
                guard let self, let changed = notification.object as? NSWindow,
                      changed === self.window else { return }
                self.refreshActivePaneChrome()
            }
            .store(in: &cancellables)

        refreshActivePaneChrome()
    }

    isolated deinit {
        if let firstResponderObserver {
            NotificationCenter.default.removeObserver(firstResponderObserver)
        }
    }

    /// A unified toolbar, matching the Notes window, and the help drawer. The
    /// window title stays visible here where it does not in Notes: the title is
    /// the project's name, which is the one thing the toolbar does not say.
    ///
    /// Deliberately deprecated, exactly as `SettingsWindow`'s override is:
    /// `ProjectHelpDrawerController` wraps `NSDrawer`, and naming it from
    /// inside a deprecated declaration is what keeps the wrapper's deprecation
    /// from leaking outward. Nothing of ours calls this override —
    /// `loadWindow()` calls the base method — so the annotation warns nobody.
    @available(macOS, deprecated: 10.13, message: "Builds the NSDrawer-backed help presenter")
    public override func configureWindow(_ window: NSWindow) {
        super.configureWindow(window)
        window.toolbar = toolbarDelegate.makeToolbar(identifier: "project.toolbar")
        window.toolbarStyle = .unified

        // The window, not `self.window`: this runs *during* `loadWindow()`, so
        // the controller's own property is not pointing at it yet.
        let presenter = ProjectHelpDrawerController(parentWindow: window, project: project)
        presenter.setHelp(Self.helpContent)
        presenter.onVisibilityChange = { [weak self] in
            self?.refreshHelpButtonAppearance()
        }
        helpPresenter = presenter
    }

    public override func showWindow(_ sender: Any?) {
        // `NSWindowController.init(window: nil)` (which SingleWindowController
        // chains into) leaves `isWindowLoaded = true`, so the default
        // `showWindow(_:)` never calls `loadWindow()`. Force it here so the
        // first `showWindow(_:)` actually produces a visible window.
        if window == nil { loadWindow() }
        super.showWindow(sender)
        installFirstResponderObserverIfNeeded()
        installTitlebarAccessoryIfNeeded()
        restoreFocusedLeafForActiveTab()
        refreshActivePaneChrome()
        refreshHelpButtonAppearance()
    }

    // MARK: - Titlebar accessories

    /// Two buttons, right-aligned: the arrange toggle, then the project's
    /// settings. Which tab bars a window shows moved into those settings — it
    /// is a property of the project, not a thing to flick on and off from the
    /// titlebar while working.
    private func installTitlebarAccessoryIfNeeded() {
        guard titlebarAccessory == nil, let window else { return }

        let arrange = Self.titlebarButton(
            symbolName: "rectangle.3.group",
            description: "Arrange Panes",
            toolTip: "Arrange panes",
            target: self,
            action: #selector(toggleArrangeMode(_:))
        )
        arrange.accessibilityID("project-window.arrange-button")
        arrangeButton = arrange

        let settings = Self.titlebarButton(
            symbolName: "gearshape",
            description: "Project Settings",
            toolTip: "Project settings",
            target: self,
            action: #selector(showProjectSettings(_:))
        )
        settings.accessibilityID("project-window.project-settings-button")

        let stack = NSStackView(views: [arrange, settings])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.frame = NSRect(x: 0, y: 0, width: 80, height: 24)

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = stack
        accessory.layoutAttribute = .right
        window.addTitlebarAccessoryViewController(accessory)
        titlebarAccessory = accessory

        // The mode can also be turned on from the Window menu, so the button's
        // tint follows the mode rather than the click.
        NotificationCenter.default.publisher(for: ComposableTabsArrangeMode.didChangeNotification)
            .sink { [weak self] notification in
                guard let self, let changed = notification.object as? NSWindow,
                      changed === self.window else { return }
                self.refreshArrangeButton()
            }
            .store(in: &cancellables)
        refreshArrangeButton()
    }

    private static func titlebarButton(
        symbolName: String,
        description: String,
        toolTip: String,
        target: AnyObject,
        action: Selector
    ) -> NSButton {
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        let button = NSButton(image: symbol ?? NSImage(), target: target, action: action)
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.toolTip = toolTip
        button.frame = NSRect(x: 0, y: 0, width: 36, height: 24)
        return button
    }

    private func refreshArrangeButton() {
        let enabled = ComposableTabsArrangeMode.shared.isEnabled(in: window)
        arrangeButton?.contentTintColor =
            enabled ? tabbed.view.resolvedThemeScope.palette.nsColor(.accent) : nil
        arrangeButton?.state = enabled ? .on : .off
    }

    // MARK: - Arrange mode and project settings

    /// Also the target of the Window ▸ Arrange menu item, reached down the
    /// responder chain — one action for both, so the checkmark and the button
    /// tint can never disagree.
    @objc
    public func toggleArrangeMode(_ sender: Any?) {
        guard let window else { return }
        ComposableTabsArrangeMode.shared.toggle(in: window)
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleArrangeMode(_:)) {
            menuItem.state = ComposableTabsArrangeMode.shared.isEnabled(in: window) ? .on : .off
        }
        return true
    }

    @objc
    public func showProjectSettings(_ sender: Any?) {
        guard let contentViewController = window?.contentViewController else { return }
        let settings = ComposableTabsSettingsViewController(
            isEdgeEnabled: { [weak self] edge in self?.tabbed.isEdgeEnabled(edge) ?? false },
            setEdgeEnabled: { [weak self] edge, enabled in self?.setEdgeEnabled(edge, enabled) }
        )
        contentViewController.presentAsSheet(settings)
    }

    /// Single entry point for edge toggling (project settings and Cocoa
    /// Scripting alike) so a freshly enabled edge is always topped up to
    /// the global tab count and the edge set is persisted. Disabling keeps
    /// the edge's members so re-enabling restores them.
    public func setEdgeEnabled(_ edge: Edge, _ enabled: Bool) {
        guard tabbed.isEdgeEnabled(edge) != enabled else { return }
        // The last enabled edge stays enabled. A window with no tab bar has no
        // tabs, therefore no panes, and no control anywhere in it to bring one
        // back — the only way out would be the titlebar settings button
        // (`principle-of-least-astonishment`).
        guard enabled || Edge.allCases.contains(where: { $0 != edge && tabbed.isEdgeEnabled($0) }) else {
            return
        }
        tabbed.setEdgeEnabled(edge, enabled)
        if enabled {
            topUpTabs(on: edge)
        }
        persistAllTabs()
    }

    /// Gives `edge` one member tab per group so its count matches the
    /// global tab count. Returns whether it had to create any.
    @discardableResult
    private func topUpTabs(on edge: Edge) -> Bool {
        var created = false
        for (index, group) in tabGroups.enumerated() where group.members[edge] == nil {
            let id = UUID()
            let split = makeSplitController(for: id)
            tabbed.insertTab(.init(id: id, title: group.title, viewController: split), at: index, on: edge)
            tabGroups[index].members[edge] = id
            created = true
        }
        return created
    }

    /// Creates a project-level tab: one member per enabled edge, all
    /// sharing a title, and activates the first member.
    private func addTabGroup() {
        let title = "Tab \(tabGroups.count + 1)"
        var group = TabGroup(id: UUID(), title: title, members: [:])
        for edge in Edge.allCases where tabbed.isEdgeEnabled(edge) {
            let id = UUID()
            let split = makeSplitController(for: id)
            tabbed.addTab(.init(id: id, title: title, viewController: split), on: edge)
            group.members[edge] = id
        }
        tabGroups.append(group)
        for edge in Edge.allCases {
            if let id = group.members[edge] {
                tabbed.selectTab(id: id, on: edge)
                break
            }
        }
        persistAllTabs()
        // `selectTab(id:on:)` above already fired `activeTabDidChange`, and
        // that callback runs after `refreshCenterContent()`, so the primary
        // recompute has already happened. This one is belt and braces for the
        // asynchronous half: in a real window the pane swap posts
        // `ComposableTabsActivePane.didChangeNotification` as views come and
        // go, and `livePanes` orders out of an unordered `NSHashTable`, so a
        // recompute racing those posts can name either pane. Guarded and
        // idempotent, so keeping it costs one comparison.
        refreshActivePaneChrome()
    }

    private func makeSplitController(for tabID: UUID) -> ComposableTabsViewController {
        let split = ComposableTabsViewController.make(
            from: project.layout.blueprint(),
            project: project,
            isRoot: true
        )
        wireLayoutCallback(on: split, tabID: tabID)
        splitControllersByTabID[tabID] = split
        return split
    }

    // MARK: - Tab-edge accessors (used by Cocoa Scripting bridges)

    /// Names of the tab edges currently enabled in this window. Names are
    /// lowercase: `"top"`, `"right"`, `"bottom"`, `"left"`. Order matches
    /// `Edge.allCases`.
    public var enabledTabEdgeNames: [String] {
        get { Edge.allCases.filter { tabbed.isEdgeEnabled($0) }.map(\.rawValue) }
        set {
            let normalized = Set(newValue.map { $0.lowercased() })
            for edge in Edge.allCases {
                setEdgeEnabled(edge, normalized.contains(edge.rawValue))
            }
        }
    }

    // MARK: - Focused-leaf tracking

    private func installFirstResponderObserverIfNeeded() {
        guard firstResponderObserver == nil, let window else { return }
        // `NSWindow.didUpdateNotification` fires on every event-loop turn
        // where the window state changed — including first-responder
        // changes. Cheap to observe, debounced before we hit SQLite.
        firstResponderObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshFocusedLeaf()
            }
        }
    }

    private func refreshFocusedLeaf() {
        guard let activeTabID = tabbed.activeTabID,
              let activeSplit = splitControllersByTabID[activeTabID] else { return }
        let newLeaf = activeSplit.focusedLeafNodeID
        let prior = focusedLeafByTabID[activeTabID]
        guard newLeaf != prior else { return }
        if let newLeaf {
            focusedLeafByTabID[activeTabID] = newLeaf
        } else {
            focusedLeafByTabID.removeValue(forKey: activeTabID)
        }
        refreshActivePaneChrome()
        scheduleFocusPersist()
    }

    private func scheduleFocusPersist() {
        pendingFocusPersist?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistAllTabs()
        }
        pendingFocusPersist = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.focusPersistDelay, execute: work)
    }

    private func restoreFocusedLeafForActiveTab() {
        guard let activeTabID = tabbed.activeTabID,
              let activeSplit = splitControllersByTabID[activeTabID],
              let focusedNodeID = focusedLeafByTabID[activeTabID] else { return }
        // Defer one runloop tick so the tab's view hierarchy is fully
        // mounted before we try to make a leaf first responder.
        DispatchQueue.main.async {
            activeSplit.makeLeafFirstResponder(nodeID: focusedNodeID)
        }
    }

    // MARK: - Footer

    /// The display path for the window's current state: the project, the tab
    /// in front, the pane the user is working in, and what that pane says is
    /// selected.
    ///
    /// `internal`, and a computed property rather than a stored string, so a
    /// test can read it without a window on screen and so there is exactly one
    /// answer to "what should the footer say" (`dry`).
    var footerStatus: String {
        let pane = activePane
        return PaneDisplayPath.format([
            project.displayName,
            activeTabTitle,
            pane?.resolvedTitle,
            pane?.selectionDescription
        ])
    }

    func refreshFooterStatus() {
        content.status = footerStatus
    }

    /// One refresh for everything that follows *which pane* is active. The
    /// footer alone refreshes far more often than this — on every selection
    /// change inside one pane — which is why the two are separate calls and
    /// not one (`separation-of-concerns`).
    func refreshActivePaneChrome() {
        refreshFooterStatus()
        refreshSearchAvailability()
    }

    /// The field means "search *this* pane": it is disabled over a pane that
    /// cannot be searched, carries that pane's placeholder, and is cleared when
    /// it changes hands. Clearing is guarded on the pane actually changing,
    /// because the active-pane notification also fires for reasons that are not
    /// a change of pane, and throwing away a half-typed query then would be a
    /// bug the user could not explain.
    private func refreshSearchAvailability() {
        guard let field = searchField else { return }
        applySearchAvailability(to: field)
    }

    /// Takes the field as a parameter rather than reading `searchField`, so the
    /// creation hook never reaches back through `toolbarDelegate` for the field
    /// it was just handed. The hook cannot in fact run before the lazy var is
    /// assigned — AppKit only asks for items through a `Delegate` that already
    /// exists — but a parameter settles the question instead of leaving a
    /// shared surface depending on the answer.
    private func applySearchAvailability(to field: NSSearchField) {
        let pane = activePane
        field.isEnabled = pane?.isSearchable ?? false
        field.placeholderString = pane?.searchPlaceholder ?? "Search"
        guard pane?.nodeID != searchTargetNodeID else { return }
        searchTargetNodeID = pane?.nodeID
        field.stringValue = ""
    }

    private var activeSplit: ComposableTabsViewController? {
        guard let activeTabID = tabbed.activeTabID else { return nil }
        return splitControllersByTabID[activeTabID]
    }

    private var activeTabTitle: String? {
        guard let activeTabID = tabbed.activeTabID else { return nil }
        return Edge.allCases
            .flatMap { tabbed.tabs(on: $0) }
            .first { $0.id == activeTabID }?
            .title
    }

    /// The pane the footer is about, in order of how directly the user said
    /// so: the one `ComposableTabsActivePane` is tracking, then the one
    /// holding the first responder, then the tab's first pane. The last is not
    /// a guess — a tab nobody has clicked in yet still has a pane on screen,
    /// and naming it is more use than naming nothing.
    private var activePane: ComposableTabsPaneViewController? {
        guard let split = activeSplit else { return nil }
        let tracked = ComposableTabsActivePane.shared.activeNodeID(in: window)
        if let nodeID = tracked ?? split.focusedLeafNodeID,
           let leaf = split.allLeaves().first(where: { $0.nodeID == nodeID }) {
            return leaf
        }
        return split.firstLeaf()
    }

    /// Every leaf reports its own selection *and* title changes to the footer.
    /// The window renders both segments, so it owns both subscriptions rather
    /// than waiting for a value somebody else happens to push
    /// (`separation-of-concerns`). Re-run whenever the tree changes, because a
    /// split makes leaves that have never been wired and the ones it replaced
    /// are gone.
    private func wirePaneObservers(on split: ComposableTabsViewController) {
        for leaf in split.allLeaves() {
            leaf.onSelectionChange = { [weak self] in self?.refreshFooterStatus() }
            leaf.onTitleChange = { [weak self] in self?.refreshFooterStatus() }
        }
    }

    // MARK: - Tab installation

    private func installInitialTabs() {
        let initial = project.initialTabs()
        // Enable edges before adding tabs so members land on live bars.
        for edge in Edge.allCases {
            tabbed.setEdgeEnabled(edge, initial.enabledEdges.contains(edge))
        }
        // Rebuild groups in stored order: group order is first-seen record
        // order, per-edge member order is record order.
        var groupIndexByID: [UUID: Int] = [:]
        for record in initial.tabs {
            let split = ComposableTabsViewController.make(
                from: record.root,
                project: project,
                isRoot: true
            )
            wireLayoutCallback(on: split, tabID: record.id)
            splitControllersByTabID[record.id] = split
            if let focusedNodeID = record.focusedNodeID {
                focusedLeafByTabID[record.id] = focusedNodeID
            }
            tabbed.addTab(.init(id: record.id, title: record.title, viewController: split), on: record.edge)
            if let index = groupIndexByID[record.groupID] {
                tabGroups[index].members[record.edge] = record.id
            } else {
                groupIndexByID[record.groupID] = tabGroups.count
                tabGroups.append(TabGroup(
                    id: record.groupID,
                    title: record.title,
                    members: [record.edge: record.id]
                ))
            }
        }
        // A project saved while an edge was disabled may lack members on a
        // now-enabled edge — restore the global-count invariant.
        var toppedUp = false
        for edge in Edge.allCases where tabbed.isEdgeEnabled(edge) {
            toppedUp = topUpTabs(on: edge) || toppedUp
        }
        // Save what the top-up made. Without this the same members are built
        // from scratch on every launch — new ids, a default layout, and a fresh
        // set of panes each time — because nothing ever wrote them down
        // (`idempotency`).
        if toppedUp { persistAllTabs() }

        if let record = initial.tabs.first(where: { $0.id == initial.activeTabID }) {
            tabbed.selectTab(id: record.id, on: record.edge)
        } else if let fallback = Edge.allCases
            .filter({ tabbed.isEdgeEnabled($0) })
            .compactMap({ edge -> (id: UUID, edge: Edge)? in
                tabbed.tabs(on: edge).first.map { (id: $0.id, edge: edge) }
            })
            .first {
            // The stored active tab is gone, or there never was one. Selecting
            // the id anyway — on `.top`, an edge that may not even be enabled —
            // leaves the window with nothing selected and no visible pane.
            tabbed.selectTab(id: fallback.id, on: fallback.edge)
        }
    }

    private func wireLayoutCallback(on split: ComposableTabsViewController, tabID: UUID) {
        split.onLayoutDidChange = { [weak self, weak split] node in
            guard let self else { return }
            // A split or a close makes leaves this window has never seen.
            if let split { self.wirePaneObservers(on: split) }
            // A removed pane must not leave a focus record behind, or
            // `installInitialTabs()` restores focus to a node that no
            // longer exists on the next launch.
            var focusWasCleared = false
            if let focused = self.focusedLeafByTabID[tabID],
               !Self.leafIDs(in: node).contains(focused) {
                self.focusedLeafByTabID[tabID] = nil
                focusWasCleared = true
            }
            self.persistAllTabs()
            // Losing the focus record is a change of *pane*: `activePane` falls
            // through to the split's first leaf, so the field's target moved
            // without the tab moving and the whole chrome has to recompute.
            // Every other reason this callback fires — a divider drag above
            // all, which arrives on every frame — moved no pane, and must not
            // pay for a search refresh.
            if focusWasCleared {
                self.refreshActivePaneChrome()
            } else {
                self.refreshFooterStatus()
            }
        }
        wirePaneObservers(on: split)
    }

    private static func leafIDs(in node: LayoutNode) -> Set<UUID> {
        switch node.kind {
        case .leaf:
            return [node.id]
        case .split(_, let first, let second):
            return leafIDs(in: first).union(leafIDs(in: second))
        }
    }

    /// Snapshots every tab's split tree (on every edge, enabled or not)
    /// and writes the full set back to the project. Called whenever the
    /// user touches the layout (split, close, tab add/remove/reorder/
    /// select, edge toggle).
    private func persistAllTabs() {
        var records: [TabRecord] = []
        for edge in Edge.allCases {
            for tab in tabbed.tabs(on: edge) {
                guard let split = splitControllersByTabID[tab.id] else { continue }
                let groupID = tabGroups.first(where: { $0.members[edge] == tab.id })?.id
                records.append(TabRecord(
                    id: tab.id,
                    groupID: groupID,
                    edge: edge,
                    title: tab.title,
                    root: split.snapshotNode(),
                    focusedNodeID: focusedLeafByTabID[tab.id]
                ))
            }
        }
        project.persistTabs(
            records,
            activeTabID: tabbed.activeTabID,
            enabledEdges: Edge.allCases.filter { tabbed.isEdgeEnabled($0) }
        )
    }

    // MARK: - Help drawer

    /// What the `?` shows. Static because it is the same for every project: a
    /// description of the window, not of the repository in it.
    public static let helpContent = HelpContent(topics: [
        HelpContent.Topic(
            title: "Panes",
            body: """
                Each pane has its own title bar. The controls on the left close, \
                minimize and zoom it; the gear on the right holds options for \
                that pane, including how much space it leaves around its \
                contents.
                """),
        HelpContent.Topic(
            title: "Minimizing",
            body: """
                Minimizing a pane sends it to one edge of the split it lives in, \
                and the pane beside it takes the space. Left and right leave a \
                narrow strip of icons; top and bottom leave the title bar. Click \
                the strip to bring the pane back.
                """),
        HelpContent.Topic(
            title: "Zoom",
            body: """
                A zoomed pane fills its whole tab. The other panes are still \
                there — zoom it again to put them back.
                """),
        HelpContent.Topic(
            title: "Search",
            body: """
                The search field searches the pane you are in. It is disabled \
                over a pane that has nothing to search, and it clears when you \
                move to another pane.
                """),
        HelpContent.Topic(
            title: "The status bar",
            body: """
                The bar along the bottom names where you are: the project, the \
                tab, the pane, and what is selected inside it.
                """)
    ])

    /// Shows or hides the help drawer. `@objc` so the toolbar's `?` can name
    /// it; no `sender` parameter, because AppKit is happy to send an action to
    /// a zero-argument selector and the drawer does not care who asked.
    ///
    /// Warning-free — and so nameable from a `#selector` — because it goes
    /// through `HelpPresenting` rather than through `WindowDrawer`.
    @objc public func toggleHelp() {
        helpPresenter?.toggleHelp()
    }

    /// Whether the help drawer is disclosed. `false` before the window has
    /// loaded, when there is no drawer to disclose.
    public var isHelpVisible: Bool { helpPresenter?.isHelpVisible ?? false }

    /// The drawer itself, for the tests and the UI suite; `nil` until the
    /// window has loaded, because a drawer needs a real window to hang off.
    ///
    /// Deprecated because `WindowDrawer` is, and naming one is only
    /// warning-free from inside a declaration carrying the same quarantine.
    /// This is the only place the window names it: everything the window
    /// actually *does* with help goes through `HelpPresenting` above, which is
    /// what keeps the annotation off `toggleHelp()` and its `#selector`.
    @available(macOS, deprecated: 10.13)
    public var helpDrawer: WindowDrawer? {
        (helpPresenter as? ProjectHelpDrawerController)?.drawer
    }

    /// Filled while open, outlined while closed — the same glyph behaviour the
    /// settings window's help button has, from the same helper. Driven from
    /// `onVisibilityChange` and from `showWindow(_:)` rather than only from the
    /// click, because the drawer also re-asserts itself when the window becomes
    /// key, and because a custom-view toolbar item does not exist until AppKit
    /// has asked the delegate for it.
    private func refreshHelpButtonAppearance() {
        guard let button = toolbarDelegate.button(for: .projectHelp) else { return }
        WindowToolbarBuilder.applyDisclosureAppearance(
            to: button,
            disclosed: isHelpVisible,
            outlineSymbol: "questionmark.circle",
            filledSymbol: "questionmark.circle.fill",
            showTooltip: "Show Help",
            hideTooltip: "Hide Help")
    }

}

// MARK: - MultiTabbedViewControllerDelegate

extension ComposableTabsWindowController: MultiTabbedViewControllerDelegate {

    public func multiTabbedViewControllerNeedsNewTab(_ controller: MultiTabbedViewController) {
        addTabGroup()
    }

    public func multiTabbedViewController(
        _ controller: MultiTabbedViewController,
        didSelectTab id: UUID,
        on edge: Edge
    ) {
        restoreFocusedLeafForActiveTab()
        persistAllTabs()
        refreshActivePaneChrome()
    }

    /// Deliberately one line. This fires during `installInitialTabs()` and
    /// mid-`addTabGroup()`, where a `persistAllTabs()` would write a half-built
    /// tab set. A pure recompute is safe there. The heavier duties stay on
    /// `didSelectTab` because they answer a different question — the user
    /// picked this tab — and not "which pane is in front now", which is all
    /// this callback claims to report.
    public func multiTabbedViewController(
        _ controller: MultiTabbedViewController,
        activeTabDidChange id: UUID,
        on edge: Edge
    ) {
        refreshActivePaneChrome()
    }

    public func multiTabbedViewController(
        _ controller: MultiTabbedViewController,
        didRequestCloseTab id: UUID,
        on edge: Edge
    ) {
        // Closing any member closes its whole group. Refuse to close the
        // last group (mirrors Safari/Terminal keeping one tab).
        guard let groupIndex = tabGroups.firstIndex(where: { $0.members.values.contains(id) }) else { return }
        guard tabGroups.count > 1 else { return }
        let group = tabGroups.remove(at: groupIndex)
        // Remove the clicked member first: if it is active, the controller
        // activates its neighbor on the same edge before the rest of the
        // group disappears.
        let ordered = [id] + group.members.values.filter { $0 != id }
        for memberID in ordered {
            controller.removeTab(id: memberID)
            splitControllersByTabID.removeValue(forKey: memberID)
            focusedLeafByTabID.removeValue(forKey: memberID)
        }
        persistAllTabs()
        // The neighbour's `activeTabDidChange` already fired — but *inside* the
        // loop above, before `splitControllersByTabID` was pruned, so it
        // recomputed against panes that were still on the books. This tail is
        // the only refresh that sees settled state. And when the last member
        // leaves an edge with no fallback, `setActiveTab(nil)` names no tab and
        // fires nothing at all, so this is the only refresh there is.
        refreshActivePaneChrome()
    }

    public func multiTabbedViewController(
        _ controller: MultiTabbedViewController,
        didReorderTab id: UUID,
        to index: Int,
        on edge: Edge
    ) {
        persistAllTabs()
    }
}

// MARK: - NSSearchFieldDelegate

extension ComposableTabsWindowController: NSSearchFieldDelegate {

    /// Live search: every keystroke goes to the pane. A pane that cannot be
    /// searched cannot receive one either — the field is disabled — so there is
    /// no capability check here beyond the one `PaneViewController.search(for:)`
    /// already makes.
    public func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField, field === searchField else { return }
        // The pane the field is *advertising* — the one whose placeholder is
        // showing and whose enablement was computed — not whatever is active
        // this instant. If the two ever disagree the keystroke belongs to
        // neither, and silently sending it to the newcomer is the bug the
        // clear-on-change rule exists to prevent (`dry`).
        guard let nodeID = searchTargetNodeID,
              let pane = activeSplit?.allLeaves().first(where: { $0.nodeID == nodeID })
        else { return }
        pane.search(for: field.stringValue)
    }
}

// MARK: - The help drawer

/// The project window's help drawer, and the per-repository preference that
/// remembers whether it was open, on which tab, and how wide.
///
/// The sibling of `ComposableSettings.HelpDrawerController`: same drawer, same
/// single Help tab, different place to remember it. `WindowDrawer` remembers
/// nothing on purpose — "Settings remembers its drawer in `UserSettings`; the
/// project window remembers its own per repository. A preference belongs to
/// whoever the preference is about." There is one settings window but one
/// project window *per project*, and they disagree, so this one writes to the
/// project's own settings bag rather than to `UserSettings`.
///
/// **Why this is a type of its own** rather than a conformance on
/// `ComposableTabsWindowController`: `HelpPresenting` is what keeps `NSDrawer`'s
/// deprecation off the chrome that asks for help. Its requirements carry no
/// annotation, so a window holding `any HelpPresenting` can name a toolbar
/// action in a `#selector`, restyle a glyph and read `isHelpVisible` without a
/// single warning, while everything that actually touches `WindowDrawer` stays
/// behind the quarantine below. Folded into the window controller instead, the
/// quarantine lands on `toggleHelp()` — and this project treats warnings as
/// errors, so a `#selector` naming it stops the build.
///
/// In this file rather than its own, because a new file in a shared tier is a
/// decision the placement guard makes the human take, and this presenter is one
/// window's — nothing else refers to it.
@available(macOS, deprecated: 10.13, message: "Wraps NSDrawer, deprecated since macOS 10.13")
@MainActor
final class ProjectHelpDrawerController: NSObject, HelpPresenting {

    private static let helpTabID = "help"

    private let project: ProjectWorkspace
    private let helpView = HelpContentView()

    /// The drawer itself, for the identifiers on it and the width read back off
    /// it. The window reaches everything else through `HelpPresenting`.
    let drawer: WindowDrawer

    var onVisibilityChange: (() -> Void)?

    /// Unused: a drawer comes out of the window's edge, not out of a button.
    /// `HelpPresenting` still requires it, because the popover presenter does
    /// need somewhere to hang its help from.
    var helpAnchorView: NSView?

    /// The remembered preference, not `drawer.isOpen`. The drawer is open
    /// because the reader asked for it to be open, and for no other reason —
    /// and AppKit silently drops an `open()` on a window that is not on screen
    /// yet, which is exactly the moment a restored window asks. Answering from
    /// the preference makes the button and its glyph right immediately;
    /// `reapplyVisibility` is what makes the drawer itself catch up.
    var isHelpVisible: Bool {
        self.project.setting(ProjectWindowSetting.drawerOpen) == "1"
    }

    init(parentWindow: NSWindow, project: ProjectWorkspace) {
        self.project = project
        let helpView = self.helpView
        self.drawer = WindowDrawer(
            parentWindow: parentWindow,
            accessibilityPrefix: "project.drawer",
            tabs: [
                DrawerTab(
                    id: Self.helpTabID,
                    title: "Help",
                    symbolName: "questionmark.circle",
                    makeView: { helpView })
            ],
            contentWidth: Self.rememberedWidth(of: project))
        super.init()

        // What the drawer re-asserts when the window finally appears, so a
        // remembered-open drawer opens on launch rather than on the second try.
        self.drawer.reapplyVisibility = { [weak self] in
            self?.applyVisibility()
        }
        // The drawer announces opening and closing, never resizing, so a width
        // the user dragged is read back at the last moment it can still matter:
        // the one that ends the session with it. Registered by selector rather
        // than by block so the observation is zeroing-weak and needs no
        // `deinit` to undo — the same reason `WindowDrawer` watches its parent
        // window that way.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.parentWindowWillClose),
            name: NSWindow.willCloseNotification,
            object: parentWindow)

        self.applyVisibility()
    }

    // MARK: - HelpPresenting

    func setHelp(_ content: HelpContent?) {
        self.helpView.setHelp(content)
    }

    func toggleHelp() {
        // `nil` deletes the row, so "never opened it" and "closed it again" are
        // one state rather than two that have to be kept agreeing.
        self.project.setSetting(
            ProjectWindowSetting.drawerOpen, to: self.isHelpVisible ? nil : "1")
        self.applyVisibility()
    }

    // MARK: - What the project remembers

    private func applyVisibility() {
        if self.isHelpVisible {
            // The remembered tab, so a second tab later needs no change here.
            // An id naming no tab is ignored by the drawer, which is the right
            // answer for a preference written by some other build.
            self.drawer.open(
                selecting: self.project.setting(ProjectWindowSetting.drawerTab) ?? Self.helpTabID)
        } else {
            self.drawer.close()
        }
        self.onVisibilityChange?()
    }

    /// The remembered width, or the default. A value that is not a number is
    /// treated as no value: nonsense in the database is not a reason to hand
    /// the user a drawer they cannot drag back.
    ///
    /// `static` because the drawer is built with it, before there is a `self`
    /// to ask.
    private static func rememberedWidth(of project: ProjectWorkspace) -> CGFloat {
        guard let raw = project.setting(ProjectWindowSetting.drawerWidth),
              let width = Double(raw) else { return WindowDrawer.defaultContentWidth }
        return CGFloat(width)
    }

    @objc private func parentWindowWillClose() {
        self.project.setSetting(ProjectWindowSetting.drawerTab, to: self.drawer.selectedTabID)
        self.project.setSetting(
            ProjectWindowSetting.drawerWidth, to: String(Double(self.drawer.contentWidth)))
    }
}
