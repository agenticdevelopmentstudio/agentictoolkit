//
//  ExtensionTreeViewController.swift
//  AgenticToolkit
//

import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import Foundation

/// Finds the data source a contributed **tree** view should draw, and says when
/// one arrives.
///
/// `ContributedWebviewResolving`'s twin, and deliberately a different shape.
/// A webview panel is the *app's* object, built here and handed to the
/// extension, so resolving returns it. A tree data provider is the
/// *extension's* object and does not exist until `registerTreeDataProvider` or
/// `createTreeView` has run — which may be behind an activation event that has
/// not happened yet. So there is nothing to return: the answer arrives through
/// `didResolve`, synchronously when the provider is already registered and a
/// turn or two later when the extension had to be woken first.
///
/// - Parameters:
///   - view: The declaration, including the extension that made it.
///   - didResolve: Called once, with the data source, if one is ever
///     registered for this view id. Never called when the extension registers
///     none, which is what leaves the pane showing its explanation.
public typealias ContributedTreeResolving = @MainActor (
    _ view: ContributedView,
    _ didResolve: @escaping (any ExtensionTreeDataSource) -> Void
) -> Void

/// The pane a contributed **tree** view gets: the extension's tree once the
/// extension registers a provider for it, and the explanation until then.
///
/// `ExtensionWebviewViewController`'s counterpart, down to the swap: the state
/// where an extension declares a view in its manifest and registers nothing for
/// it is ordinary — a `when` clause nothing has satisfied, a provider behind a
/// later activation event — and an empty outline would claim the extension
/// answered "no rows" when in truth it was never asked
/// (`principle-of-least-astonishment`).
///
/// Unlike the webview wrapper the swap here runs at most once and in one
/// direction: a webview panel can be disposed and put the placeholder back,
/// while a tree data provider's registration is disposed only by the extension
/// going away, which takes the whole pane's host with it.
@MainActor
public final class ExtensionTreeViewController: NSViewController {

    private let contributedView: ContributedView
    private let extensionDisplayName: String
    private let resolve: ContributedTreeResolving

    /// What is on screen now. `nil` until `loadView()`.
    private var content: NSViewController?

    /// Stops a late resolve from building a tree into a pane on its way out:
    /// an extension activated by this very pane's appearance can register its
    /// provider after the user has already closed it.
    private var isBeingDiscarded = false

    /// `PaneTitleProviding.onPaneTitleChange`, held here and forwarded, for
    /// `ExtensionWebviewViewController`'s reason: the pane claims it before any
    /// tree exists and must keep hearing about retitles across the swap.
    private var onTitleChange: (() -> Void)?

    public init(
        view: ContributedView,
        extensionDisplayName: String,
        resolve: @escaping ContributedTreeResolving
    ) {
        self.contributedView = view
        self.extensionDisplayName = extensionDisplayName
        self.resolve = resolve
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        container.wantsLayer = true
        container.observeTheme { view, palette in
            view.layer?.backgroundColor = palette.nsColor(.surface).cgColor
        }
        view = container
        show(ExtensionViewPlaceholderViewController(
            view: contributedView, extensionDisplayName: extensionDisplayName))
    }

    /// Asks in `viewDidLoad` rather than `loadView`, for the reason the webview
    /// wrapper gives: an extension that is already awake resolves synchronously,
    /// and swapping content while `view` is still being assigned is how a view
    /// controller ends up asking for its own view from inside `loadView`.
    public override func viewDidLoad() {
        super.viewDidLoad()
        resolve(contributedView) { [weak self] dataSource in
            self?.adopt(dataSource)
        }
    }

