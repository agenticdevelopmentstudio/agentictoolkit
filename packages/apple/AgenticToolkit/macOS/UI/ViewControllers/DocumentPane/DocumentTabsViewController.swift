import AppKit

import AgenticToolkitCore

/// The Document pane: tabs across the top, each holding one or more editors
/// side by side.
///
/// The same sandwich the project window uses — tabs from
/// `MultiTabbedViewController`, splitting from `ComposableTabsViewController` —
/// one level down, with two things handed in that the window does not want: a
/// registry containing only the editor, and an arranger that spreads panes
/// evenly.
///
/// The tab list is persisted here, by this class, rather than by
/// `MultiTabbedViewController` — that base class stores nothing of its own on
/// purpose, so a pane bar can be deployed anywhere without dragging a
/// persistence format with it. What survives a restart, and under which key,
/// is this container's business, the same way `ProjectPaneStateStore`
/// namespaces the *chrome* keys underneath it: only the type that knows what
/// its tabs mean is in a position to decide how they are written down.
@MainActor
public final class DocumentTabsViewController: MultiTabbedViewController {

    public static let tabsStateKey = "document.tabs"

    private let project: ProjectWorkspace
    private let documentWorkingDirectory: URL
    private let documentLayout: ComposableTabsLayout
    private let documentViewID: ComposableTabsViewID

    /// The node this whole container occupies in the enclosing project's
    /// layout tree — handed in rather than discovered, because a registry
    /// factory is the only place that actually knows it (`context.nodeID`).
    private let paneNodeID: UUID

    private var splitsByTabID: [UUID: ComposableTabsViewController] = [:]

    /// The editors `wireTitles(in:tabID:)` has already hooked. It walks every
    /// editor in a tab, and `openToTheSide` calls it again after each split,
    /// so without this an editor that survives three side-splits ends up with
    /// three chained copies of the same handler and fires it three times per
    /// change. Weak, so a closed pane's editor drops out rather than keeping
    /// its identity alive for a later allocation to collide with.
    private let wiredEditors = NSHashTable<DocumentEditorViewController>.weakObjects()

    /// The pane the first responder was last seen in, per tab.
    ///
    /// "Which editor is focused" cannot be answered by asking the window at
    /// the moment the question is put: the click that puts it — a file picked
    /// in the tree — has already moved the first responder into the tree. So
    /// focus is recorded when it arrives and read back afterwards.
    ///
    /// One record per tab, not one for the container: each tab has its own
    /// editors and its own idea of which of them the user was last working in,
    /// and a single slot meant clicking into tab two's editor threw away tab
    /// one's answer — so coming back to tab one opened files into its first
    /// pane however carefully the user had picked another.
    ///
    /// Weak values, so a closed pane is not kept alive by being remembered and
    /// the entry goes with it.
    private let lastFocusedPanes =
        NSMapTable<NSUUID, ComposableTabsPaneViewController>.strongToWeakObjects()

    /// AppKit posts no notification when the first responder moves, and
    /// `NSWindow.firstResponder` is the only place the move is visible. One
    /// observer for the whole container, rather than every pane watching every
    /// event.
    private var focusObservation: NSKeyValueObservation?

    /// The file last handed to `onFocusedDocumentChange`, so moving the caret
    /// around inside one editor does not re-announce what the tree already
    /// highlights. Doubly optional: "nothing reported yet" and "reported as
    /// empty" are different answers.
    private var lastReportedDocument: URL??

    /// Fires with the file the focused editor is showing, so the tree can move
    /// its highlight to follow.
    public var onFocusedDocumentChange: ((URL?) -> Void)?

    /// Fires with a file any editor in this container asked to open — a
    /// go-to-definition target, or a file chosen from a breadcrumb popover.
    /// Routed out to the session rather than opened directly: choosing in the
    /// breadcrumb is the same as clicking in the tree.
    public var onOpenRequest: ((URL) -> Void)?

