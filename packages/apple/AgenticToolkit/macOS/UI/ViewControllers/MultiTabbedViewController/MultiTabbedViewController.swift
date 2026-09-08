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
        public var title: String
        public var viewController: NSViewController

        public init(id: UUID = UUID(), title: String, viewController: NSViewController) {
            self.id = id
            self.title = title
            self.viewController = viewController
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

    private var tabBars: [Edge: TabBarView] = [:]

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

    /// The plane the centre content sits on — what shows through
    /// `contentInsets`, and through any gap the content leaves inside itself.
    ///
    /// `nil` is the window background, so the centre disappears into the window
    /// and the tab bars are the only chrome. A host whose content should read
    /// as separate objects rather than as one field gives it a color of its own.
    public var centerBackgroundColor: NSColor? {
        didSet { centerContainer.colorOverride = centerBackgroundColor }
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
            tabBars[edge] = bar
            wireCallbacks(for: bar)
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    open override func loadView() {
        let root = ThemedBackgroundView(role: .windowBackground)

        centerContainer.translatesAutoresizingMaskIntoConstraints = false
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

    public func renameTab(id: UUID, title: String) {
        guard let edge = edge(forTabID: id), let state = edgeStates[edge] else { return }
        guard let idx = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        state.tabs[idx].title = title
        tabBars[edge]?.renameItem(id: id, title: title)
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
        for bar in tabBars.values { bar.setSelected(id) }
        refreshCenterContent()
        // The single funnel every activation goes through — a click,
        // `selectTab`, `activateFallbackTab`, `insertTab`, `removeTab`'s
        // neighbour — so a host is told once, here, instead of at each of them.
        // Fired after the state is applied so the host sees the settled tab.
        if let id, let edge = edge(forTabID: id) {
            delegate?.multiTabbedViewController(self, activeTabDidChange: id, on: edge)
        }
    }

    /// Activates the first tab on the first enabled edge, or clears the
    /// active tab when no enabled edge has tabs.
    private func activateFallbackTab() {
        for edge in Edge.allCases where isEdgeEnabled(edge) {
            if let first = edgeStates[edge]?.tabs.first {
                setActiveTab(first.id)
                return
            }
        }
        setActiveTab(nil)
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

    // MARK: - Sync

    private func syncTabBar(for edge: Edge) {
        guard let state = edgeStates[edge], let bar = tabBars[edge] else { return }
        let items = state.tabs.map { TabBarView.ItemModel(id: $0.id, title: $0.title) }
        bar.setItems(items, selectedID: activeTabID)
    }

    private func edge(forTabID id: UUID) -> Edge? {
        for edge in Edge.allCases where edgeStates[edge]?.tabs.contains(where: { $0.id == id }) == true {
            return edge
        }
        return nil
    }
}