    /// `replacing` is what lets a second source past the refusal below.
    ///
    /// The refusal is for `resolve` answering twice — an extension that is
    /// already awake answers synchronously *and* again on the activation
    /// callback — and a second outline for the same source would throw away
    /// the user's open branches. A *replacement* source is the opposite case:
    /// the outline on screen is bound to a model the adaptor has retired,
    /// which answers no children by design, so leaving it there leaves a
    /// permanently blank pane.
    private func adopt(_ dataSource: any ExtensionTreeDataSource, replacing: Bool = false) {
        guard !isBeingDiscarded else { return }
        guard replacing || !(content is ExtensionTreeOutlineViewController) else { return }
        // Re-hooked on every source this pane binds to, so the chain keeps
        // going: a replacement is itself replaced by the registration after
        // it, and a pane that hooked only the first one would go blank on the
        // second reload instead of the first.
        dataSource.onProviderReplaced = { [weak self] replacement in
            self?.adopt(replacement, replacing: true)
        }
        show(ExtensionTreeOutlineViewController(
            dataSource: dataSource,
            fallbackTitle: contributedView.name,
            accessibilityPrefix: contributedView.registryID))
    }

    /// Replaces whatever is on screen, wiring the pane's title callback to
    /// whichever child holds it now.
    private func show(_ child: NSViewController) {
        if let current = content {
            // The outgoing child is discarded, not merely unparented. An
            // outline retires by this route now (see `adopt(_:replacing:)`),
            // and one that is never told hands its callbacks back to nobody:
            // it stays registered in `callbackOwners` against a source it no
            // longer draws, so the replacement's own teardown finds the
            // ownership test failing and leaves the *live* source wired to a
            // pane that is gone.
            (current as? PaneContentTeardown)?.paneContentWillBeDiscarded()
            (current as? PaneTitleProviding)?.onPaneTitleChange = nil
            current.removeFromParent()
            current.view.removeFromSuperview()
        }
        content = child
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        (child as? PaneTitleProviding)?.onPaneTitleChange = { [weak self] in
            self?.onTitleChange?()
        }
        // The title moved by definition: the new child answers `paneTitle`
        // differently from the old one, and nothing else will say so.
        onTitleChange?()
    }
}

// MARK: - Being a pane

extension ExtensionTreeViewController: PaneTitleProviding {

    /// What the tree calls itself once `createTreeView` has let the extension
    /// rename it, and the manifest's name until then — which is also what the
    /// placeholder shows, so the chrome and the pane never disagree.
    public var paneTitle: String {
        (content as? PaneTitleProviding)?.paneTitle ?? contributedView.name
    }

    public var onPaneTitleChange: (() -> Void)? {
        get { onTitleChange }
        set { onTitleChange = newValue }
    }
}

extension ExtensionTreeViewController: PaneContentTeardown {

    /// Hands the teardown down and refuses any later resolve. The tree itself
    /// holds no process and no window — what it has is two callbacks on an
    /// object that outlives the pane, and the child is what takes them back.
    public func paneContentWillBeDiscarded() {
        isBeingDiscarded = true
        (content as? PaneContentTeardown)?.paneContentWillBeDiscarded()
    }
}

// MARK: - The outline

/// One row of a contributed tree, as `NSOutlineView` needs to hold it.
///
/// A reference type because the outline identifies items by pointer: expansion
/// state, selection and `reloadItem(_:)` all key off the object, so a row
/// rebuilt as a fresh instance on every refresh would collapse every branch the
/// user had opened. The same object is therefore kept for the life of a handle
/// and its `item` rewritten in place.
@MainActor
final class ExtensionTreeRow {

    /// `ContributedTreeItem.id` — the handle the data source mints, and the
    /// key everything in the controller below is stored under.
    let handle: String

    var item: ContributedTreeItem

    init(item: ContributedTreeItem) {
        self.handle = item.id
        self.item = item
    }

    /// A blank row for the one question the outline can ask that has no answer
    /// — see `outlineView(_:child:ofItem:)`. Never stored, so its empty handle
    /// collides with nothing.
    static func placeholder() -> ExtensionTreeRow {
        ExtensionTreeRow(item: ContributedTreeItem(
            id: "",
            label: "",
            description: nil,
            tooltip: nil,
            collapsibleState: .none,
            symbolName: nil,
            commandID: nil))
    }
}