    public init(
        project: ProjectWorkspace,
        workingDirectory: URL,
        documentLayout: ComposableTabsLayout,
        documentViewID: ComposableTabsViewID,
        paneNodeID: UUID
    ) {
        self.project = project
        self.documentWorkingDirectory = workingDirectory
        self.documentLayout = documentLayout
        self.documentViewID = documentViewID
        self.paneNodeID = paneNodeID
        super.init()
        delegate = self
        setEdgeEnabled(.top, true)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        installRestoredTabs()
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        observeFirstResponder(in: view.window)
    }

    public override func viewDidDisappear() {
        super.viewDidDisappear()
        focusObservation = nil
    }

    // MARK: - Focus

    private func observeFirstResponder(in window: NSWindow?) {
        guard let window else {
            focusObservation = nil
            return
        }
        focusObservation = window.observe(\.firstResponder) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.firstResponderDidMove() }
        }
    }

    /// Records the editor focus arrived in. Focus *leaving* — for the tree, or
    /// for another pane of the window entirely — is deliberately not recorded:
    /// the answer has to outlive the click that asks for it.
    private func firstResponderDidMove() {
        guard let tabID = selectedTabID(on: .top), let root = splitsByTabID[tabID] else { return }
        guard let pane = panes(in: root).first(where: { $0.containsFirstResponder }) else { return }
        rememberFocus(pane, inTab: tabID)
        reportFocusedDocument()
    }

    private func rememberFocus(_ pane: ComposableTabsPaneViewController, inTab tabID: UUID) {
        lastFocusedPanes.setObject(pane, forKey: tabID as NSUUID)
    }

    private func rememberedFocus(inTab tabID: UUID) -> ComposableTabsPaneViewController? {
        lastFocusedPanes.object(forKey: tabID as NSUUID)
    }

    /// Makes the pane holding `editor` the one its tab remembers as focused.
    ///
    /// No-op for an editor that is not in the tab on screen: only a visible pane
    /// can have been the one the user acted in.
    private func rememberFocus(of editor: DocumentEditorViewController) {
        guard let tabID = selectedTabID(on: .top), let root = splitsByTabID[tabID],
              let pane = panes(in: root).first(where: { $0.contentViewController === editor })
        else { return }
        rememberFocus(pane, inTab: tabID)
    }

    /// Hands the focused editor's file out, once per change.
    private func reportFocusedDocument() {
        let url = focusedEditor?.fileURL
        guard lastReportedDocument != .some(url) else { return }
        lastReportedDocument = .some(url)
        onFocusedDocumentChange?(url)
    }

    // MARK: - Building tabs

    /// A tab is always created with exactly one editor pane in it. Zero panes
    /// is not a state this container has.
    private func makeTabRoot(from node: LayoutNode? = nil) -> ComposableTabsViewController {
        let root = ComposableTabsViewController.make(
            from: node ?? .leaf(contentType: documentViewID),
            project: project,
            workingDirectory: documentWorkingDirectory,
            isRoot: true
        )
        // All three stamp the whole subtree through their `didSet`, and all
        // three must be set before the panes' views load — the registry decides
        // what the pane builds, and it only gets one chance.
        root.layoutOverride = documentLayout
        root.arranger = ProportionalArranger()
        // The Document pane's width belongs to the window's tree, not to how
        // many editors this tab happens to hold — see `clampsToContainer`.
        root.clampsToContainer = true
        // These editors are not layout nodes: they exist only inside this
        // pane's own stored layout, so what they remember has to be filed
        // against the node the window *does* know, or the next `saveTabs`
        // sweeps it and every editor comes back empty.
        root.stateOwnerNodeID = paneNodeID
        root.onLayoutDidChange = { [weak self] _ in self?.persistTabs() }
        // The pane's own close box and the tab's close box are the same close
        // box as far as the spec is concerned — "clicking the close box removes
        // the document from display but does not remove the tab" — so they route
        // to the same floor rather than to two implementations of it (`dry`).
        root.onLastPaneCloseRequest = { [weak self, weak root] _ in
            guard let self, let root, let tabID = self.tabID(of: root) else { return }
            self.closeTab(tabID)
        }
        return root
    }

    /// Which tab a root belongs to, by identity. `makeTabRoot` runs before the
    /// `Tab` that will hold it exists, so the id cannot be captured at the point
    /// the hook is installed.
    private func tabID(of root: ComposableTabsViewController) -> UUID? {
        splitsByTabID.first { $0.value === root }?.key
    }

    @discardableResult
    private func addTab(root: ComposableTabsViewController, title: String) -> UUID {
        let tab = Tab(title: title, viewController: root)
        splitsByTabID[tab.id] = root
        addTab(tab, on: .top)
        wireTitles(in: root, tabID: tab.id)
        return tab.id
    }

    /// Hooks every not-yet-hooked editor in `root` so a title change retitles
    /// the tab and reports the focus change outward. Idempotent: `openToTheSide`
    /// calls this over a whole tab after adding one pane, and an editor must
    /// come away with exactly one copy of each handler however many times it
    /// is walked.
    ///
    /// `DocumentEditorViewController.onTitleChange` is the same storage
    /// `PaneTitleProviding.onPaneTitleChange` writes through, and
    /// `PaneViewController` has already claimed it by the time this runs — it
    /// is what keeps the pane's own title bar in sync. Overwriting it outright
    /// would silently stop that. Capturing and chaining the previous closure
    /// keeps both listeners alive rather than the second one winning.
    private func wireTitles(in root: ComposableTabsViewController, tabID: UUID) {
        for editor in editors(in: root) where !wiredEditors.contains(editor) {
            wiredEditors.add(editor)
            let previousTitleHandler = editor.onTitleChange
            editor.onTitleChange = { [weak self] in
                previousTitleHandler?()
                self?.retitle(tabID)
                self?.reportFocusedDocument()
            }
            // Same chaining concern as `onTitleChange` above: the editor may
            // already have an owner for this handler, and overwriting it
            // outright would silently drop them.
            let previousOpenHandler = editor.onOpenRequest
            editor.onOpenRequest = { [weak self, weak editor] url in
                previousOpenHandler?(url)
                guard let self else { return }
                // Recorded *before* the request goes out. It leaves here for the
                // session — choosing in a breadcrumb is the same event as
                // clicking in the tree — and comes back as
                // `openInSelectedPane(_:)`, by which point the one fact only
                // this end ever knew is gone: which editor asked. Clicking a
                // breadcrumb moves no first responder, so without this the file
                // landed in whichever editor the user had last typed in.
                if let editor { self.rememberFocus(of: editor) }
                self.onOpenRequest?(url)
            }
        }
    }

    private func retitle(_ tabID: UUID) {
        guard let root = splitsByTabID[tabID] else { return }
        let title = focusedEditor(in: root)?.paneTitle ?? "Untitled"
        renameTab(id: tabID, title: title)
    }

    // MARK: - Opening

    public func openInSelectedPane(_ url: URL) {
        guard let editor = focusedEditor else { return }
        editor.fileURL = url
    }

    public func openInNewTab(_ url: URL) {
        let root = makeTabRoot()
        let newTabID = addTab(root: root, title: url.lastPathComponent)
        selectTab(id: newTabID, on: .top)
        focusedEditor(in: root)?.fileURL = url
        persistTabs()
    }

    public func openToTheSide(_ url: URL) {
        guard let tabID = selectedTabID(on: .top),
              let root = splitsByTabID[tabID],
              let focused = focusedPane(in: root) else { return }

        let before = Set(editors(in: root).map(ObjectIdentifier.init))
        (focused.host as? ComposableTabsViewController)?.split(
            focused, adding: documentViewID, direction: .right
        )
        wireTitles(in: root, tabID: tabID)

        // The pane the split just made, never the rightmost one: the split
        // lands beside the *focused* pane, so opening twice without moving the
        // focus would hand the second file to the pane the first one filled.
        let added = editors(in: root).first { !before.contains(ObjectIdentifier($0)) }
        // The new editor is the one the user just asked for, so it becomes the
        // focused one — *before* it is filled. Both the tab's title and the
        // tree's highlight name whatever the focused editor holds, and filling
        // it first announces the new file while the old pane still counts as
        // focused, leaving the tab named after the file beside it. Keyboard
        // focus itself is left where the window put it — the editor's text view
        // is CodeEditSourceEditor's, not ours to hand the first responder to.
        if let addedPane = panes(in: root).first(where: { $0.contentViewController === added }) {
            rememberFocus(addedPane, inTab: tabID)
        }
        added?.fileURL = url
        reportFocusedDocument()
        persistTabs()
    }

    // MARK: - Inspection

    public var focusedEditor: DocumentEditorViewController? {
        guard let tabID = selectedTabID(on: .top), let root = splitsByTabID[tabID] else { return nil }
        return focusedEditor(in: root)
    }

    public func editors(inTabAt index: Int) -> [DocumentEditorViewController] {
        let all = tabs(on: .top)
        guard index >= 0, index < all.count, let root = splitsByTabID[all[index].id] else { return [] }
        return editors(in: root)
    }

    /// The chrome-bearing panes of a tab, in tree order.
    ///
    /// `editors(inTabAt:)` answers about the documents; this answers about the
    /// things with close boxes on them, which is what a test of the close box
    /// has to hold.
    public func panes(inTabAt index: Int) -> [ComposableTabsPaneViewController] {
        let all = tabs(on: .top)
        guard index >= 0, index < all.count, let root = splitsByTabID[all[index].id] else { return [] }
        return panes(in: root)
    }

    public func paneFractions(inTabAt index: Int) -> [CGFloat] {
        let all = tabs(on: .top)
        guard index >= 0, index < all.count, let root = splitsByTabID[all[index].id] else { return [] }
        return absoluteFractions(of: root.snapshotNode())
    }

    /// The arranger works in fractions *of the enclosing split*, so a nested
    /// tree's numbers have to be multiplied down the spine before they can be
    /// compared to "a third of the tab".
    private func absoluteFractions(of node: LayoutNode, scale: CGFloat = 1) -> [CGFloat] {
        switch node.kind {
        case .leaf:
            return [scale]
        case .split(_, let first, let second):
            let firstScale = CGFloat(first.thicknessFraction ?? 0.5) * scale
            let secondScale = CGFloat(second.thicknessFraction ?? 0.5) * scale
            return absoluteFractions(of: first, scale: firstScale)
                + absoluteFractions(of: second, scale: secondScale)
        }
    }

    private func editors(in root: ComposableTabsViewController) -> [DocumentEditorViewController] {
        panes(in: root).compactMap { $0.contentViewController as? DocumentEditorViewController }
    }

    private func focusedEditor(in root: ComposableTabsViewController) -> DocumentEditorViewController? {
        focusedPane(in: root)?.contentViewController as? DocumentEditorViewController
    }

    private func focusedPane(in root: ComposableTabsViewController) -> ComposableTabsPaneViewController? {
        let all = panes(in: root)
        // The record first, the window second. `firstResponderDidMove()` writes
        // the record from the same first responder this would read, so the two
        // agree whenever focus is in a pane — and where they don't, the record is
        // the more informed of the two: it also carries the pane the user acted
        // in through a click that moved no first responder at all, which is every
        // click on a breadcrumb or a control in the chrome. Asking the window
        // first handed those files to whichever editor was last typed in.
        if let tabID = tabID(of: root), let remembered = rememberedFocus(inTab: tabID),
           all.contains(where: { $0 === remembered }) {
            return remembered
        }
        // Focus that arrived before this container had a window to observe.
        if let holding = all.first(where: { $0.containsFirstResponder }) { return holding }
        return all.first
    }

    /// Every leaf pane under `controller`, forcing each one's view to load on
    /// the way.
    ///
    /// A pane's `contentViewController` is built lazily, in `loadView()` — see
    /// `PaneViewController` — and wrapping a view controller in an
    /// `NSSplitViewItem` does not itself trigger that (`ComposableTabsViewController`'s
    /// own tests force it the same way with an explicit `_ = leaf.view`). In a
    /// headless test there is no window to lay a split view out and load its
    /// items for it, so nothing else in the chain will ever ask.
    private func panes(in controller: ComposableTabsViewController) -> [ComposableTabsPaneViewController] {
        controller.layoutChildren.flatMap { child -> [ComposableTabsPaneViewController] in
            if let pane = child as? ComposableTabsPaneViewController {
                _ = pane.view
                return [pane]
            }
            if let split = child as? ComposableTabsViewController { return panes(in: split) }
            return []
        }
    }

    // MARK: - Persistence

    /// The tab list is this controller's to persist: `MultiTabbedViewController`
    /// stores nothing itself, and the project's own tab tables belong to the
    /// window, not to a pane inside it.
    public func persistTabs() {
        let snapshots = tabs(on: .top).compactMap { splitsByTabID[$0.id]?.snapshotNode() }
        let records = snapshots.map { StoredTab(root: LayoutNodeCodable($0)) }
        let stored = StoredTabs(
            tabs: records,
            selectedIndex: tabs(on: .top).firstIndex { $0.id == selectedTabID(on: .top) } ?? 0
        )
        guard let data = try? JSONEncoder().encode(stored),
              let json = String(data: data, encoding: .utf8) else { return }
        project.setPaneState(nodeID: paneNodeID, key: Self.tabsStateKey, value: json)

        // The editors in these tabs are not layout nodes, so the project's own
        // sweep cannot collect what they remembered: their rows are filed under
        // this pane's node id with their own id in the key, and this pane is
        // still here. This is the list only this controller has — every id its
        // tabs still spend, written down at the same moment the trees holding
        // them are — so the collecting is this controller's too.
        var liveIDs: Set<UUID> = [paneNodeID]
        for snapshot in snapshots {
            liveIDs.formUnion(snapshot.allIDs)
        }
        project.pruneNestedPaneState(nodeID: paneNodeID, keeping: liveIDs)
    }

    private func readStoredTabs() -> StoredTabs {
        guard let json = project.paneState(nodeID: paneNodeID, key: Self.tabsStateKey),
              let data = json.data(using: .utf8),
              let stored = try? JSONDecoder().decode(StoredTabs.self, from: data) else {
            return StoredTabs(tabs: [], selectedIndex: 0)
        }
        return stored
    }

    private func installRestoredTabs() {
        let stored = readStoredTabs()
        guard !stored.tabs.isEmpty else {
            addTab(root: makeTabRoot(), title: "Untitled")
            // Written down at once, because this tab's layout node ids are the
            // keys its editors file everything under. Left unpersisted, the next
            // launch found no tab list, invented a second tab with fresh ids, and
            // every `document.<uuid>.*` row the first launch wrote — the file each
            // editor had open above all — was orphaned where no sweep can reach
            // it. One empty tab is a layout like any other.
            persistTabs()
            return
        }
        for record in stored.tabs {
            // Titled from the restored editors rather than from the record:
            // `retitle` walks the panes, which loads them, which is what asks
            // each editor for the file it remembers. Until that happens there
            // is nothing to name the tab after.
            let tabID = addTab(root: makeTabRoot(from: record.root.node), title: "Untitled")
            retitle(tabID)
        }
        let all = tabs(on: .top)
        if stored.selectedIndex >= 0, stored.selectedIndex < all.count {
            selectTab(id: all[stored.selectedIndex].id, on: .top)
        }
    }
}

