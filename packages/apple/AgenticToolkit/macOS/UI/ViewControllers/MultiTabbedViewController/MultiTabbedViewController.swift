import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// IDE-style tabbed container with up to four edge-docked tab bars (top,
/// right, bottom, left) around a single shared content area. Each enabled
/// edge owns its own tab list; edges can be toggled on/off independently.
///
/// Layout (when all four edges enabled):
/// ```
///           [ top tab bar ]
/// [left bar][   content   ][right bar]
///           [ bottom bar  ]
/// ```
/// Each horizontal bar is its own row spanning the content's width; each
/// vertical bar is its own column spanning the content's height. Exactly
/// one tab is active across the whole controller, and its view controller
/// fills the center. `mainContentViewController` (if set) fills the center
/// while no tab is active.
///
/// Hidden edges keep their tab lists so re-enabling restores them.
@MainActor
open class MultiTabbedViewController: NSViewController {

    // MARK: - Public types

    public struct Tab {
        public let id: UUID

        /// Ties this tab to its siblings on the other edges: one thing the
        /// user thinks of as "a tab" can have a member on each edge, and
        /// selecting any member selects all of them. Defaults to `id`, which
        /// makes a tab its own group of one — the behaviour every host had
        /// before groups existed.
        public let groupID: UUID
        public var item: TabItem
        public var viewController: NSViewController

        @MainActor
        public var title: String { item.title }

        public init(
            id: UUID = UUID(),
            groupID: UUID? = nil,
            item: TabItem,
            viewController: NSViewController
        ) {
            self.id = id
            self.groupID = groupID ?? id
            self.item = item
            self.viewController = viewController
        }

        public init(
            id: UUID = UUID(),
            groupID: UUID? = nil,
            title: String,
            viewController: NSViewController
        ) {
            self.init(id: id, groupID: groupID, item: .title(title), viewController: viewController)
        }
    }

    // MARK: - Public properties

    public weak var delegate: MultiTabbedViewControllerDelegate?

    /// Shown in the center while no tab is active.
    public var mainContentViewController: NSViewController? {
        didSet {
            guard oldValue !== mainContentViewController else { return }
            refreshCenterContent()
        }
    }

    /// The single tab (across all edges) whose content occupies the center.
    public private(set) var activeTabID: UUID?

    // MARK: - Private state

    @MainActor
    private final class EdgeState {
        var enabled: Bool
        var tabs: [Tab] = []

        init(enabled: Bool) {
            self.enabled = enabled
        }
    }

    private var edgeStates: [Edge: EdgeState] = [
        .top: EdgeState(enabled: true),
        .right: EdgeState(enabled: false),
        .bottom: EdgeState(enabled: false),
        .left: EdgeState(enabled: false)
    ]

    private(set) var tabBars: [Edge: TabBarView] = [:]

    private let centerContainer = ThemedBackgroundView(role: .windowBackground)
    private var mountedCenterController: NSViewController?

    /// Space held between the centre content and the tab bars around it.
    ///
    /// Applied here rather than inside the content because the tab bars have to
    /// stay flush against the window: the gap belongs between the bars and what
    /// they frame, and this controller is the only thing that owns both.
    public var contentInsets = NSEdgeInsetsZero {
        didSet { applyContentInsets() }
    }

    /// Where a bar's first tab begins, measured along the bar from its start —
    /// the top of a left or right bar, the leading edge of a top or bottom one.
    ///
    /// A host sets it when the first tab has to line up with something inside
    /// the content it frames; this controller never asks what that something
    /// is, because the content is the only thing that could know.
    public func setTabStartInset(_ inset: CGFloat, for edge: Edge) {
        tabBars[edge]?.startInset = inset
    }

    public func tabStartInset(for edge: Edge) -> CGFloat {
        tabBars[edge]?.startInset ?? 0
    }

    /// The plane the centre content sits on — what shows through
    /// `contentInsets`, and through any gap the content leaves inside itself.
    ///
    /// `nil` is the window background, so the centre disappears into the window
    /// and the tab bars are the only chrome. A host whose content should read
    /// as separate objects rather than as one field gives it a color of its own.
    public var centerBackgroundColor: NSColor? {
        didSet { centerContainer.colorOverride = centerBackgroundColor }
    }

    /// The line drawn around the centre content, so the plane it sits on has a
    /// visible boundary and the tabs standing against that boundary read as
    /// part of the same object rather than as chrome beside it.
    ///
    /// `nil` falls back to the palette's `.outline`.
    public var centerOutlineColor: NSColor? {
        didSet { applyCenterOutline(centerContainer.resolvedThemeScope.palette) }
    }

    /// The four constraints pinning the mounted content, kept so an inset
    /// change is a constant update rather than a teardown.
    private var centerContentConstraints: [NSLayoutConstraint] = []
    private var edgeConstraints: [NSLayoutConstraint] = []

