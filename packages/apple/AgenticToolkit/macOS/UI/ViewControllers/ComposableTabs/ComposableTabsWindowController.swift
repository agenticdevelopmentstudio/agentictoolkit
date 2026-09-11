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
        /// Shared by every member tab in the group — see
        /// `ComposableTabsViewController.workingDirectory`.
        let workingDirectory: URL
    }

    public let project: ProjectWorkspace
    private let tabbed: MultiTabbedViewController

    /// Supplies what each tab shows in the edge bar. The project controller
    /// (a later task) sets this; a window with none falls back to a plain
    /// title button — see `tabItem(for:on:)`.
    public weak var tabItemDataSource: ComposableTabsTabItemDataSource?

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

    /// The same object as `helpPresenter`, at the type that has a drawer on it.
    ///
    /// Two references rather than a downcast: the window builds the presenter
    /// itself and knows the concrete type at that moment, so `helpDrawer` can
    /// say what it means instead of asking `as?` a question that would answer
    /// `nil` — silently, and wrongly — if a second `HelpPresenting` were ever
    /// installed here. The existential still earns its keep: everything the
    /// window *does* with help goes through it, which is what keeps the
    /// deprecation off `toggleHelp()` and its `#selector`.
    @available(macOS, deprecated: 10.13)
    private var projectHelpDrawer: ProjectHelpDrawerController?

    /// The pane the search field is currently pointed at, so a redundant
    /// refresh does not throw away what the user has typed.
    private var searchTargetNodeID: UUID?

    /// The strip across the bottom. Public because the UI suite and the
    /// scripting bridge both address it, and neither should have to know it
    /// arrived by composition.
    public var footer: WindowFooterBar { content.footer }

    /// Project-level tabs, in creation order.
    private var tabGroups: [TabGroup] = []

    /// Set for the duration of `reloadTabs()`'s removal loop. `removeTab`
    /// fires `didSelectTab` for whichever member it activates next, and none
    /// of that callback's duties are meaningful mid-loop: `persistAllTabs()`
    /// would write the shrinking tab set the loop hasn't finished removing,
    /// overwriting the stored tabs `installInitialTabs()` is about to read
    /// back; `restoreFocusedLeafForActiveTab()` would schedule a first
    /// responder on a split controller the loop discards two statements
    /// later; and `refreshActivePaneChrome()` would recompute against tabs
    /// that are half gone. So the callback is suppressed wholesale, and
    /// `persistAllTabs()` checks the flag again for the paths that reach it
    /// by other routes.
    private var isReloadingTabs = false

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

    /// Latched by `windowWillClose(_:)`. A window on its way out still lays
    /// out — the split views settle, their debounced thickness persist fires,
    /// and the responder chain comes apart — and each of those reaches
    /// `persistAllTabs()`, which would write the dying window's tab set over
    /// whatever the project has written since. Nothing of value is lost by
    /// refusing, with one deliberate exception. Every *structural* change —
    /// split, close, add, remove, reorder, select, edge toggle — is written
    /// synchronously as it happens, by `persistTreeToDocument()`. Only two
    /// writers are debounced: divider thicknesses (300 ms) and the focused
    /// leaf (250 ms). So releasing a divider drag, or moving focus, within
    /// that window of closing the window drops that one write. That trade is
    /// intended: a tab set written over by a dead window is corruption, and a
    /// divider position is a preference.
    ///
    /// Deliberately one-way, and deliberately not `isReloadingTabs`: that flag
    /// is raised and lowered around one loop precisely so the top-up persist in
    /// `installInitialTabs()` still runs. This one never comes down, because
    /// the window never comes back.
    private var isClosing = false

    private var titlebarAccessory: NSTitlebarAccessoryViewController?
    private var arrangeButton: NSButton?
    private var cancellables = Set<AnyCancellable>()

    /// Keeps the room around the panes following the setting while the window
    /// is open, so the Spacing panel previews on the window behind its sheet.
    private var spacingObservers: [UserSettingObserver<Int>] = []

    /// Keeps the plane behind the panes following the theme.
    private var backdropObserver: ThemePaletteObserver?

    /// Keeps the `?` glyph following the theme. Made when the toolbar has
    /// actually built the button, and re-made whenever it builds a new one —
    /// see `refreshHelpButtonAppearance()`.
    private var helpThemeObserver: ThemePaletteObserver?

    /// The button `helpThemeObserver` is hosted on, which is whichever one the
    /// toolbar delegate last built. Weak because the delegate owns its buttons;
    /// a rebuilt toolbar simply leaves this `nil` until the next refresh.
    private weak var helpButton: NSButton?

    /// - Parameter tabItemDataSource: Assigned **before** the initial tabs are
    ///   installed, which is the only moment it can matter: `installInitialTabs()`
    ///   runs inside this initializer, and a data source set afterwards arrives
    ///   too late to be asked for a single tab item — every tab falls back to
    ///   `.title(record.title)` and the whole tree has to be thrown away and
    ///   rebuilt to correct it. Defaulted, because a window with no project
    ///   controller behind it (every layout test, the demo app) genuinely has
    ///   none.
    public init(project: ProjectWorkspace, tabItemDataSource: ComposableTabsTabItemDataSource? = nil) {
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
        Self.applyPaneSpacing(PaneSpacing.contentInsets, to: tabbed)
        backdropObserver = ThemePaletteObserver(host: tabbed.view) { [weak self] palette in
            self?.tabbed.centerBackgroundColor = NSColor(palette.projectPaneBackdrop)
            self?.tabbed.centerOutlineColor = NSColor(palette.projectPaneOutline)
        }
        spacingObservers = PaneSpacing.edgeSettings.values.map { setting in
            UserSettingObserver(setting) { [weak self] _ in
                guard let tabbed = self?.tabbed else { return }
                Self.applyPaneSpacing(PaneSpacing.contentInsets, to: tabbed)
            }
        }
        self.tabItemDataSource = tabItemDataSource
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

    /// Hands the window's spacing to the tabs: the room around the panes, and
    /// where a side bar's first tab begins.
    ///
    /// Both come from the same insets, so they are applied together — a top
    /// spacing that moved the panes down without moving the tabs with them
    /// would break the alignment the tab is there to show.
    /// `MultiTabbedViewController` is generic and knows nothing about pane
    /// chrome, so the arithmetic belongs here, where the spacing and the
    /// pane's own title bar are both in view.
    static func applyPaneSpacing(_ insets: NSEdgeInsets, to tabbed: MultiTabbedViewController) {
        tabbed.contentInsets = insets
        let firstTabTop = insets.top + ComposableTabsPaneViewController.titleBarBottom
        tabbed.setTabStartInset(firstTabTop, for: .left)
        tabbed.setTabStartInset(firstTabTop, for: .right)
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
        projectHelpDrawer = presenter
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
            let split = makeSplitController(for: id, workingDirectory: group.workingDirectory)
            let record = TabRecord(
                id: id,
                groupID: group.id,
                edge: edge,
                title: group.title,
                root: split.snapshotNode(),
                workingDirectory: storedWorkingDirectory(group.workingDirectory)
            )
            let tab = MultiTabbedViewController.Tab(
                id: id, groupID: group.id, item: tabItem(for: record, on: edge), viewController: split)
            tabbed.insertTab(tab, at: index, on: edge)
            tabGroups[index].members[edge] = id
            created = true
        }
        return created
    }

    /// Creates a project-level tab: one member per enabled edge, all
    /// sharing a title, and activates the first member.
    private func addTabGroup() {
        let title = "Tab \(tabGroups.count + 1)"
        var group = TabGroup(
            id: UUID(), title: title, members: [:], workingDirectory: project.directoryURL)
        for edge in Edge.allCases where tabbed.isEdgeEnabled(edge) {
            let id = UUID()
            let split = makeSplitController(for: id, workingDirectory: project.directoryURL)
            let record = TabRecord(
                id: id,
                groupID: group.id,
                edge: edge,
                title: title,
                root: split.snapshotNode(),
                workingDirectory: storedWorkingDirectory(group.workingDirectory)
            )
            tabbed.addTab(
                .init(id: id, groupID: group.id, item: tabItem(for: record, on: edge), viewController: split),
                on: edge)
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

    /// What `record` should show in the edge bar. Falls back to a plain title
    /// button when no data source is set — the window controller still works,
    /// on its own, exactly as it always has.
    private func tabItem(for record: TabRecord, on edge: Edge) -> TabItem {
        tabItemDataSource?.composableTabsWindowController(self, tabItemFor: record, on: edge) ?? .title(record.title)
    }

    /// The `TabItem` actually installed for every tab on `edge`, right now.
    /// Internal, not `private`, and reached only through `@testable import` —
    /// a test needs to tell a hosted pane (`.viewController`) apart from a
    /// plain title button (`.title`), which `scriptingTabs(branch:)` cannot
    /// answer: it reports a group's stored title regardless of which case
    /// installed it.
    func tabItems(on edge: Edge) -> [TabItem] {
        tabbed.tabs(on: edge).map(\.item)
    }

    private func makeSplitController(
        for tabID: UUID, workingDirectory: URL
    ) -> ComposableTabsViewController {
        let split = ComposableTabsViewController.make(
            from: project.layout.blueprint(),
            project: project,
            workingDirectory: workingDirectory,
            isRoot: true
        )
        wireLayoutCallback(on: split, tabID: tabID)
        splitControllersByTabID[tabID] = split
        return split
    }

    // MARK: - Scripting accessors

    /// One project-level tab, the way a reader sees it and therefore the way a
    /// script does: the *group*, not the member tabs it happens to be drawn as.
    ///
    /// A window with two edges enabled draws "Tab 1" on both bars, and vending
    /// the members would show a script two tabs of that name where there is
    /// one. Its members are listed too, because everything that enumerates
    /// panes has to go through them.
    ///
    /// A value type, made fresh on each read: it is a copy of what `TabGroup`
    /// already holds, and a cached one would be a second thing to invalidate
    /// every time a tab is renamed or an edge is toggled.
    public struct ScriptingTab {

        /// The persisted `project_tabs.group_id`.
        public let id: UUID
        public let title: String

        /// The group's member tabs on edges that are *enabled*, in
        /// `Edge.allCases` order. Disabling an edge keeps its members so that
        /// re-enabling restores them, but neither the tab bar nor its panes are
        /// on screen — so neither is in here.
        public let members: [(edge: Edge, tabID: UUID)]

        public var edges: [Edge] { self.members.map(\.edge) }
    }

    /// This window's project-level tabs, in creation order.
    public var scriptingTabGroups: [ScriptingTab] {
        tabGroups.map { group in
            ScriptingTab(
                id: group.id,
                title: liveGroupTitle(for: group),
                members: Edge.allCases.compactMap { edge in
                    guard tabbed.isEdgeEnabled(edge), let id = group.members[edge] else { return nil }
                    return (edge: edge, tabID: id)
                })
        }
    }

    /// A group's title the way a reader sees it, not the stored default it
    /// was created with: a data source can host a richer item whose own
    /// title changes independently (e.g. a pane's `title` following its
    /// session). Falls back to the stored `group.title` when the group has
    /// no installed member — which cannot happen for a real tab, but keeps
    /// this total rather than force-unwrapping a lookup.
    private func liveGroupTitle(for group: TabGroup) -> String {
        for edge in Edge.allCases {
            guard let id = group.members[edge],
                  let tab = tabbed.tabs(on: edge).first(where: { $0.id == id }),
                  // A hosted item whose view controller has no `title` reports
                  // `""`, which is not a name a script should read as the
                  // tab's. Treat it the same as no installed member.
                  !tab.title.isEmpty else { continue }
            return tab.title
        }
        return group.title
    }

    /// Storage's convention for a tab's working directory: `nil` means the
    /// project's own directory (see `TabRecord.workingDirectory`). Records
    /// built for a freshly created tab must follow it too, or a data source
    /// sees the same tab two different ways depending on whether it was just
    /// created or restored from storage. Resolved, not standardized, for the
    /// reason `ProjectCheckout.init` resolves.
    private func storedWorkingDirectory(_ directory: URL) -> URL? {
        directory.resolvingSymlinksInPath() == project.directoryURL.resolvingSymlinksInPath()
            ? nil
            : directory
    }

    /// This window's tabs, as scripting values. `branch` resolves a working
    /// directory to a branch name — `ProjectWindowManager+Scripting.swift`
    /// supplies the real lookup, through the project's `ProjectController`
    /// and its per-checkout `BranchController`; a caller with no such
    /// controller (or a directory that is not a checkout) passes `{ _ in
    /// nil }`, which `ScriptableProjectTab` reports as an empty string.
    public func scriptingTabs(branch: (URL) -> String?) -> [ScriptableProjectTab] {
        scriptingTabGroups.map { group in
            let directory = tabGroups.first { $0.id == group.id }?.workingDirectory ?? project.directoryURL
            return ScriptableProjectTab(
                id: group.id,
                title: group.title,
                edges: group.edges.map(\.rawValue),
                project: project.displayName,
                workingDirectory: directory.path,
                branch: branch(directory) ?? ""
            )
        }
    }

    /// Every pane in this window, on every tab and every enabled edge.
    ///
    /// Order is by tab, then by edge, then by the split tree's own leaf order,
    /// so a script that reads `panes` twice in a row gets the same order twice.
    public func allPanes() -> [ComposableTabsPaneViewController] {
        scriptingTabGroups.flatMap { self.leaves(of: $0) }
    }

    /// The panes in one project tab, by the tab's scripting id.
    public func panes(inTab identifier: String) -> [ComposableTabsPaneViewController] {
        guard let id = UUID(uuidString: identifier),
              let group = scriptingTabGroups.first(where: { $0.id == id }) else { return [] }
        return leaves(of: group)
    }

    /// The project tab a pane is on, or `nil` for a pane this window does not
    /// have.
    ///
    /// Here rather than derived from `panes(inTab:)` by the caller: that route
    /// rebuilds `scriptingTabGroups` once per tab and walks every leaf again
    /// each time, which is a quadratic answer to a question that is one pass —
    /// build the groups once, stop at the group that holds the pane.
    public func tabGroup(containing pane: ComposableTabsPaneViewController) -> ScriptingTab? {
        scriptingTabGroups.first { group in
            leaves(of: group).contains { $0 === pane }
        }
    }

    private func leaves(of group: ScriptingTab) -> [ComposableTabsPaneViewController] {
        group.members.compactMap { splitControllersByTabID[$0.tabID] }.flatMap { $0.allLeaves() }
    }

    /// The titlebar search field's contents. Setting it searches, rather than
    /// only filling the field in — a script that sets a query and then reads
    /// the pane back would otherwise see a field that says one thing and a
    /// pane that shows another.
    ///
    /// Inert until the toolbar has built the field: before that `searchField`
    /// is `nil` and `searchTargetNodeID` has never been assigned — only the
    /// field-creation hook assigns it — so there is nothing to fill in and
    /// nothing to route to. That is a window that has not been on screen yet,
    /// which is not a window the scripting surface can name: `project window`
    /// enumerates the manager's open controllers, every one of which has been
    /// shown.
    public var searchQuery: String {
        get { searchField?.stringValue ?? "" }
        set {
            searchField?.stringValue = newValue
            routeSearch(newValue)
        }
    }

    /// The active project tab's id as a string, and the setter that selects
    /// one. The *group's* id, not the member's: that is what `project tab`
    /// means, and it is what a script was handed when it read the tab.
    public var selectedTabIdentifier: String {
        get {
            guard let activeTabID = tabbed.activeTabID else { return "" }
            return tabGroups.first { $0.members.values.contains(activeTabID) }?.id.uuidString ?? ""
        }
        set { if let id = UUID(uuidString: newValue) { selectTab(id: id) } }
    }

    /// Selects a project tab, on the first enabled edge it has a member on. An
    /// id that names no tab is ignored — a window with no selected tab is not a
    /// state this window has, and it is a worse answer to a typo than doing
    /// nothing.
    ///
    /// A script picking a tab means what a click on it means, so it takes the
    /// same tail: the tab is remembered, and the pane that was in front when
    /// the tab was last left comes back. `tabbed.selectTab` alone reports only
    /// `activeTabDidChange`, which deliberately does neither.
    public func selectTab(id: UUID) {
        guard let group = tabGroups.first(where: { $0.id == id }) else { return }
        for edge in Edge.allCases where tabbed.isEdgeEnabled(edge) {
            if let memberID = group.members[edge] {
                guard tabbed.activeTabID != memberID else { return }
                tabbed.selectTab(id: memberID, on: edge)
                tabWasActivated()
                return
            }
        }
    }

    /// The drawer, as a setting rather than a toggle — a script says what it
    /// wants, and saying it twice means the same as saying it once
    /// (`idempotency`).
    ///
    /// Warning-free, and so callable from a wrapper that carries no
    /// quarantine, because it goes through `HelpPresenting` like everything
    /// else the window does with help.
    public func setHelpVisible(_ visible: Bool) {
        guard visible != isHelpVisible else { return }
        toggleHelp()
    }

    /// Which drawer tab is showing; `nil` before the window has loaded.
    ///
    /// Through the presenter rather than through `helpDrawer`, for the reason
    /// `toggleHelp()` is: `String?` names no deprecated type, so nothing on
    /// this path — and nothing that reads it — has to carry the quarantine.
    public var helpDrawerTabID: String? { helpPresenter?.helpTabID }

    // MARK: - Tab-edge accessors (used by Cocoa Scripting bridges)

    /// Names of the tab edges currently enabled in this window. Names are
    /// lowercase: `"top"`, `"right"`, `"bottom"`, `"left"`. Order matches
    /// `Edge.allCases`.
    public var enabledTabEdgeNames: [String] {
        get { Edge.allCases.filter { tabbed.isEdgeEnabled($0) }.map(\.rawValue) }
        set {
            let normalized = Set(newValue.map { $0.lowercased() })
            // Enables first, then disables. `setEdgeEnabled` refuses to turn
            // off the last enabled edge — a window with no tab bar anywhere
            // has nowhere to put a tab — and that rule is stated per call, so
            // in `Edge.allCases` order it also refuses perfectly legal
            // *sets*: assigning `["bottom"]` to a window enabled only at the
            // top asks to disable top before bottom exists, the refusal
            // stands, and the window is left with both. Doing every enable
            // before any disable means the last-edge rule is only ever reached
            // by an assignment that genuinely names no edge at all.
            for edge in Edge.allCases where normalized.contains(edge.rawValue) {
                setEdgeEnabled(edge, true)
            }
            for edge in Edge.allCases where !normalized.contains(edge.rawValue) {
                setEdgeEnabled(edge, false)
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

    /// Drops a debounced focus-persist that has not fired yet.
    ///
    /// There are two writers of a project's tab rows — this window and the
    /// project controller's reconcile — and `saveTabs` is a full
    /// delete-then-insert, so the later write simply wins. The 250 ms delay on
    /// this one is long enough to land *after* reconcile has written, and what
    /// it would write is the window's live tab set: on a first open, the single
    /// placeholder tab, which then replaces the freshly reconciled worktree
    /// tabs outright.
    ///
    /// So reconcile calls this immediately before it writes. Only the pending
    /// item is cancelled — not persisting in general — because the write that
    /// follows is *also* ours, and `reloadTabs()` runs in the same main-actor
    /// turn as it, leaving no window for a new one to be armed in. The focus
    /// record the cancelled item was carrying is re-derived from the rebuilt
    /// tabs; it is a first-responder position, not user data.
    public func cancelPendingTabPersist() {
        pendingFocusPersist?.cancel()
        pendingFocusPersist = nil
    }

    /// A closing window stops writing the project's tab rows.
    ///
    /// All three halves are needed. The pending focus-persist is dropped; the
    /// observer that arms it goes too, because a close tears the responder
    /// chain apart and every step of that posts `didUpdateNotification`, which
    /// would arm a fresh one straight after the cancel; and `isClosing` catches
    /// the writer neither of those covers — the splits' own debounced thickness
    /// persist, armed by the layout a close provokes and reaching
    /// `persistAllTabs()` through `onLayoutDidChange`.
    ///
    /// It usually went unnoticed because `ProjectWindowManager` drops its last
    /// reference to the controller in the same turn, leaving the work items'
    /// `weak self` nil by the time they run. "Usually deallocated first" is not
    /// a life cycle, and anything that holds the controller a moment longer —
    /// a script, a test — got the write.
    ///
    /// Closing the window also discards every pane in it, which is the third
    /// whole-tree discard alongside `removeAllTabs()` and `didRequestCloseTab`
    /// — and the one that was missing. Neither of the other two runs on this
    /// path, no leaf defines a `deinit`, and `paneWillBeRemoved()` is what
    /// reaches `TerminalSessionContentViewController`'s `terminateAll()` and
    /// `FileBrowserViewController.stopWatching()`. Close a project window with
    /// three terminals open and, without this, three shells kept running with
    /// their file watchers still firing for the rest of the app's life.
    ///
    /// After `isClosing` is raised, so the tear-down cannot provoke a layout
    /// callback that writes the emptied tab set over the project's saved tabs.
    public override func windowWillClose(_ notification: Notification) {
        super.windowWillClose(notification)
        isClosing = true
        cancelPendingTabPersist()
        if let firstResponderObserver {
            NotificationCenter.default.removeObserver(firstResponderObserver)
            self.firstResponderObserver = nil
        }
        for split in splitControllersByTabID.values {
            tearDown(split: split)
        }
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

    /// Hands a query to the pane the field is *advertising* — the one whose
    /// placeholder is showing and whose enablement was computed — not whatever
    /// is active this instant. If the two ever disagree the keystroke belongs
    /// to neither, and silently sending it to the newcomer is the bug the
    /// clear-on-change rule exists to prevent.
    ///
    /// One method for both callers, so a script setting `search query` reaches
    /// exactly the pane a keystroke would (`dry`).
    private func routeSearch(_ query: String) {
        guard let nodeID = searchTargetNodeID,
              let pane = activeSplit?.allLeaves().first(where: { $0.nodeID == nodeID })
        else { return }
        pane.search(for: query)
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
            let directory = record.workingDirectory ?? project.directoryURL
            let split = ComposableTabsViewController.make(
                from: record.root,
                project: project,
                workingDirectory: directory,
                isRoot: true
            )
            wireLayoutCallback(on: split, tabID: record.id)
            splitControllersByTabID[record.id] = split
            if let focusedNodeID = record.focusedNodeID {
                focusedLeafByTabID[record.id] = focusedNodeID
            }
            let tab = MultiTabbedViewController.Tab(
                id: record.id,
                groupID: record.groupID,
                item: tabItem(for: record, on: record.edge),
                viewController: split)
            tabbed.addTab(tab, on: record.edge)
            if let index = groupIndexByID[record.groupID] {
                tabGroups[index].members[record.edge] = record.id
            } else {
                groupIndexByID[record.groupID] = tabGroups.count
                tabGroups.append(TabGroup(
                    id: record.groupID,
                    title: record.title,
                    members: [record.edge: record.id],
                    workingDirectory: directory
                ))
            }
        }
        // A project saved while an edge was disabled may lack members on a
        // now-enabled edge — restore the global-count invariant.
        var toppedUp = false
        for edge in Edge.allCases where tabbed.isEdgeEnabled(edge) {
            toppedUp = topUpTabs(on: edge) || toppedUp
        }
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

        // Save what the top-up made. Without this the same members are built
        // from scratch on every launch — new ids, a default layout, and a fresh
        // set of panes each time — because nothing ever wrote them down
        // (`idempotency`).
        //
        // *After* the restore above, never before it. `persistAllTabs()` writes
        // whichever tab is active at the moment it runs, and until the restore
        // has run that is whatever the first `insertTab` happened to auto-select
        // — so a top-up that wrote first would overwrite the remembered
        // selection with the first tab of the first enabled edge, and the
        // restore that followed would put the right tab on screen without ever
        // writing it down. The window looked correct and the *next* launch
        // opened on the wrong tab.
        if toppedUp { persistAllTabs() }
    }

    /// Tears down every tab and re-installs from the workspace's stored tabs.
    ///
    /// The project controller calls this when — and only when — a reconcile
    /// actually wrote different tabs. It is not a cheap refresh: every pane in
    /// the window is discarded and rebuilt, which for the app's default
    /// blueprint means killing a shell per tab and spawning a new one, so
    /// calling it on a reconcile that changed nothing is pure loss.
    public func reloadTabs() {
        removeAllTabs()
        tabGroups.removeAll()
        splitControllersByTabID.removeAll()
        focusedLeafByTabID.removeAll()
        installInitialTabs()
        refreshActivePaneChrome()
    }

    /// Re-asks the data source what each tab's bar item should be, and swaps
    /// in the answer. The panes are untouched.
    ///
    /// This is the cheap counterpart to `reloadTabs()`, and it exists because
    /// the two things a tab is made of become available at different times.
    /// A window installs its tabs from storage the moment it opens; the data
    /// source's answer for a tab depends on a checkout scan that runs git and
    /// therefore has not finished yet, so every item falls back to
    /// `.title(record.title)`. When the scan then agrees with what was stored
    /// — the common case on a reopen — nothing was written, `reloadTabs()` is
    /// rightly not called, and the placeholder titles would otherwise stand
    /// for the life of the window. Rebuilding the panes to correct a tab
    /// button would be an absurd price; this only rebuilds the buttons.
    public func refreshTabItems() {
        for (edge, record) in currentTabRecords() {
            tabbed.setTabItem(id: record.id, item: tabItem(for: record, on: edge))
        }
    }

    /// The removal half of `reloadTabs()`, extracted so `isReloadingTabs`
    /// is raised and lowered by one `defer` around the loop alone. The flag
    /// must be down again before `installInitialTabs()` runs, or the top-up
    /// persist inside it would be suppressed too.
    private func removeAllTabs() {
        isReloadingTabs = true
        defer { isReloadingTabs = false }
        for split in splitControllersByTabID.values {
            tearDown(split: split)
        }
        for edge in Edge.allCases {
            for tab in tabbed.tabs(on: edge) {
                tabbed.removeTab(id: tab.id)
            }
        }
    }

    /// Tells every pane under `split` that it is being discarded.
    ///
    /// `MultiTabbedViewController.removeTab(id:)` drops a whole split tree
    /// without going through `ComposableTabsViewController.remove(_:)`, which
    /// is the framework's only other call site for `paneWillBeRemoved()`. A
    /// pane's content may own a shell or an FSEvents stream, and "released
    /// whenever the last reference happens to drop" is not a life cycle for a
    /// child process — so the three paths that discard a tree whole,
    /// `removeAllTabs()`, `didRequestCloseTab` and `windowWillClose(_:)`, go
    /// through here.
    private func tearDown(split: ComposableTabsViewController) {
        for leaf in split.allLeaves() {
            leaf.paneWillBeRemoved()
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
    ///
    /// A no-op while `reloadTabs()` is tearing tabs down: `removeTab`'s
    /// `didSelectTab` callback fires for whatever it activates next, and
    /// mid-loop that callback would write the shrinking tab set — pruning
    /// tabs `installInitialTabs()` is about to read straight back out of
    /// storage. A no-op once the window is closing, for the reasons on
    /// `isClosing`.
    private func persistAllTabs() {
        guard !isReloadingTabs, !isClosing else { return }
        project.persistTabs(
            currentTabRecords().map(\.record),
            activeTabID: tabbed.activeTabID,
            enabledEdges: Edge.allCases.filter { tabbed.isEdgeEnabled($0) }
        )
    }

    /// What this window's tabs are, right now, as the records storage holds —
    /// paired with the edge each one is drawn on, which the record itself also
    /// carries but which a caller asking per-edge questions would otherwise
    /// have to dig back out.
    ///
    /// Shared by the two callers that need a record for a live tab: the
    /// persist above, and `refreshTabItems()`, which hands each one back to
    /// the data source (`dry` — one answer to "what is this tab").
    private func currentTabRecords() -> [(edge: Edge, record: TabRecord)] {
        var records: [(edge: Edge, record: TabRecord)] = []
        for edge in Edge.allCases {
            for tab in tabbed.tabs(on: edge) {
                guard let split = splitControllersByTabID[tab.id] else { continue }
                let group = tabGroups.first(where: { $0.members[edge] == tab.id })
                records.append((edge: edge, record: TabRecord(
                    id: tab.id,
                    groupID: group?.id,
                    edge: edge,
                    // The group's own title, not `tab.title`. A hosted item's
                    // title is whatever its view controller reports — nil
                    // becomes `""`, and a source that derives its title from
                    // the record accretes (`main` → `hosted-main` →
                    // `hosted-hosted-main`) across reload/persist cycles.
                    // Either way the stored title would be overwritten
                    // permanently, and the next launch installs tabs before a
                    // data source exists, so the fallback would render it.
                    title: group?.title ?? tab.title,
                    root: split.snapshotNode(),
                    focusedNodeID: focusedLeafByTabID[tab.id],
                    workingDirectory: storedWorkingDirectory(split.workingDirectory)
                )))
            }
        }
        return records
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
    /// This and `projectHelpDrawer` are the only places the window names it:
    /// everything the window actually *does* with help goes through
    /// `HelpPresenting` above, which is what keeps the annotation off
    /// `toggleHelp()` and its `#selector`.
    @available(macOS, deprecated: 10.13)
    public var helpDrawer: WindowDrawer? {
        projectHelpDrawer?.drawer
    }

    /// Filled while open, outlined while closed — the same glyph behaviour the
    /// settings window's help button has, from the same helper. Driven from
    /// `onVisibilityChange` and from `showWindow(_:)` rather than only from the
    /// click, because the drawer also re-asserts itself when the window becomes
    /// key, and because a custom-view toolbar item does not exist until AppKit
    /// has asked the delegate for it.
    private func refreshHelpButtonAppearance() {
        guard let button = toolbarDelegate.button(for: .projectHelp) else { return }
        // The delegate builds a *new* `NSButton` every time AppKit asks it for
        // the item, so "there is already an observer" is not the same question
        // as "there is an observer on the button that is on screen". Asking the
        // second question is what `NotesWindowToolbar` does at its own help
        // glyph; asking only the first leaves the observer tinting a button
        // nobody can see.
        guard helpButton !== button else {
            applyHelpButtonAppearance(to: button)
            return
        }
        helpButton = button
        // `host: button` rather than `self`, for the reason `NotesWindowToolbar`
        // gives too: the tint comes from the *button's* resolved `ThemeScope`,
        // and a window controller is not in the view hierarchy that resolves
        // one. The observer applies immediately on creation, so this replaces
        // the seeding call rather than preceding it — and it must not call back
        // into this method, which would make a second observer before the first
        // is stored. The button is re-resolved inside the closure rather than
        // captured, so the last one built is always the one painted.
        helpThemeObserver = ThemePaletteObserver(host: button) { [weak self] _ in
            guard let self, let helpButton = self.helpButton else { return }
            self.applyHelpButtonAppearance(to: helpButton)
        }
    }

    private func applyHelpButtonAppearance(to button: NSButton) {
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
        guard !isReloadingTabs else { return }
        tabWasActivated()
    }

    /// What "this tab is the one now" costs, wherever the choice came from —
    /// a click on a tab card or a script writing `selected tab`. Both mean the
    /// same thing to the window, so neither gets its own half of it (`dry`).
    private func tabWasActivated() {
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
        activeTabDidChange id: UUID?,
        on edge: Edge?
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
            if let split = splitControllersByTabID[memberID] {
                tearDown(split: split)
            }
            controller.removeTab(id: memberID)
            splitControllersByTabID.removeValue(forKey: memberID)
            focusedLeafByTabID.removeValue(forKey: memberID)
        }
        persistAllTabs()
        // The neighbour's `activeTabDidChange` already fired — but *inside* the
        // loop above, before `splitControllersByTabID` was pruned, so it
        // recomputed against panes that were still on the books. This tail is
        // the only refresh that sees settled state, including in the case where
        // the last member leaves an edge with no fallback and the callback
        // arrived carrying `nil`.
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
        routeSearch(field.stringValue)
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

    /// What the reader last asked for, in memory — not `drawer.isOpen`, and not
    /// a `SELECT`. The drawer is open because the reader asked for it to be
    /// open, and for no other reason: AppKit silently drops an `open()` on a
    /// window that is not on screen yet, which is exactly the moment a restored
    /// window asks, so the drawer's own answer is unreliable and
    /// `reapplyVisibility` is what makes it catch up.
    ///
    /// Held here rather than re-read from the database, for the reason
    /// `ComposableSettings.HelpDrawerController` holds its own preference in a
    /// `UserSettingObserver`: `setSetting` swallows its errors, so a click that
    /// asked the database what it had just written would be a silent no-op
    /// whenever the write failed — and `reapplyVisibility` fires on every
    /// `didBecomeKey` *and* every `didBecomeMain`, which made two main-thread
    /// queries out of every window focus.
    private var isOpen: Bool

    /// What was last written to `drawer.tab` and `drawer.width`, so an
    /// announcement that changed neither writes neither.
    ///
    /// The drawer re-asserts itself on `didBecomeKey` *and* `didBecomeMain`, and
    /// every re-assert announces a visibility change — so one window focus was
    /// four upserts on the main thread for values nobody touched. In-memory
    /// state is the truth here for the same reason it is for `isOpen`: asking
    /// the database what it last stored is a query per announcement, and
    /// `setSetting` swallows its errors anyway.
    ///
    /// `nil` means "nothing written yet", so the first write always happens.
    private var writtenTab: String?
    private var writtenWidth: String?

    /// Whether help has been disclosed at all in this window's lifetime, which
    /// is the gate on writing `drawer.tab` and `drawer.width`. `setSetting`'s
    /// contract is that "never set" and "set back to the default" are one
    /// state; a reader who never touched help has never set anything, and a
    /// default row written on every window close is the opposite of that.
    ///
    /// It cannot be `isOpen`: the moment the width most needs writing is the
    /// moment the drawer *closes*, when `isOpen` has just become false.
    private var hasDisclosedHelp = false

    /// True from the moment the window says it is closing.
    ///
    /// AppKit shuts a drawer along with the window it hangs off, and reports
    /// that through the same `drawerDidClose(_:)` a drag on the outer edge
    /// produces — so without this, closing a window with help open reads as the
    /// reader putting help away, and erases the preference this whole feature
    /// exists to keep. Once it is set, what the reader left behind is what gets
    /// remembered; nothing announced afterwards changes it.
    ///
    /// Never cleared, and it does not need to be: `ProjectWindowManager.swift:171`
    /// drops this controller inside its own `willClose` observer, so reopening a
    /// project builds a fresh presenter — unlike
    /// `ComposableSettings.HelpDrawerController`, whose one instance outlives
    /// every close of the settings window and which therefore clears its own
    /// flag when the window comes back.
    private var isTearingDown = false

    /// True only while `applyVisibility()` is moving the drawer itself.
    ///
    /// The drawer announces every move, including the ones we asked for — and
    /// including an `open()` AppKit dropped because the window was not on
    /// screen yet, which looks from the outside exactly like the reader
    /// dragging the drawer shut. This is what tells those two apart.
    private var isApplyingVisibility = false

    var isHelpVisible: Bool { self.isOpen }

    init(parentWindow: NSWindow, project: ProjectWorkspace) {
        self.project = project
        self.isOpen = project.setting(ProjectWindowSetting.drawerOpen) == "1"
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
        // The drawer announces opening and closing, never resizing — so those
        // are the moments a dragged width is read back, and the first of the
        // two the brief names: putting help away ends the session with it just
        // as surely as closing the window does, and quitting from the menu bar
        // never closes the window at all.
        self.drawer.onVisibilityChange = { [weak self] in
            self?.drawerVisibilityDidChange()
        }
        // The second moment. Registered by selector rather than by block so the
        // observation is zeroing-weak and needs no `deinit` to undo — the same
        // reason `WindowDrawer` watches its parent window that way.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.parentWindowWillClose),
            name: NSWindow.willCloseNotification,
            object: parentWindow)
        // The third, and the one the other two miss: this is an `LSUIElement`
        // app, so quitting from the menu bar ends the session without ever
        // closing the window. A reader who dragged the drawer wider and then
        // touched nothing else would otherwise lose the width at quit. Same
        // registration style, and `object: nil` because the notification comes
        // from the application, not from this window.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil)

        self.applyVisibility()
    }

    // MARK: - HelpPresenting

    func setHelp(_ content: HelpContent?) {
        self.helpView.setHelp(content)
    }

    /// The drawer's own answer, not the remembered preference: the preference
    /// is what the drawer was *asked* for, and an id naming no tab is ignored
    /// by the drawer, so the two can legitimately differ.
    var helpTabID: String? { self.drawer.selectedTabID }

    func toggleHelp() {
        self.isOpen.toggle()
        self.writeOpenState()
        self.applyVisibility()
    }

    /// `nil` deletes the row, so "never opened it" and "closed it again" are one
    /// state rather than two that have to be kept agreeing. The write is the
    /// consequence of the decision, never the decision itself — see `isOpen`.
    private func writeOpenState() {
        self.project.setSetting(ProjectWindowSetting.drawerOpen, to: self.isOpen ? "1" : nil)
    }

    // MARK: - What the project remembers

    private func applyVisibility() {
        self.isApplyingVisibility = true
        defer { self.isApplyingVisibility = false }

        if self.isOpen {
            self.hasDisclosedHelp = true
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

    /// The drawer moved. Either we moved it — in which case there is nothing to
    /// reconcile, only a width and a tab worth writing down — or the reader
    /// dragged it shut by its outer edge, which never goes near the `?` and
    /// would otherwise leave the preference saying "open" and the next
    /// `didBecomeKey` sliding it back out.
    ///
    /// Idempotent on purpose: one move can be announced twice, once from
    /// `WindowDrawer.close()` and once from `NSDrawer`'s delegate.
    private func drawerVisibilityDidChange() {
        if self.closeIsTheReaders, self.isOpen {
            self.isOpen = false
            self.writeOpenState()
            self.onVisibilityChange?()
        }
        self.persistTabAndWidth()
    }

    /// Whether the close just announced is one the reader could have made.
    ///
    /// Two of the three answers are ours: a move `applyVisibility()` is making,
    /// and a window on its way out. The third — is the drawer even shut, and is
    /// its window in a state where AppKit rather than a hand could have shut it
    /// — belongs to the drawer, and `WindowDrawer` answers it for every owner
    /// rather than each one re-deriving it.
    private var closeIsTheReaders: Bool {
        !self.isApplyingVisibility
            && !self.isTearingDown
            && self.drawer.closeIsAttributableToTheReader
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

    /// The last chance to write down a width and a tab, for the session that
    /// ends with the drawer still out.
    @objc private func parentWindowWillClose() {
        // First, and before the persist: AppKit closes the drawer *after* this
        // notification, and that close must not be read as the reader putting
        // help away.
        self.isTearingDown = true
        self.persistTabAndWidth()
    }

    /// The third moment, and the only one that arrives while the window is
    /// still open. Deliberately does **not** set `isTearingDown`: that flag is
    /// there to stop an AppKit-driven close being read as the reader putting
    /// help away, and terminating closes nothing — the drawer is still out, and
    /// its width is exactly what we came to write down.
    @objc private func applicationWillTerminate() {
        self.persistTabAndWidth()
    }

    /// The three moments a dragged width and a chosen tab are written down:
    /// the drawer's visibility changing, the window closing, and the
    /// application terminating. Together they cover every way a session can
    /// end — the last because an `LSUIElement` app quits without closing its
    /// windows.
    ///
    /// Silent until help has actually been disclosed once: a project whose
    /// reader never clicked `?` has no opinion about how wide the drawer should
    /// be, and a default row written on its behalf is a preference nobody set.
    private func persistTabAndWidth() {
        guard self.hasDisclosedHelp else { return }
        let tab = self.drawer.selectedTabID
        let width = String(Double(self.drawer.contentWidth))
        guard tab != self.writtenTab || width != self.writtenWidth else { return }
        self.writtenTab = tab
        self.writtenWidth = width
        self.project.setSetting(ProjectWindowSetting.drawerTab, to: tab)
        self.project.setSetting(ProjectWindowSetting.drawerWidth, to: width)
    }
}