// MARK: - The floor

extension DocumentTabsViewController: MultiTabbedViewControllerDelegate {

    /// Everything closes until one tab with one pane is left. Closing that one
    /// empties the editor and keeps the pane and the tab — you always land
    /// back on an empty editor, never an empty window.
    public func multiTabbedViewController(
        _ controller: MultiTabbedViewController,
        didRequestCloseTab tabID: UUID,
        on edge: Edge
    ) {
        closeTab(tabID)
    }

    /// The floor itself, reached from the tab's close box and from the last
    /// editor pane's — see `onLastPaneCloseRequest` in `makeTabRoot`.
    func closeTab(_ tabID: UUID) {
        guard tabs(on: .top).count > 1 else {
            // Every editor in the tab, not only the focused one: what the user
            // clicked closes the *tab*, and `retitle` renames it "Untitled" the
            // moment the focused editor empties — a tab named after nothing while
            // three of its four panes still show files is a tab lying about what
            // is in it. The arrangement stays: the panes are the user's, and the
            // floor is about the documents.
            splitsByTabID[tabID].map(editors(in:))?.forEach { $0.clearDocument() }
            retitle(tabID)
            persistTabs()
            return
        }
        // `removeTab(id:)` drops the whole tree without going through
        // `ComposableTabsViewController.remove(_:)`, so nothing else tells these
        // panes they are gone — the arrange overlay's local key-down monitor
        // would outlive the tab and `PaneContentTeardown` would never run.
        splitsByTabID.removeValue(forKey: tabID)?.tearDownPanes()
        lastFocusedPanes.removeObject(forKey: tabID as NSUUID)
        removeTab(id: tabID)
        persistTabs()
    }