/// Draws one registered `TreeDataProvider`, and reports back what the user does
/// to it.
///
/// **Pull, not push, and asynchronous both ways.** `getChildren` is asked as
/// branches are opened and never for a branch nobody opens, and it answers a
/// `Thenable` often enough that waiting is the normal case rather than the
/// exception (`ExtensionTreeDataSource`'s own doc). An `NSOutlineView` cannot
/// wait for an answer, so every question is answered from the cache below —
/// empty on the first ask — and the branch is reloaded when the answer lands.
///
/// **One pane per view id at a time.** The data source carries a single
/// `onDidChangeTreeData` and a single `onDidChangeChrome`, so a second pane for
/// the same contributed view in a second window would take both callbacks over
/// and leave the first pane frozen at whatever it had drawn. That is upstream's
/// model too — a view id names one tree, not one per window — and the pane that
/// loses the callbacks is the one the user is not looking at, since taking them
/// is what building the newer pane does.
///
/// Internal rather than file-private so its two asynchronous rules — a branch
/// stays askable when a provider never answers, and a row an extension moves is
/// drawn under one parent — can be driven by a test. Nothing outside this
/// framework can see it; `ExtensionTreeViewController` is still the only way in.
@MainActor
final class ExtensionTreeOutlineViewController: NSViewController {

    private let dataSource: any ExtensionTreeDataSource

    /// The manifest's name for the view, shown until the extension renames it.
    private let fallbackTitle: String

    private let outline = ThemedOutlineView(role: .surface)
    private let scrollView = ThemedScrollView()

    /// `TreeView.message` — a banner above the rows, which is how an extension
    /// says "no results", or qualifies the rows it did answer, without
    /// inventing a row that says it.
    private let messageLabel = ThemedLabel(string: "", role: .tertiaryText, textRole: .caption)

    /// The rows this pane has drawn and how they are related — see
    /// `ExtensionTreeRowTable`, which is the half of this controller with no
    /// view in it.
    private var table = ExtensionTreeRowTable()

    /// Handles with a `getChildren` in flight. A second ask for the same branch
    /// while the first is outstanding would be a second call into the
    /// extension's provider for an answer already on its way.
    private var loadingHandles: Set<String> = []

    /// Handles that were told to refresh while their load was in flight. The
    /// in-flight answer predates the change, so it is drawn and then asked
    /// again — dropping the request instead would leave the tree silently
    /// disagreeing with the extension, which is the one failure a user cannot
    /// diagnose.
    private var staleHandles: Set<String> = []

    /// Set while the outline is being reloaded, so the empty selection a reload
    /// passes through is not reported to the extension as the user letting go
    /// of the row they are reading.
    private var isSyncingSelection = false

    /// The same guard for disclosure: a branch this controller opens to honour
    /// `TreeItemCollapsibleState.Expanded` is not the user expanding it, and
    /// `onDidExpandElement` is documented as the user's gesture.
    private var isSyncingExpansion = false

    private var onTitleChange: (() -> Void)?

    /// Set by the pane's teardown: the callbacks are already back, and a load
    /// still in flight must not draw into a view on its way out.
    private var isBeingDiscarded = false

    private let accessibilityPrefix: String

