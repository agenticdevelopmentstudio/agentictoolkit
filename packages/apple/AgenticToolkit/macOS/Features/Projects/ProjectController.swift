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

    /// The reconcile currently running, if any. `open()` and
    /// `refreshCheckouts()` both chain onto this rather than starting their
    /// own work straight away, so two overlapping callers — `open()` from the
    /// window opening and `refreshCheckouts()` from `observeBecameKey` firing
    /// moments later — cannot interleave at the `await` inside
    /// `readCheckouts()` and let whichever's git call happens to finish last
    /// win, even when that is the earlier of the two calls. Chaining onto the
    /// previous `Task` keeps them running one at a time in call order
    /// instead: the second caller's own read only happens once the first's
    /// write has already landed, so the second's write — the later one — is
    /// always the one left standing.
    private var inFlightReconcile: Task<Void, Never>?

    /// Set synchronously, before any `await`, at the top of `shutdown()`.
    /// `reconcile(notify:)` checks it again after its own git call returns,
    /// so a reconcile already in flight when the window closes — the open
    /// scan taking its ~100ms while `observeClose` drops this controller —
    /// bails before persisting tabs or notifying, instead of writing a dead
    /// window's checkouts into the database and asking it to reload. One flag
    /// covers both `open()` and `refreshCheckouts()`, since both funnel
    /// through `serializedReconcile(notify:)`; a stored, cancelled `Task`
    /// handle was the alternative, rejected because it would be a second
    /// lifecycle to keep in step with this one.
    private var isClosed = false

    public init(workspace: ProjectWorkspace, gitClient: GitClient, commandRegistry: CommandRegistry?) {
        self.workspace = workspace
        self.gitClient = gitClient
        self.commandRegistry = commandRegistry
    }

    // MARK: Lifecycle

    public func open() async {
        await serializedReconcile(notify: false)
    }

    public func refreshCheckouts() async {
        await serializedReconcile(notify: true)
    }

    /// Waits for whatever reconcile is already in flight, then runs this
    /// caller's own — see `inFlightReconcile`.
    private func serializedReconcile(notify: Bool) async {
        let previous = inFlightReconcile
        let task = Task {
            _ = await previous?.value
            guard !self.isClosed else { return }
            await self.reconcile(notify: notify)
            guard !self.isClosed else { return }
            for controller in self.branchControllers.values {
                await controller.refresh()
            }
        }
        inFlightReconcile = task
        await task.value
    }

    public func shutdown() async {
        isClosed = true
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
        let freshCheckouts = await readCheckouts()
        // Checked again here, not only at the top of `serializedReconcile`'s
        // task: `readCheckouts()` is the `await` a window close can land
        // inside of, and everything past this point writes — to `checkouts`,
        // to `branchControllers`, and (below) to the database. A close that
        // lands mid-scan must stop here, before any of that runs.
        guard !isClosed else { return }
        checkouts = freshCheckouts
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
        // The root tab stores no working directory, so it falls back to the
        // path the project was opened with — the one path in this system that
        // nothing has resolved. Normalizing it here means every tab's pane
        // reaches its branch controller, and its provider, the same way.
        let directory = (record.workingDirectory ?? workspace.directoryURL).resolvingSymlinksInPath()
        guard let branch = branchController(forDirectory: directory) else {
            return .title(record.title)
        }
        return .viewController(branch.makeTabPane(edge: edge, tabID: record.id))
    }
}

extension ProjectController: Loggable {
    public static nonisolated let logger = makeLogger()
}
