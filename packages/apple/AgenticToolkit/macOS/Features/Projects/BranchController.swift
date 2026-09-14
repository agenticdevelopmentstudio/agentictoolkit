import AgenticToolkitCore
import AppKit

/// Owns one checkout: its status provider, its current branch, the commands
/// that act on it and the tab panes that describe it. Vended by
/// `ProjectController`; never touches the window.
@MainActor
public final class BranchController: TabPaneDataSource, TabPaneDelegate {
    public let checkout: ProjectCheckout
    public let statusProvider: GitStatusProvider
    public private(set) var currentBranch: String?

    private let gitClient: GitClient
    private let panes = NSHashTable<TabPaneViewController>.weakObjects()

    /// The provider is handed in, not built here (`dependency-injection`). A
    /// checkout's panes are built before this controller exists — the window
    /// installs its stored tabs while the first `git worktree list` is still
    /// running — so a provider minted here could never be the one those panes
    /// were given, and the checkout would end up with two: one painting the
    /// badges, one answering `Refresh Status`. The project owns the per-
    /// directory cache both sides ask; see
    /// `ProjectWorkspace.gitStatusProvider(forDirectory:)`.
    public init(checkout: ProjectCheckout, gitClient: GitClient, statusProvider: GitStatusProvider) {
        self.checkout = checkout
        self.gitClient = gitClient
        self.statusProvider = statusProvider
        self.currentBranch = checkout.branch
    }

    // MARK: Panes

    /// One pane per edge the tab is drawn on. The controller is the pane's
    /// data source and delegate, so a branch change reloads every pane at once.
    ///
    /// One pane per *(tab, edge)* for the life of that tab, too — the name says
    /// "make", but a caller asking twice for the same tab's item is asking the
    /// same question. `refreshTabItems()` asks for every tab on every checkout
    /// scan and every branch refresh, so minting a new controller each time
    /// built and threw away a view controller per tab per edge per scan, and
    /// left the discarded ones in `panes` to be reloaded alongside the live
    /// ones until AppKit got around to releasing them.
    ///
    /// The lookup is a linear scan of a table that holds one entry per visible
    /// tab — a handful of pointer comparisons against building a view
    /// controller.
    public func makeTabPane(edge: Edge, tabID: UUID) -> TabPaneViewController {
        if let existing = panes.allObjects.first(where: { $0.edge == edge && $0.tabID == tabID }) {
            existing.reload()
            return existing
        }
        let pane = TabPaneViewController(edge: edge, tabID: tabID)
        pane.dataSource = self
        pane.delegate = self
        panes.add(pane)
        pane.reload()
        return pane
    }

    /// What this checkout is called *now*.
    ///
    /// `checkout` is the snapshot this controller was built from and never
    /// moves — it is a `let`, and deliberately so: `identifier` is
    /// path-derived precisely so a checkout keeps its identity across branch
    /// switches. But `displayName` is not identity, it is a label, and a
    /// label read off that frozen snapshot went on naming the branch that
    /// happened to be checked out when the window opened. `currentBranch` is
    /// re-read on every `refresh()`, so everything a user reads — the command
    /// palette's category, a pane's session name — comes from here instead.
    public var displayName: String {
        currentBranch ?? checkout.directory.lastPathComponent
    }

    /// Re-reads the branch and reloads every pane.
    ///
    /// A detached HEAD is an *answer*: `currentBranch(in:)` returns `nil` for
    /// it, and that `nil` must replace whatever name was there. A thrown error
    /// is not an answer — git could not be asked, so the last known branch
    /// stays put, the same policy `GitStatusProvider` applies to a failed
    /// status. Folding both into one `try?` kept a stale branch name on screen
    /// forever, because the two cases are indistinguishable once the error is
    /// discarded.
    public func refresh() async {
        do {
            currentBranch = try await gitClient.currentBranch(in: checkout.directory)
        } catch {
            // Deliberately left in place; the failed call is in GitCommandLog.
        }
        for pane in panes.allObjects {
            pane.reload()
        }
    }

    // MARK: Commands