    init(
        dataSource: any ExtensionTreeDataSource,
        fallbackTitle: String,
        accessibilityPrefix: String
    ) {
        self.dataSource = dataSource
        self.fallbackTitle = fallbackTitle
        self.accessibilityPrefix = accessibilityPrefix
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - View

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("extension-tree"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 22
        outline.indentationPerLevel = 14
        outline.style = .inset
        outline.allowsEmptySelection = true
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(rowDoubleClicked(_:))
        outline.autoresizesOutlineColumn = false
        _ = outline.accessibilityID("\(accessibilityPrefix).tree")

        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.cell?.wraps = true
        messageLabel.cell?.usesSingleLineMode = false
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.alignment = .left
        messageLabel.isHidden = true
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        _ = messageLabel.accessibilityID("\(accessibilityPrefix).message")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        container.addSubview(scrollView)
        container.addSubview(messageLabel)
        treeBelowMessage = scrollView.topAnchor.constraint(
            equalTo: messageLabel.bottomAnchor, constant: Self.messageInset / 2)
        treeAtTop = scrollView.topAnchor.constraint(equalTo: container.topAnchor)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            treeAtTop,
            messageLabel.topAnchor.constraint(
                equalTo: container.topAnchor, constant: Self.messageInset / 2),
            messageLabel.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: Self.messageInset),
            messageLabel.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -Self.messageInset)
        ])
        view = container
    }

    /// Inset from each side of the pane for the message, matching the
    /// placeholder's own so the two read as the same pane saying two things.
    private static let messageInset: CGFloat = 16

    /// The two positions the tree can start at: under the message banner, or
    /// at the top of the pane when there is no message. Exactly one is active,
    /// swapped by `applyChrome()`.
    private var treeBelowMessage: NSLayoutConstraint!
    private var treeAtTop: NSLayoutConstraint!

    /// The identifier the plain background row views are recycled under.
    private static let backgroundRowIdentifier =
        NSUserInterfaceItemIdentifier("extension.tree.backgroundRow")

    /// This pane's claim on the data source's two callbacks.
    ///
    /// A token rather than the pane's identity because an address can be
    /// reused once a pane has gone, and this outlives the pane that minted it.
    private let callbackToken = UUID()

    /// Which pane holds each data source's callbacks now.
    ///
    /// **One pane per view id is the model, and this is the other half of it.**
    /// A second pane for the same contributed view takes both callbacks over
    /// — see the class doc — so the older pane is already inert by the time
    /// the user closes it. Its teardown, though, still ran unconditionally:
    /// it nilled the callbacks the *live* pane had installed, and that pane
    /// went quiet for good, showing whatever it had drawn until the window
    /// closed. Closures cannot be compared, so ownership is recorded here and
    /// a teardown only undoes its own wiring *(idempotency — a stale pane
    /// tearing down twice, or out of order, changes nothing)*.
    private static var callbackOwners: [ObjectIdentifier: UUID] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        Self.callbackOwners[ObjectIdentifier(dataSource)] = callbackToken
        dataSource.onDidChangeTreeData = { [weak self] handle in
            self?.providerDidChangeTreeData(handle)
        }
        dataSource.onDidChangeChrome = { [weak self] in
            self?.applyChrome()
        }
        applyChrome()
        loadChildren(of: "")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        reportVisibility(true)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        reportVisibility(false)
    }

    /// `TreeView.visible` describes the pane that holds the source's
    /// callbacks, and no other — the same ownership test `paneContentWillBeDiscarded`
    /// makes, for the same reason, and it was missing here.
    ///
    /// A pane superseded by a second one for the same view id stays in its
    /// window until the user closes it, and goes on receiving appearance
    /// notifications the whole time. Unguarded, those overwrote the live
    /// pane's answer: the retired pane scrolling out of view, or its window
    /// closing, told the extension its tree was hidden while the tree the user
    /// is looking at was on screen — and an extension that only refreshes
    /// while visible then stopped refreshing.
    private func reportVisibility(_ isVisible: Bool) {
        guard Self.callbackOwners[ObjectIdentifier(dataSource)] == callbackToken else { return }
        dataSource.visibilityDidChange(to: isVisible)
    }

    /// The width a multi-line `NSTextField` computes its intrinsic height
    /// against — the same measurement, and the same collapsed-pane floor,
    /// `ExtensionViewPlaceholderViewController.viewDidLayout` explains at
    /// length.
    override func viewDidLayout() {
        super.viewDidLayout()
        messageLabel.preferredMaxLayoutWidth = max(
            0, view.bounds.width - 2 * Self.messageInset)
    }

    /// `title`, `message` and `canSelectMany`, which move through the
    /// `TreeView` object rather than through the rows.
    private func applyChrome() {
        outline.allowsMultipleSelection = dataSource.allowsMultipleSelection
        let message = dataSource.message
        messageLabel.stringValue = message ?? ""
        messageLabel.isHidden = message == nil
        // A banner above the rows, never instead of them (`vscode.d.ts:11298`
        // renders it in the view, with the tree still under it). An extension
        // that keeps a standing message — "showing 10 of 100" — would lose its
        // whole tree to a pane that read `message` as a replacement, and the
        // one state where there genuinely are no rows already draws as an
        // empty outline under the sentence explaining it.
        treeAtTop.isActive = message == nil
        treeBelowMessage.isActive = message != nil
        view.needsLayout = true
        onTitleChange?()
    }

    // MARK: - Reading the provider

    /// The rows under `item`, which is `nil` for the roots.
    ///
    /// Answers from the cache and starts the load that will fill it. Returning
    /// nothing for a branch that has not been read is what makes a slow
    /// provider merely late: the branch draws empty for as long as the
    /// extension takes, and reloads itself when the answer lands.
    private func children(of item: Any?) -> [ExtensionTreeRow] {
        let handle = (item as? ExtensionTreeRow)?.handle ?? ""
        if let cached = table.children(of: handle) { return cached }
        loadChildren(of: handle)
        return []
    }

    /// How long a provider gets to answer `getChildren` before the pane stops
    /// waiting for that answer.
    ///
    /// Settable so a test can reach the timeout without spending it;
    /// production never changes it.
    var childrenBudget: TimeInterval = 30

    /// **Bounded, because the cost of an unbounded wait is not a slow branch.**
    /// `getChildren` is an extension's code — a network call, a subprocess, a
    /// promise nothing ever resolves — and while it is out, `loadingHandles`
    /// holds this handle, which is what stops a second ask. A provider that
    /// never answers therefore does not merely leave the branch empty; it
    /// leaves it *unaskable*, so the branch stays empty after the extension
    /// recovers, after a `refresh()`, and until the window is closed.
    ///
    /// The budget ends the wait and nothing else: no rows are adopted, so the
    /// branch stays unread rather than being recorded as empty, and the next
    /// time the outline asks it is asked again. That is the difference between
    /// a late tree and a broken one *(idempotency — asking again is safe, so
    /// the timeout can simply stop asking)*.
    ///
    /// The `weak self` is not promoted until after the await, which is the
    /// other half: `guard let self` at the top holds the whole pane — outline
    /// view, rows, window — alive for as long as the extension takes, which on
    /// a provider that never answers is forever.
    private func loadChildren(of handle: String) {
        guard !isBeingDiscarded, !loadingHandles.contains(handle) else {
            // A refresh that arrives mid-flight is remembered rather than
            // dropped — see `staleHandles`.
            if loadingHandles.contains(handle) { staleHandles.insert(handle) }
            return
        }
        // A handle whose row has been pruned names a branch that no longer
        // exists; asking for its children would resurrect it.
        guard handle.isEmpty || table.row(for: handle) != nil else { return }
        loadingHandles.insert(handle)
        let parent = handle.isEmpty ? nil : table.row(for: handle)?.item
        let budget = childrenBudget
        Task { [weak self] in
            // The ask goes back through `self` rather than through a captured
            // data source: the source is a reference type an extension owns and
            // is not `Sendable`, so the only place it may be touched is here,
            // on the actor that owns it. `self` is weak throughout — see above.
            let items = try? await withWallClockBudget(budget) { [weak self] in
                await self?.askChildren(of: parent)
            }
            guard let self else { return }
            self.loadingHandles.remove(handle)
            guard let items = items ?? nil else {
                Self.logger.error(
                    "A tree provider did not answer getChildren in time; the branch stays unread")
                // A refresh that arrived while this ask was in flight is still
                // owed an answer, and dropping it was the one path that broke
                // `staleHandles`' promise above. The provider had already
                // fired its change event, so nothing was left to ask again:
                // the branch stayed both unread *and* unasked until something
                // else happened to refresh the whole tree. Bounded, because
                // only an arriving refresh ever sets the flag — a provider
                // that answers nothing and changes nothing is asked once.
                if self.staleHandles.remove(handle) != nil {
                    self.loadChildren(of: handle)
                }
                self.pruneIfSettled()
                return
            }
            guard !self.isBeingDiscarded,
                  handle.isEmpty || self.table.row(for: handle) != nil else {
                self.staleHandles.remove(handle)
                return
            }
            self.adopt(items, under: handle)
            if self.staleHandles.remove(handle) != nil {
                self.loadChildren(of: handle)
            }
            self.pruneIfSettled()
        }
    }

    /// Forgets the rows a refresh dropped, once the refresh is over.
    ///
    /// "Over" is `loadingHandles` being empty: a refresh asks every loaded
    /// branch at once and the answers come back in the extension's order, so
    /// until the last one lands, a row no branch currently claims may simply
    /// belong to a branch that has not answered yet. Pruning per answer is
    /// what made a moved row lose its identity — and therefore its open
    /// disclosure and its whole loaded subtree — depending on which of the two
    /// branches the extension happened to answer for first. See
    /// `ExtensionTreeRowTable.orphanedHandles`.
    ///
    /// After the stale re-ask, not before: a branch whose refresh arrived
    /// mid-flight is about to be asked again, and that ask puts its handle back
    /// into `loadingHandles`.
    private func pruneIfSettled() {
        guard loadingHandles.isEmpty else { return }
        table.pruneOrphans()
    }

    /// Puts a freshly read list of children in place, reusing the row object
    /// for every handle that survived and forgetting the subtrees of those that
    /// did not.
    ///
    /// A row an extension has moved leaves a branch that is still drawing it,
    /// and that branch is nowhere in this reload's path — so `adopt` names it
    /// and it is redrawn too. Doing it first means the outline is never briefly
    /// holding the same row in two places, which is the state it cannot
    /// represent.
    /// The one place the data source is read, so that the read happens on the
    /// actor that owns it rather than inside the budget's `@Sendable` closure.
    private func askChildren(of parent: ContributedTreeItem?) async -> [ContributedTreeItem] {
        await dataSource.children(of: parent)
    }

    private func adopt(_ items: [ContributedTreeItem], under handle: String) {
        let adoption = table.adopt(items, under: handle)
        for displaced in adoption.displacedParents { redraw(displaced) }
        redraw(handle)
    }

    private func redraw(_ handle: String) {
        let selected = selectedHandles()
        isSyncingSelection = true
        isSyncingExpansion = true
        if handle.isEmpty {
            outline.reloadData()
        } else if let row = table.row(for: handle) {
            outline.reloadItem(row, reloadChildren: true)
        }
        isSyncingExpansion = false
        isSyncingSelection = false
        expandDefaults(under: handle)
        restore(selection: selected)
    }

    /// Opens the branches the extension asked to be open, once each.
    private func expandDefaults(under handle: String) {
        for row in table.children(of: handle) ?? []
        where row.item.collapsibleState == .expanded {
            guard table.markAutoExpanded(row.handle) else { continue }
            isSyncingExpansion = true
            outline.expandItem(row)
            isSyncingExpansion = false
        }
    }

    private func selectedHandles() -> [String] {
        outline.selectedRowIndexes.compactMap {
            (outline.item(atRow: $0) as? ExtensionTreeRow)?.handle
        }
    }

    /// Puts the selection back after a reload, as far as the rows still drawn
    /// allow — and tells the extension only if it actually narrowed, which is
    /// the one case where `TreeView.selection` would otherwise name rows that
    /// no longer exist.
    private func restore(selection handles: [String]) {
        guard !handles.isEmpty else { return }
        var indexes = IndexSet()
        for handle in handles {
            guard let row = table.row(for: handle) else { continue }
            let index = outline.row(forItem: row)
            if index >= 0 { indexes.insert(index) }
        }
        isSyncingSelection = true
        outline.selectRowIndexes(indexes, byExtendingSelection: false)
        isSyncingSelection = false
        if indexes.count != handles.count {
            dataSource.selectionDidChange(to: selectedItems())
        }
    }

    private func selectedItems() -> [ContributedTreeItem] {
        outline.selectedRowIndexes.compactMap {
            (outline.item(atRow: $0) as? ExtensionTreeRow)?.item
        }
    }

    /// `onDidChangeTreeData`, with the handle whose subtree moved or `nil` for
    /// the whole tree.
    ///
    /// A whole-tree change re-asks every branch this pane has read rather than
    /// emptying the cache: the rows come back as the same objects, so the user
    /// keeps their disclosure and their place, and a branch nobody has opened
    /// is not asked for at all.
    private func providerDidChangeTreeData(_ handle: String?) {
        guard !isBeingDiscarded else { return }
        if let handle, !handle.isEmpty, table.row(for: handle) != nil {
            loadChildren(of: handle)
            return
        }
        for branch in table.loadedBranches { loadChildren(of: branch) }
        // A pane whose root load has not landed yet holds no branches at all,
        // and the change is exactly the news that it should ask again.
        if table.isEmpty { loadChildren(of: "") }
    }

    // MARK: - Activation

    @objc private func rowDoubleClicked(_ sender: Any?) {
        guard outline.clickedRow >= 0,
              let row = outline.item(atRow: outline.clickedRow) as? ExtensionTreeRow else { return }
        dataSource.activate(row.item)
    }

    /// Return on the selected row, which AppKit delivers one of two ways
    /// depending on whether the table interpreted the key or passed it on —
    /// `insertNewline(_:)` when it interpreted it, a raw `keyDown` when it did
    /// not. Both land on this controller, which is in the responder chain
    /// behind its own view, and both mean the same thing.
    override func insertNewline(_ sender: Any?) {
        activateSelection()
    }

    override func keyDown(with event: NSEvent) {
        // 36 is Return, 76 the keypad's Enter.
        guard event.keyCode == 36 || event.keyCode == 76 else {
            super.keyDown(with: event)
            return
        }
        activateSelection()
    }

    private func activateSelection() {
        guard let row = outline.item(atRow: outline.selectedRow) as? ExtensionTreeRow else { return }
        dataSource.activate(row.item)
    }
}

