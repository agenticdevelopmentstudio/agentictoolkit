import AppKit
import Combine

import AgenticDeveloperToolkitUI
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

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
                self.refreshFooterStatus()
            }
            .store(in: &cancellables)
        refreshFooterStatus()
    }

    isolated deinit {
        if let firstResponderObserver {
            NotificationCenter.default.removeObserver(firstResponderObserver)
        }
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
        refreshFooterStatus()
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
            if let focused = self.focusedLeafByTabID[tabID],
               !Self.leafIDs(in: node).contains(focused) {
                self.focusedLeafByTabID[tabID] = nil
            }
            self.persistAllTabs()
            self.refreshFooterStatus()
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
        refreshFooterStatus()
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