    /// Three commands per checkout, namespaced by `checkout.identifier` so two
    /// worktrees of one repository do not collide on an id.
    ///
    /// The checkout's live `displayName` goes in the **category**, not the title.
    /// Ids are namespaced but never shown: a command palette renders a row as
    /// title + category, so with a bare "Branch" a two-worktree project offered
    /// six rows reading "Refresh Status — Branch" and the user picking one got
    /// a coin flip over which directory it acted on. The title is what the
    /// per-pane context menu renders — alone, inside a pane that already says
    /// which checkout it is — so putting the name there would repeat it in the
    /// one place it is already known.
    ///
    /// `revealInFinder` and `copyPath` capture `directory` by value rather than
    /// reaching through `self`, so an unregister that races a menu already on
    /// screen still does the right thing rather than silently nothing.
    public var commands: [AppCommand] {
        let suffix = checkout.identifier
        let directory = checkout.directory
        let category = "Branch — \(displayName)"
        return [
            AppCommand(
                id: "branch.action.refreshStatus.\(suffix)",
                title: "Refresh Status",
                category: category
            ) { [weak self] in
                // The provider broadcasts to everything watching this
                // checkout, so asking it is all this command has to do: every
                // file browser on the checkout repaints its badges. It used to
                // pass a completion that discarded the result, which under the
                // old one-request-wins provider also cancelled the refresh a
                // pane was genuinely waiting on.
                self?.statusProvider.refresh()
                Task { [weak self] in await self?.refresh() }
            },
            AppCommand(
                id: "branch.action.revealInFinder.\(suffix)",
                title: "Reveal in Finder",
                category: category
            ) {
                NSWorkspace.shared.activateFileViewerSelecting([directory])
            },
            AppCommand(
                id: "branch.action.copyPath.\(suffix)",
                title: "Copy Path",
                category: category
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(directory.path, forType: .string)
            }
        ]
    }

    // MARK: TabPaneDataSource

    /// Placeholders until an agent is attached to the tab: the design names
    /// "Claude", no model, and an idle moon. Real values arrive with the
    /// document-model work that follows the vsc-plugins branch.
    public func tabPaneAgentName(_ pane: TabPaneViewController) -> String { "Claude" }
    public func tabPaneModelName(_ pane: TabPaneViewController) -> String? { nil }
    public func tabPaneStatusSymbols(_ pane: TabPaneViewController) -> [TabPaneStatusSymbol] { [.idle] }
    public func tabPaneSessionName(_ pane: TabPaneViewController) -> String { displayName }
    public func tabPaneWorkingDirectory(_ pane: TabPaneViewController) -> URL { checkout.directory }
    public func tabPaneBranch(_ pane: TabPaneViewController) -> String? { currentBranch }
    public func tabPaneSummary(_ pane: TabPaneViewController) -> String? { nil }

    // MARK: TabPaneDelegate

    /// Reuses the toolkit's own `ClosureMenuItemTarget` rather than a
    /// hand-rolled `@objc` action, so enablement goes through
    /// `validateMenuItem(_:)` — the path `NSMenu.autoenablesItems` (default
    /// `true`) actually consults, instead of an `item.isEnabled` AppKit would
    /// silently discard.
    ///
    /// `NSMenuItem.target` is **weak**, so the target must also be retained
    /// somewhere with the item's lifetime; `representedObject` is that
    /// somewhere. Losing this retention does not fail loudly — it leaves
    /// every item silently inert once its target is deallocated.
    public func tabPane(_ pane: TabPaneViewController, contextMenuFor event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for command in commands {
            // `AppCommand.run` is `([Any]) -> Any?`; a menu item has no arguments
            // to deliver and nothing to resolve with, so it passes none and
            // discards the answer — the same adaptation `AppCommand`'s
            // `() -> Void` initializer makes for every other call site.
            let target = ClosureMenuItemTarget(
                action: { _ = command.run([]) },
                isEnabled: command.isEnabled
            )
            let item = NSMenuItem(
                title: command.title,
                action: #selector(ClosureMenuItemTarget.performMenuAction(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = target
            menu.addItem(item)
        }
        return menu
    }
}