// MARK: - Outline

extension ExtensionTreeOutlineViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let children = children(of: item)
        // AppKit asks for the count and for each child in separate calls, and
        // an answer landing from the extension in between can shrink the list.
        // That is a stale question rather than a programmer error, so it is
        // answered with a throwaway row instead of a crash — the reload the new
        // answer triggers is already on its way, and this row is gone with it.
        guard children.indices.contains(index) else { return ExtensionTreeRow.placeholder() }
        return children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? ExtensionTreeRow)?.item.collapsibleState.isExpandable ?? false
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let row = notification.userInfo?["NSObject"] as? ExtensionTreeRow,
              !table.hasLoaded(row.handle) else { return }
        loadChildren(of: row.handle)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isSyncingExpansion,
              let row = notification.userInfo?["NSObject"] as? ExtensionTreeRow else { return }
        dataSource.didExpand(row.item)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isSyncingExpansion,
              let row = notification.userInfo?["NSObject"] as? ExtensionTreeRow else { return }
        dataSource.didCollapse(row.item)
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        if let reused = outlineView.makeView(
            withIdentifier: Self.backgroundRowIdentifier, owner: self) as? ThemedTableRowView {
            return reused
        }
        let fresh = ThemedTableRowView()
        fresh.identifier = Self.backgroundRowIdentifier
        return fresh
    }

    /// Recycled rather than built per row, which is what every other outline
    /// and table in this framework does and this one alone did not. A tree is
    /// the shape where it matters most: a branch that opens onto a few hundred
    /// children built a few hundred view hierarchies — each one a stack view,
    /// two labels, an image view and three constraints — for the dozen rows
    /// that fit on screen, and built them all again on every scroll pass, on
    /// the main thread, while the user was dragging the scroller.
    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let row = item as? ExtensionTreeRow else { return nil }
        let rowView = outlineView.makeView(
            withIdentifier: ExtensionTreeRowView.reuseIdentifier, owner: self
        ) as? ExtensionTreeRowView ?? ExtensionTreeRowView()
        rowView.configure(item: row.item, palette: view.resolvedThemeScope.palette)
        return rowView
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSelection else { return }
        dataSource.selectionDidChange(to: selectedItems())
    }
}

