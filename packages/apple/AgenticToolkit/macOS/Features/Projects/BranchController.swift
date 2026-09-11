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

    public init(checkout: ProjectCheckout, gitClient: GitClient) {
        self.checkout = checkout
        self.gitClient = gitClient
        self.statusProvider = GitStatusProvider(repoRoot: checkout.directory, client: gitClient)
        self.currentBranch = checkout.branch
    }

    // MARK: Panes

    /// One pane per edge the tab is drawn on. The controller is the pane's
    /// data source and delegate, so a branch change reloads every pane at once.
    public func makeTabPane(edge: Edge, tabID: UUID) -> TabPaneViewController {
        let pane = TabPaneViewController(edge: edge, tabID: tabID)
        pane.dataSource = self
        pane.delegate = self
        panes.add(pane)
        pane.reload()
        return pane
    }

    public func refresh() async {
        if let branch = try? await gitClient.currentBranch(in: checkout.directory) {
            currentBranch = branch
        }
        for pane in panes.allObjects {
            pane.reload()
        }
    }

    // MARK: Commands

    /// Three commands per checkout, namespaced by `checkout.identifier` so two
    /// worktrees of one repository do not collide on an id.
    ///
    /// The checkout's `displayName` goes in the **category**, not the title.
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
        let category = "Branch — \(checkout.displayName)"
        return [
            AppCommand(
                id: "branch.action.refreshStatus.\(suffix)",
                title: "Refresh Status",
                category: category
            ) { [weak self] in
                self?.statusProvider.refresh { _, _ in }
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
    public func tabPaneSessionName(_ pane: TabPaneViewController) -> String { currentBranch ?? checkout.displayName }
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
            let target = ClosureMenuItemTarget(action: command.run, isEnabled: command.isEnabled)
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