    public func multiTabbedViewController(
        _ controller: MultiTabbedViewController,
        activeTabDidChange tabID: UUID?,
        on edge: Edge?
    ) {
        reportFocusedDocument()
    }
}

// MARK: - Persisted layout mirror

/// A `Codable` mirror of `LayoutNode`.
///
/// `LayoutNode` is a storage-vocabulary value type built over
/// `ComposableTabsViewID`, which is deliberately not `Codable` itself — see its
/// own doc comment — so this is the one place that knows how to turn a tab's
/// tree into JSON and back. A struct rather than reusing `LayoutNode` directly
/// because a self-referencing struct cannot hold its own children without an
/// array or a class in the way, and an array of exactly zero or two elements
/// reads less clearly at the call site than two named optionals would.
struct LayoutNodeCodable: Codable {

    private enum Kind: String, Codable {
        case split
        case leaf
    }

    private let id: UUID
    private let kind: Kind
    private let contentType: String?
    private let paneLabel: String?
    private let orientation: String?
    private let thicknessFraction: Double?
    private let first: Box<LayoutNodeCodable>?
    private let second: Box<LayoutNodeCodable>?

    init(_ node: LayoutNode) {
        id = node.id
        thicknessFraction = node.thicknessFraction
        switch node.kind {
        case .leaf(let contentType, let paneLabel):
            kind = .leaf
            self.contentType = contentType.rawValue
            self.paneLabel = paneLabel
            orientation = nil
            first = nil
            second = nil
        case .split(let orientation, let firstNode, let secondNode):
            kind = .split
            contentType = nil
            paneLabel = nil
            self.orientation = orientation.rawValue
            first = Box(LayoutNodeCodable(firstNode))
            second = Box(LayoutNodeCodable(secondNode))
        }
    }

