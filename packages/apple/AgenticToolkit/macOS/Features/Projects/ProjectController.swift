import AgenticToolkitCore
import AppKit
import os

/// One per project window. Owns the project's checkouts and their branch
/// controllers, decides which tabs the window shows, and answers the window
/// controller's tab-item requests. Knows nothing about views beyond vending
/// what a branch controller makes.
@MainActor
public final class ProjectController: ComposableTabsTabItemDataSource {
    public let workspace: ProjectWorkspace
    public private(set) var checkouts: [ProjectCheckout] = []
    public private(set) var branchControllers: [ProjectCheckout: BranchController] = [:]
    public var onTabsDidChange: (() -> Void)?

    private let gitClient: GitClient
    private let commandRegistry: CommandRegistry?

    public init(workspace: ProjectWorkspace, gitClient: GitClient, commandRegistry: CommandRegistry?) {
        self.workspace = workspace
        self.gitClient = gitClient
        self.commandRegistry = commandRegistry
    }

    // MARK: Lifecycle

    public func open() async {
        await reconcile(notify: false)
        for controller in branchControllers.values {
            await controller.refresh()
        }
    }

    public func refreshCheckouts() async {
        await reconcile(notify: true)
        for controller in branchControllers.values {
            await controller.refresh()
        }
    }

    public func shutdown() async {
        await workspace.languageServices?.shutdown()
    }

    /// Resolved before comparison, matching `ProjectCheckout.init` and
    /// `ProjectTabReconciler.plan`: a checkout's directory came from `git
    /// worktree list` and is stored resolved, while `directory` here may be
    /// whatever a caller had lying around, so an unresolved symlink on either
    /// side would turn a real match into a miss.
    public func branchController(forDirectory directory: URL) -> BranchController? {
        let directory = directory.resolvingSymlinksInPath()
        return branchControllers.first { $0.key.directory == directory }?.value
    }

    // MARK: Reconciliation

    /// Re-reads the checkouts, keeps the branch controllers in step, then
    /// brings the stored tabs in line with what is on disk. Persists only when
    /// something changed or nothing was stored, so an unchanged reopen leaves
    /// the database and the window alone.
    private func reconcile(notify: Bool) async {
        checkouts = await readCheckouts()
        syncBranchControllers()

        let stored = workspace.storedTabs()
        let plan = ProjectTabReconciler.plan(
            stored: stored?.tabs ?? [],
            checkouts: checkouts,
            projectDirectory: workspace.directoryURL
        )
        guard stored == nil || !plan.isUnchanged else { return }

        let enabledEdges = stored?.enabledEdges ?? [.top]
        var tabs = plan.keep
        for checkout in plan.add {
            tabs += ProjectTabReconciler.makeRecords(
                for: checkout,
                enabledEdges: enabledEdges,
                blueprint: workspace.layout.blueprint
            )
        }
        let activeTabID = tabs.first { $0.id == stored?.activeTabID }?.id ?? tabs.first?.id
        workspace.persistTabs(tabs, activeTabID: activeTabID, enabledEdges: enabledEdges)
        if notify {
            onTabsDidChange?()
        }
    }

    /// The repository's own checkout first. When git answers with no
    /// worktrees at all (no executable, not a repository) the project
    /// directory is the one checkout. A transient failure is different from
    /// that: it keeps whatever the last successful read produced rather than
    /// collapsing to the single-project fallback, so a `BranchController`
    /// this controller already handed out (and a pane that may still be
    /// showing it) does not get silently dropped and re-created on the very
    /// next reconcile because one `git worktree list` call hiccupped.
    private func readCheckouts() async -> [ProjectCheckout] {
        do {
            let worktrees = try await gitClient.worktrees(in: workspace.directoryURL)
            let found = ProjectCheckout.checkouts(from: worktrees)
            guard !found.isEmpty else {
                return [ProjectCheckout(directory: workspace.directoryURL, branch: nil, isMain: true)]
            }
            // `sorted(by:)` is documented as not guaranteed stable, so a
            // comparator that only orders main-before-non-main would not
            // reliably keep the non-main checkouts in git's own order.
            // Partition instead: git's order survives within each half.
            return found.filter(\.isMain) + found.filter { !$0.isMain }
        } catch {
            // What failed and where, never the git output itself (which may
            // land in `GitClientError.commandFailed`'s `standardError`).
            let directory = self.workspace.directoryURL.path
            Self.logger.error(
                "readCheckouts: worktrees(in:) failed for \(directory, privacy: .public); keeping last checkouts"
            )
            return checkouts.isEmpty
                ? [ProjectCheckout(directory: workspace.directoryURL, branch: nil, isMain: true)]
                : checkouts
        }
    }

    /// Keeps one `BranchController` per current checkout, reusing an existing
    /// one (by directory, since `ProjectCheckout` also hashes on `branch`, and
    /// a checkout that switched branch must still find its controller) rather
    /// than rebuilding it. A checkout that drops out of `checkouts` drops its
    /// controller here too, but `CommandRegistry` has no unregister: that
    /// controller's commands stay registered, acting on a directory that is
    /// now gone, until the app relaunches.
    private func syncBranchControllers() {
        var next: [ProjectCheckout: BranchController] = [:]
        for checkout in checkouts {
            let existing = branchControllers.first { $0.key.directory == checkout.directory }?.value
            let controller = existing ?? BranchController(checkout: checkout, gitClient: gitClient)
            next[checkout] = controller
            if existing == nil {
                for command in controller.commands {
                    commandRegistry?.register(command)
                }
            }
        }
        branchControllers = next
        workspace.gitStatusProviderResolver = { [weak self] directory in
            self?.branchController(forDirectory: directory)?.statusProvider
        }
    }

    // MARK: ComposableTabsTabItemDataSource

    public func composableTabsWindowController(
        _ controller: ComposableTabsWindowController,
        tabItemFor record: TabRecord,
        on edge: Edge
    ) -> TabItem {
        let directory = record.workingDirectory ?? workspace.directoryURL
        guard let branch = branchController(forDirectory: directory) else {
            return .title(record.title)
        }
        return .viewController(branch.makeTabPane(edge: edge, tabID: record.id))
    }
}

extension ProjectController: Loggable {
    public static nonisolated let logger = makeLogger()
}