    // MARK: - Lifecycle

    public init() {
        super.init(nibName: nil, bundle: nil)
        for edge in Edge.allCases {
            let bar = TabBarView(edge: edge)
            bar.hostController = self
            tabBars[edge] = bar
            wireCallbacks(for: bar)
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    open override func loadView() {
        let root = ThemedBackgroundView(role: .windowBackground)

        centerContainer.translatesAutoresizingMaskIntoConstraints = false
        centerContainer.observeTheme { [weak self] _, palette in
            self?.applyCenterOutline(palette)
        }
        root.addSubview(centerContainer)
        for edge in Edge.allCases {
            guard let bar = tabBars[edge] else { continue }
            bar.isHidden = !isEdgeEnabled(edge)
            root.addSubview(bar)
        }

        self.view = root
        rebuildEdgeConstraints()
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        for edge in Edge.allCases {
            syncTabBar(for: edge)
        }
        refreshCenterContent()
    }

    /// A hosted item's `preferredContentSize` changing is how it tells the
    /// bar it needs more room — grow the bar that hosts it to match.
    open override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        for bar in tabBars.values { bar.updateThickness() }
    }

    // MARK: - Edge enable/disable

    public func setEdgeEnabled(_ edge: Edge, _ enabled: Bool) {
        guard let state = edgeStates[edge], state.enabled != enabled else { return }
        state.enabled = enabled
        if !enabled, let activeTabID, state.tabs.contains(where: { $0.id == activeTabID }) {
            activateFallbackTab()
        }
        if enabled, activeTabID == nil {
            activateFallbackTab()
        }
        guard isViewLoaded else { return }
        tabBars[edge]?.isHidden = !enabled
        rebuildEdgeConstraints()
    }

    public func isEdgeEnabled(_ edge: Edge) -> Bool {
        edgeStates[edge]?.enabled ?? false
    }

    // MARK: - Tab manipulation (per edge)

    public func addTab(_ tab: Tab, on edge: Edge) {
        insertTab(tab, at: tabs(on: edge).count, on: edge)
    }

    public func insertTab(_ tab: Tab, at index: Int, on edge: Edge) {
        guard let state = edgeStates[edge] else { return }
        let clamped = max(0, min(index, state.tabs.count))
        state.tabs.insert(tab, at: clamped)
        syncTabBar(for: edge)
        if activeTabID == nil, isEdgeEnabled(edge) {
            setActiveTab(tab.id)
        }
    }

    public func removeTab(id: UUID) {
        guard let edge = edge(forTabID: id), let state = edgeStates[edge] else { return }
        guard let index = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = (activeTabID == id)
        state.tabs.remove(at: index)
        syncTabBar(for: edge)
        guard wasActive else { return }
        let nextIndex = min(index, state.tabs.count - 1)
        if nextIndex >= 0 {
            setActiveTab(state.tabs[nextIndex].id)
        } else {
            activateFallbackTab()
        }
        if let activeTabID, let activeEdge = self.edge(forTabID: activeTabID) {
            delegate?.multiTabbedViewController(self, didSelectTab: activeTabID, on: activeEdge)
        }
    }

    /// Retitles a `.title` tab, and **deliberately does nothing to a hosted
    /// one**.
    ///
    /// A hosted item's bar content is a view controller the caller supplied;
    /// there is no text in it to edit, and the only way to honour a title here
    /// would be to replace that controller with a label — tearing down
    /// whatever it was showing in order to obey a request that never asked for
    /// that. A caller that really does want the item replaced says so through
    /// `setTabItem(id:item:)`, which is about replacing the item and says it
    /// in its name.
    public func renameTab(id: UUID, title: String) {
        guard let edge = edge(forTabID: id), let state = edgeStates[edge] else { return }
        guard let idx = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        guard case .title = state.tabs[idx].item else { return }
        state.tabs[idx].item = .title(title)
        tabBars[edge]?.renameItem(id: id, title: title)
    }

    /// Swaps out what a tab shows *in the bar*, leaving its content view
    /// controller — and everything running inside it — exactly where it is.
    ///
    /// `renameTab` cannot do this: it only edits the text of a `.title` item,
    /// and refuses a hosted one outright. A caller whose tab items come from a
    /// data source that was not ready yet needs the other direction — a
    /// `.title` placeholder becoming the real hosted item — and the whole
    /// point of doing it here rather than by rebuilding the tab is that the
    /// pane below the bar must not be disturbed.
    ///
    /// Re-syncing the bar is enough to hand the old hosted controller back:
    /// `TabBarView.rebuildButtons()` reconciles its children on id *and*
    /// payload identity, so the replaced one is torn down there.
    public func setTabItem(id: UUID, item: TabItem) {
        guard let edge = edge(forTabID: id), let state = edgeStates[edge] else { return }
        guard let idx = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        state.tabs[idx].item = item
        syncTabBar(for: edge)
    }

    public func moveTab(id: UUID, to index: Int, on edge: Edge) {
        guard let state = edgeStates[edge] else { return }
        guard let from = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        let clamped = max(0, min(index, state.tabs.count - 1))
        guard from != clamped else { return }
        let item = state.tabs.remove(at: from)
        state.tabs.insert(item, at: clamped)
        syncTabBar(for: edge)
        delegate?.multiTabbedViewController(self, didReorderTab: id, to: clamped, on: edge)
    }

    // MARK: - Inspection

    public func tabs(on edge: Edge) -> [Tab] {
        edgeStates[edge]?.tabs ?? []
    }

    /// The active tab, if it lives on `edge`.
    public func selectedTab(on edge: Edge) -> Tab? {
        guard let id = selectedTabID(on: edge) else { return nil }
        return edgeStates[edge]?.tabs.first(where: { $0.id == id })
    }

    /// The active tab's ID, if the active tab lives on `edge`.
    public func selectedTabID(on edge: Edge) -> UUID? {
        guard let activeTabID,
              edgeStates[edge]?.tabs.contains(where: { $0.id == activeTabID }) == true else { return nil }
        return activeTabID
    }

    public func selectTab(id: UUID, on edge: Edge) {
        guard edgeStates[edge]?.tabs.contains(where: { $0.id == id }) == true else { return }
        setActiveTab(id)
    }

    // MARK: - File menu hook

    /// File > New Tab — auto-disabled by AppKit when no responder
    /// implements this selector. The tab count is global across edges, so
    /// the delegate is expected to add one tab to every enabled edge.
    @objc public func newTab(_ sender: Any?) {
        delegate?.multiTabbedViewControllerNeedsNewTab(self)
    }

    // MARK: - Wiring

    private func wireCallbacks(for bar: TabBarView) {
        let edge = bar.edge
        bar.onSelect = { [weak self] id in
            guard let self else { return }
            self.selectTab(id: id, on: edge)
            self.delegate?.multiTabbedViewController(self, didSelectTab: id, on: edge)
        }
        bar.onClose = { [weak self] id in
            guard let self else { return }
            self.delegate?.multiTabbedViewController(self, didRequestCloseTab: id, on: edge)
        }
        bar.onReorder = { [weak self] id, index in
            guard let self else { return }
            self.delegate?.multiTabbedViewController(self, didReorderTab: id, to: index, on: edge)
        }
    }

    // MARK: - Layout

    /// Pins the center to the enabled bars (or the container edges), each
    /// horizontal bar to its own row hugging the center's width, and each
    /// vertical bar to its own column hugging the center's height. Bar
    /// thickness comes from `TabBarView`'s own constraints. Disabled bars
    /// are hidden and left unconstrained.
    private func rebuildEdgeConstraints() {
        NSLayoutConstraint.deactivate(edgeConstraints)

        let topBar = isEdgeEnabled(.top) ? tabBars[.top] : nil
        let bottomBar = isEdgeEnabled(.bottom) ? tabBars[.bottom] : nil
        let leftBar = isEdgeEnabled(.left) ? tabBars[.left] : nil
        let rightBar = isEdgeEnabled(.right) ? tabBars[.right] : nil

        var constraints: [NSLayoutConstraint] = [
            centerContainer.topAnchor.constraint(equalTo: topBar?.bottomAnchor ?? view.topAnchor),
            centerContainer.bottomAnchor.constraint(equalTo: bottomBar?.topAnchor ?? view.bottomAnchor),
            centerContainer.leadingAnchor.constraint(equalTo: leftBar?.trailingAnchor ?? view.leadingAnchor),
            centerContainer.trailingAnchor.constraint(equalTo: rightBar?.leadingAnchor ?? view.trailingAnchor)
        ]

        if let topBar {
            constraints += [
                topBar.topAnchor.constraint(equalTo: view.topAnchor),
                topBar.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
                topBar.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor)
            ]
        }
        if let bottomBar {
            constraints += [
                bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                bottomBar.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
                bottomBar.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor)
            ]
        }
        if let leftBar {
            constraints += [
                leftBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                leftBar.topAnchor.constraint(equalTo: centerContainer.topAnchor),
                leftBar.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor)
            ]
        }
        if let rightBar {
            constraints += [
                rightBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                rightBar.topAnchor.constraint(equalTo: centerContainer.topAnchor),
                rightBar.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor)
            ]
        }

        edgeConstraints = constraints
        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Active tab & mounting

    private var activeTab: Tab? {
        guard let activeTabID else { return nil }
        for state in edgeStates.values {
            if let tab = state.tabs.first(where: { $0.id == activeTabID }) { return tab }
        }
        return nil
    }

    private func setActiveTab(_ id: UUID?) {
        guard activeTabID != id else { return }
        activeTabID = id
        for (edge, bar) in tabBars { bar.setSelected(selectedID(on: edge)) }
        refreshCenterContent()
        // The single funnel every activation goes through — a click,
        // `selectTab`, `activateFallbackTab`, `insertTab`, `removeTab`'s
        // neighbour — so a host is told once, here, instead of at each of them.
        // Fired after the state is applied so the host sees the settled tab.
        //
        // Including the deactivations: `setEdgeEnabled` runs
        // `activateFallbackTab()` with no fallback to find, and that clearing
        // is as much a change of what is in front as any click. Reported as
        // `nil` rather than not reported, so a host cannot be left rendering a
        // tab that is no longer showing.
        delegate?.multiTabbedViewController(
            self, activeTabDidChange: id, on: id.flatMap { edge(forTabID: $0) })
    }

    /// Keeps the active *group* wherever an enabled edge still shows it,
    /// falls back to the first tab on the first enabled edge, and clears the
    /// active tab when no enabled edge has any.
    ///
    /// The group step is the one that matters. Every sibling of a tab stands
    /// for the same thing — that is what `selectedID(on:)` encodes — so
    /// turning off the edge the active tab happened to live on changes *where*
    /// the user's tab is drawn, not which tab they are on. Taking the first
    /// tab of the first enabled edge instead dropped them onto an unrelated
    /// checkout, and the pane tree in front of them changed with it.
    private func activateFallbackTab() {
        let group = activeTab?.groupID
        let sibling = group.flatMap { group in firstTabOnAnEnabledEdge { $0.groupID == group } }
        setActiveTab(sibling ?? firstTabOnAnEnabledEdge { _ in true })
    }

    private func firstTabOnAnEnabledEdge(where matches: (Tab) -> Bool) -> UUID? {
        for edge in Edge.allCases where isEdgeEnabled(edge) {
            if let tab = edgeStates[edge]?.tabs.first(where: matches) { return tab.id }
        }
        return nil
    }

    private func refreshCenterContent() {
        guard isViewLoaded else { return }
        let target = activeTab?.viewController ?? mainContentViewController
        guard mountedCenterController !== target else { return }
        if let mounted = mountedCenterController {
            mounted.view.removeFromSuperview()
            mounted.removeFromParent()
            centerContentConstraints = []
        }
        mountedCenterController = target
        guard let target else { return }
        if target.parent !== self {
            addChild(target)
        }
        target.view.translatesAutoresizingMaskIntoConstraints = false
        centerContainer.addSubview(target.view)
        centerContentConstraints = [
            target.view.topAnchor.constraint(equalTo: centerContainer.topAnchor),
            target.view.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
            target.view.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor),
            target.view.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor)
        ]
        NSLayoutConstraint.activate(centerContentConstraints)
        applyContentInsets()
    }

    /// Order matches how the constraints were built: top, leading, trailing,
    /// bottom — and the trailing and bottom edges count inward, so their
    /// constants are negative.
    private func applyContentInsets() {
        guard centerContentConstraints.count == 4 else { return }
        centerContentConstraints[0].constant = contentInsets.top
        centerContentConstraints[1].constant = contentInsets.left
        centerContentConstraints[2].constant = -contentInsets.right
        centerContentConstraints[3].constant = -contentInsets.bottom
    }

    /// Draws the centre's boundary straight onto its layer. `ThemedBackgroundView`
    /// paints only a fill, and this is the one view in the toolkit that needs a
    /// line as well — a border property on the shared view would be carried by
    /// every other user of it for this one caller's sake.
    private func applyCenterOutline(_ palette: SemanticPalette) {
        centerContainer.layer?.borderWidth = 1
        centerContainer.layer?.borderColor = (centerOutlineColor ?? palette.nsColor(.outline)).cgColor
    }

    // MARK: - Sync

    private func syncTabBar(for edge: Edge) {
        guard let state = edgeStates[edge], let bar = tabBars[edge] else { return }
        let items = state.tabs.map { TabBarView.ItemModel(id: $0.id, item: $0.item) }
        bar.setItems(items, selectedID: selectedID(on: edge))
    }

    /// Which tab one edge's bar should show as selected: its own member of the
    /// active tab's group. Exactly one tab is active across the controller —
    /// it is the one whose content the centre shows — but every sibling of it
    /// stands for the same thing, so every sibling looks selected.
    private func selectedID(on edge: Edge) -> UUID? {
        guard let group = activeTab?.groupID else { return nil }
        return edgeStates[edge]?.tabs.first(where: { $0.groupID == group })?.id
    }

    private func edge(forTabID id: UUID) -> Edge? {
        for edge in Edge.allCases where edgeStates[edge]?.tabs.contains(where: { $0.id == id }) == true {
            return edge
        }
        return nil
    }
}