// MARK: - Being a pane

extension ExtensionTreeOutlineViewController: PaneTitleProviding {

    var paneTitle: String {
        guard let title = dataSource.title, !title.isEmpty else { return fallbackTitle }
        return title
    }

    var onPaneTitleChange: (() -> Void)? {
        get { onTitleChange }
        set { onTitleChange = newValue }
    }
}

extension ExtensionTreeOutlineViewController: PaneContentTeardown {

    /// Takes the two callbacks back off the data source, which outlives this
    /// pane: the adaptor holds one registration per view id for the life of the
    /// extension, and a closed pane must stop being the thing a refresh talks
    /// to. The tree is also no longer visible, and the extension's
    /// `TreeView.visible` has to say so — `viewDidDisappear` is not guaranteed
    /// for content removed while its window is already gone.
    func paneContentWillBeDiscarded() {
        guard !isBeingDiscarded else { return }
        isBeingDiscarded = true
        // Only this pane's own wiring, and only while it is still this pane's
        // — see `callbackOwners`. The visibility report goes with it: a pane
        // that no longer holds the callbacks is not what `TreeView.visible`
        // describes, and saying the tree went away would be telling the
        // extension about a pane the user stopped looking at long ago.
        let key = ObjectIdentifier(dataSource)
        guard Self.callbackOwners[key] == callbackToken else { return }
        Self.callbackOwners.removeValue(forKey: key)
        dataSource.onDidChangeTreeData = nil
        dataSource.onDidChangeChrome = nil
        dataSource.onProviderReplaced = nil
        dataSource.visibilityDidChange(to: false)
    }
}

