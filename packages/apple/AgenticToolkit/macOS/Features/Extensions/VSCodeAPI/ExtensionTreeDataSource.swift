//
//  ExtensionTreeDataSource.swift
//  AgenticToolkit
//

import Foundation

/// A registered `TreeDataProvider`, as the pane showing it talks to it.
///
/// **The inverse direction of every other seam in this directory.** A webview,
/// a status bar item, a quick pick — each is something the extension *pushes*
/// at the app, so the seam is an `…Presenting` the adaptor calls. A tree is
/// pulled: `getChildren` is asked as rows come into view, is asked again
/// whenever the provider says the tree moved, and is never asked at all for a
/// branch the user never opens. So the protocol is what the pane calls, and
/// the adaptor is the conformer.
///
/// That is also why it is asynchronous. `TreeDataProvider.getChildren` returns
/// `ProviderResult<T[]>` — `T[] | undefined | null | Thenable<…>`
/// (`vscode.d.ts:11361`) — and the thenable case is the common one, since a
/// provider that reads a file or runs a process is the reason a tree exists.
/// An `NSOutlineView` cannot wait, so the pane asks, draws what it has, and
/// redraws when the answer lands.
///
/// One instance per registered view id, held by the adaptor for the extension's
/// lifetime. `AnyObject` because the pane assigns the callbacks below, and a
/// value type would take a copy of the thing it was trying to talk to.
@MainActor
public protocol ExtensionTreeDataSource: AnyObject {

    /// The children of `parent`, or the roots when it is `nil` — upstream's
    /// own signature, where `getChildren()` with no element means the top
    /// (`vscode.d.ts:11361`).
    ///
    /// An empty array for every failure an extension can produce: a provider
    /// that threw, one whose thenable rejected, one that answered a
    /// non-array, and one whose registration has been disposed. The pane
    /// draws an empty branch either way, and the log is where the difference
    /// is recorded — a pane cannot act on the distinction, and a thrown error
    /// surfaced as a row would put an extension's stack trace in a user's
    /// sidebar.
    func children(of parent: ContributedTreeItem?) async -> [ContributedTreeItem]

    /// Runs the `command` the item declared, if it declared one.
    ///
    /// The pane calls this on activation — a double click, or Return on the
    /// selected row — and never on selection alone, because upstream does not:
    /// `TreeItem.command` is documented as running "when the tree item is
    /// selected" but VS Code fires it on the click that selects, not on an
    /// arrow-key move through the tree, and a command per keystroke while
    /// someone navigates is the difference between a tree and a minefield.
    func activate(_ item: ContributedTreeItem)

    /// What the pane calls the view, once `createTreeView` has let an
    /// extension rename it. `nil` while the manifest's name still stands.
    var title: String? { get }

    /// `TreeView.message` (`vscode.d.ts:11294`) — a banner shown *above* the
    /// rows, which is how an extension says "no results", or qualifies the
    /// rows it did answer, without inventing a fake row for it.
    ///
    /// Above and not instead of: upstream renders it in the view with the tree
    /// still under it, and an extension that keeps a standing message —
    /// "showing 10 of 100" — would lose its whole tree to a pane that read this
    /// as a replacement. The one state where there genuinely are no rows
    /// already draws as an empty outline under the sentence explaining it.
    var message: String? { get }

    /// `TreeViewOptions.canSelectMany` (`vscode.d.ts:11238`), which the pane
    /// hands straight to `NSTableView.allowsMultipleSelection`.
    ///
    /// A member rather than a ledger row because honouring it costs one
    /// assignment: an option this host *can* satisfy has no business being
    /// reported as one it cannot (`MainThreadWebviews.parseOptions`' rule).
    var allowsMultipleSelection: Bool { get }

    /// Told that the provider fired `onDidChangeTreeData`, with the element
    /// whose subtree moved, or `nil` for the whole tree.
    ///
    /// Assigned by the pane. The argument is a `ContributedTreeItem.id` — the
    /// handle, not a rebuilt item — because that is all a pane needs to find
    /// the row and ask for its children again, and building an item here would
    /// mean a `getTreeItem` round trip for a row the pane may have already
    /// scrolled away from. An element the pane has never seen arrives as
    /// `nil`, which redraws everything rather than nothing: over-refreshing is
    /// a wasted `getChildren`, while under-refreshing is a tree that silently
    /// stops matching the world.
    var onDidChangeTreeData: ((String?) -> Void)? { get set }

    /// Told that `title`, `message` or `canSelectMany` was written through the
    /// `TreeView` object `createTreeView` returned.
    ///
    /// Separate from `onDidChangeTreeData` because it changes the chrome and
    /// not a single row: a pane that reloaded its outline for a retitle would
    /// collapse every branch the user had opened.
    var onDidChangeChrome: (() -> Void)? { get set }

    /// Told that this source has been retired in favour of `replacement`, and
    /// that the pane should rebind to it.
    ///
    /// The one event that travels *forwards* rather than out to the pane's
    /// own callbacks, and it exists because a pane resolves its data source
    /// exactly once, when its view loads. Nothing re-offers one. An extension
    /// re-registering a provider for a view id it already owns is ordinary —
    /// every deactivate/activate cycle does it, and reloading the host does it
    /// for every view at once — and without this the open pane went on holding
    /// the retired source, which answers no children by design, forever.
    ///
    /// Called *before* the outgoing source is invalidated, so the pane can
    /// hand its callbacks over while both are still live. The replacement
    /// arrives unsubscribed: whoever takes it assigns `onDidChangeTreeData`
    /// and `onDidChangeChrome` on it, including this one again, or the next
    /// replacement has nowhere to go.
    var onProviderReplaced: ((any ExtensionTreeDataSource) -> Void)? { get set }

    /// Tells the provider's `TreeView` object which rows are selected, so
    /// `TreeView.selection` and `onDidChangeSelection` can answer.
    func selectionDidChange(to items: [ContributedTreeItem])

    /// Tells the provider's `TreeView` object whether its pane is on screen,
    /// for `TreeView.visible` and `onDidChangeVisibility`.
    func visibilityDidChange(to isVisible: Bool)

    /// Feeds `TreeView.onDidExpandElement` (`vscode.d.ts:11258`).
    func didExpand(_ item: ContributedTreeItem)

    /// Feeds `TreeView.onDidCollapseElement` (`vscode.d.ts:11263`).
    func didCollapse(_ item: ContributedTreeItem)
}