    var node: LayoutNode {
        switch kind {
        case .leaf:
            return .leaf(
                id: id,
                contentType: ComposableTabsViewID(contentType ?? ""),
                paneLabel: paneLabel,
                thicknessFraction: thicknessFraction
            )
        case .split:
            let axis = orientation.flatMap(ComposableTabsAxis.init(rawValue:)) ?? .horizontal
            return .split(
                id: id,
                orientation: axis,
                first: first?.value.node ?? .leaf(contentType: .placeholder),
                second: second?.value.node ?? .leaf(contentType: .placeholder),
                thicknessFraction: thicknessFraction
            )
        }
    }
}

/// Heap indirection for `LayoutNodeCodable`'s two optional children — a struct
/// cannot hold an optional of itself directly, only through something already
/// on the heap.
private final class Box<Value: Codable>: Codable {
    let value: Value

    init(_ value: Value) { self.value = value }

    init(from decoder: Decoder) throws {
        value = try Value(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

/// A tab is stored as its layout alone. The title is deliberately not written
/// down: it is the focused editor's file name, the editors already remember
/// their own files, and a second copy of one fact is a copy that goes stale —
/// the editor records a new file the moment it is opened, while the tab list is
/// only rewritten when the arrangement changes. `installRestoredTabs` derives
/// the title back from the restored editors. (Tab lists written before this
/// still carry a `title`; `JSONDecoder` ignores it.)
struct StoredTab: Codable {
    let root: LayoutNodeCodable
}

struct StoredTabs: Codable {
    let tabs: [StoredTab]
    let selectedIndex: Int
}