// MARK: - Rows

/// One tree row: the icon the item named, its label, and the dimmer description
/// after it.
///
/// Its own type rather than a stack built inline so the three pieces lay out
/// once, and so a row with no icon and a row with one line up with each other
/// — a tree where only some rows have icons is the common case, and ragged
/// labels are what makes it look broken.
@MainActor
private final class ExtensionTreeRowView: NSView {

    /// What `makeView(withIdentifier:owner:)` recycles these under. One
    /// identifier for the whole outline, because every row in it is these same
    /// three pieces in this same order.
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("extension.tree.row")

    private let icon = NSImageView()
    private let label = ThemedLabel(string: "", role: .primaryText, textRole: .body)
    private let caption = ThemedLabel(string: "", role: .tertiaryText, textRole: .caption)

    /// Builds the three pieces and the layout once. Nothing here depends on an
    /// item — that is `configure(item:palette:)`, and the split is what makes
    /// the view reusable.
    init() {
        super.init(frame: .zero)
        identifier = Self.reuseIdentifier

        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        caption.lineBreakMode = .byTruncatingTail
        caption.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [icon, label, caption])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    /// Dresses this view as `item`. Every way one row differs from another is
    /// written here, and nothing is built.
    ///
    /// The icon and the description are *hidden* rather than left out:
    /// `NSStackView` detaches a hidden arranged subview from its layout, so a
    /// row with no icon lays out exactly as one built without an icon did —
    /// which is the alignment this type exists for — and a recycled view
    /// cannot inherit its predecessor's symbol or caption.
    func configure(item: ContributedTreeItem, palette: SemanticPalette) {
        if let symbolName = item.symbolName,
           let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            icon.image = image
            icon.contentTintColor = palette.nsColor(.secondaryText)
            icon.isHidden = false
        } else {
            icon.image = nil
            icon.isHidden = true
        }

        label.stringValue = item.label

        let description = item.description ?? ""
        caption.stringValue = description
        caption.isHidden = description.isEmpty

        // The tooltip, and the label as its own fallback: a truncated row is
        // the one a user most wants to hover, and an item that declared no
        // tooltip would otherwise leave them no way to read it.
        toolTip = item.tooltip ?? item.label
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

extension ExtensionTreeOutlineViewController: Loggable {
    public static nonisolated let logger = makeLogger()
}
