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
    /// Fired when — and only when — a reconcile actually wrote new tabs. The
    /// window rebuilds from storage in response, so firing it on a reconcile
    /// that changed nothing would throw away a live pane tree, and every shell
    /// and file-system watcher in it, for no reason at all.
    public var onTabsDidChange: (() -> Void)?

    /// Fired immediately before a reconcile writes, in the same main-actor
    /// turn. The window's debounced focus-persist is the other writer of these
    /// rows and would otherwise land after this write with a stale tab set; the
    /// window cancels it from here. See `cancelPendingTabPersist()`.
    public var onWillChangeTabs: (() -> Void)?

    /// Fired when a reconcile left the stored tabs alone but this controller's
    /// checkouts — and so the answers it gives as a tab-item data source —
    /// changed. The window opened before the first scan finished, so its tab
    /// buttons are the stored titles; this is what tells it they can now be
    /// the real thing. Mutually exclusive with `onTabsDidChange`: one fires on
    /// the path that writes, the other on the path that does not.
    public var onTabItemsNeedRefresh: (() -> Void)?

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

    /// Set by `markClosed()`, which the window's close handler calls
    /// **synchronously**, in the same main-actor turn that drops this
    /// controller. That timing is the whole point: `shutdown()` sets the flag
    /// too, but it is `async`, so reaching it costs a main-actor hop — and a
    /// reconcile continuation already enqueued ahead of that hop would resume
    /// with the flag still down, pass the guard, and write a dead window's
    /// checkouts into the database.
    ///
    /// `reconcile()` checks it again after its own git call returns, so
    /// a reconcile already in flight when the window closes — the open scan
    /// taking its ~100ms while `observeClose` drops this controller — bails
    /// before persisting tabs or notifying. One flag covers both `open()` and
    /// `refreshCheckouts()`, since both funnel through `serializedReconcile()`;
    /// a stored, cancelled `Task` handle was the alternative, rejected because
    /// it would be a second lifecycle to keep in step with this one.
    private(set) var isClosed = false

    public init(workspace: ProjectWorkspace, gitClient: GitClient, commandRegistry: CommandRegistry?) {
        self.workspace = workspace
        self.gitClient = gitClient
        self.commandRegistry = commandRegistry
    }

    // MARK: Lifecycle

    public func open() async {
        await serializedReconcile()
    }

    public func refreshCheckouts() async {
        await serializedReconcile()
    }

    /// Waits for whatever reconcile is already in flight, then runs this
    /// caller's own — see `inFlightReconcile`.
    private func serializedReconcile() async {
        let previous = inFlightReconcile
        let task = Task {
            _ = await previous?.value
            guard !self.isClosed else { return }
            await self.reconcile()
            guard !self.isClosed else { return }
            for controller in self.branchControllers.values {
                await controller.refresh()
            }
        }
        inFlightReconcile = task
        await task.value
    }

    /// Closes this controller to further work, synchronously. Separate from
    /// `shutdown()` because `shutdown()` is `async`: a caller reaching it
    /// through `Task { await … }` gets the flag set one main-actor hop later
    /// than its own turn, which is exactly long enough for a reconcile
    /// continuation enqueued ahead of that hop to resume, find the flag down,
    /// and persist for a window that is already gone.
    ///
    /// It also takes back every branch command. The registry outlives this
    /// controller — it is the app's, not the window's — so a project the user
    /// closed would otherwise keep contributing palette rows that act on its
    /// checkouts for the rest of the process.
    public func markClosed() {
        isClosed = true
        for controller in branchControllers.values {
            unregisterCommands(of: controller)
        }
    }

    /// Re-files any branch command of this controller's that has gone missing
    /// from the registry.
    ///
    /// Every command id is derived from `checkout.identifier`, a hash of the
    /// resolved directory path and nothing else, so two project windows over
    /// the same repository mint *identical* ids — and `readCheckouts()` makes
    /// that routine rather than exotic, because it derives from `git worktree
    /// list`, which answers the same worktree set for any subdirectory of one
    /// repository. The registry is the app's, so the second window to open
    /// replaced the first's entries, and the first window to close took them
    /// back out from under whoever was still using them. `syncBranchControllers()`
    /// only registers for a controller it just created, so nothing there ever
    /// noticed: the surviving window's palette lost those rows for good.
    ///
    /// Called by `ProjectWindowManager` after a sibling window closes. Ids that
    /// are still registered are left alone, so the common case — no overlap —
    /// costs a dictionary lookup per command and logs nothing.
    public func reregisterCommands() {
        guard !isClosed, let commandRegistry else { return }
        for controller in branchControllers.values {
            for command in controller.commands where commandRegistry.command(id: command.id) == nil {
                commandRegistry.register(command)
            }
        }
    }

    public func shutdown() async {
        markClosed()
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
    ///
    /// The two callbacks bracket that write and fire only on the path that
    /// actually takes it: everything downstream — the window throwing its pane
    /// tree away and rebuilding it, the window cancelling its own pending
    /// write — is wasted or harmful work when the stored tabs already say what
    /// this reconcile was going to write.
    private func reconcile() async {
        let freshCheckouts = await readCheckouts()
        // Checked again here, not only at the top of `serializedReconcile`'s
        // task: `readCheckouts()` is the `await` a window close can land
        // inside of, and everything past this point writes — to `checkouts`,
        // to `branchControllers`, and (below) to the database. A close that
        // lands mid-scan must stop here, before any of that runs.
        guard !isClosed else { return }
        let previousCheckouts = checkouts
        checkouts = freshCheckouts
        syncBranchControllers()

        let stored = workspace.storedTabs()
        let plan = ProjectTabReconciler.plan(
            stored: stored?.tabs ?? [],
            checkouts: checkouts,
            projectDirectory: workspace.directoryURL
        )
        guard stored == nil || !plan.isUnchanged else {
            // The stored tabs already say what this reconcile would have
            // written, so nothing is persisted and the window keeps its panes.
            // Its tab *buttons* are another matter: the window installed them
            // before this scan finished, when this controller had no checkouts
            // and could only answer `.title`. Now that it can answer properly,
            // the buttons — and only the buttons — are rebuilt.
            if previousCheckouts != checkouts { onTabItemsNeedRefresh?() }
            return
        }

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
        onWillChangeTabs?()
        workspace.persistTabs(tabs, activeTabID: activeTabID, enabledEdges: enabledEdges)
        onTabsDidChange?()
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
    /// controller here *and* its commands: `git worktree remove` deletes the
    /// directory those commands act on, so leaving them registered leaves a
    /// palette row that reveals a folder which no longer exists.
    ///
    /// Dropping out is decided by directory, matching the reuse lookup above:
    /// a checkout that merely switched branch is a different `ProjectCheckout`
    /// (it hashes on `branch`) reached through the same controller, and must
    /// not be mistaken for one that went away.
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
        let keptDirectories = Set(next.keys.map(\.directory))
        for (checkout, controller) in branchControllers where !keptDirectories.contains(checkout.directory) {
            unregisterCommands(of: controller)
        }
        branchControllers = next
        workspace.gitStatusProviderResolver = { [weak self] directory in
            self?.branchController(forDirectory: directory)?.statusProvider
        }
    }

    /// `commands` is computed, but every id in it is derived from
    /// `checkout.identifier` — a hash of the resolved directory path — so the
    /// ids a controller unregisters are exactly the ones it registered, even
    /// after a branch switch.
    private func unregisterCommands(of controller: BranchController) {
        for command in controller.commands {
            commandRegistry?.unregister(id: command.id)
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
