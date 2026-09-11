import AppKit
import Combine
import os
import AgenticToolkitCore

/// Keeps one window per project, keyed by `git_repo.id`.
///
/// The key is the row id and not the path, so opening "the same project" twice
/// means the same window even after the repository has been moved or renamed —
/// which is the whole reason the registry has ids in the first place.
@MainActor
public final class ProjectWindowManager: ProjectOpening, ObservableObject {

    public static let shared = ProjectWindowManager()

    /// `project_setting` key marking a project whose window was open when the
    /// app last quit. It lives with the project row rather than in app
    /// preferences so it cascades away with the project — a forgotten registry
    /// row can't leave a "reopen me" behind pointing at nothing.
    ///
    /// Internal rather than private so a test asserting what a close does *not*
    /// write names the same key the writer does, instead of a literal that can
    /// drift away from it silently.
    static let openWindowKey = "window.open"

    private var controllers: [UUID: ComposableTabsWindowController] = [:]

    /// Language-service shutdowns started by a window close, still running.
    /// The controller is out of `controllers` by then, so
    /// `shutdownAllLanguageServices()` cannot find it there; this is the
    /// handle that lets the quit path wait for it anyway. See
    /// `PendingTeardowns`.
    private let closeTeardowns = PendingTeardowns()

    /// The order projects were opened in.
    ///
    /// `controllers` is a `Dictionary`, whose value order is seeded per
    /// process; scripting enumerates windows, tabs and panes through this, and
    /// a script that lists `panes` twice must get the same order twice.
    private var openOrder: [UUID] = []

    /// Which projects have a window open right now, so anything outside a
    /// project window can follow projects opening and closing — the language
    /// server settings panel lists one section per open project, and a
    /// language server exists only inside one.
    ///
    /// Ids rather than workspaces. `openWorkspaces` is still the accessor for
    /// the values, and it reads them out of the controllers; publishing the
    /// workspaces instead would put a `@Published` array of them beside the
    /// controllers that own them, and a subscriber holding the last emission
    /// would then keep a closed project's workspace — and the language servers
    /// hanging off it — alive past its window.
    ///
    /// Derived from `openOrder` and `controllers` at every mutation rather
    /// than maintained alongside them, so the three cannot drift — and in
    /// `openOrder`'s order, because a subscriber that renders one section per
    /// open project must not have them rearrange themselves on the next
    /// unrelated open or close. `closeProject` is not one of
    /// those sites: it only asks the window to close, and the removal happens
    /// in the `willCloseNotification` observer below, which is also the path a
    /// user clicking the red button takes.
    @Published public private(set) var openWorkspaceIDs: [UUID] = []
    private var closeObservers: [UUID: NSObjectProtocol] = [:]

    /// The projects registered by `adoptForScripting(_:)` rather than opened
    /// here. Membership is what `forgetForScripting(_:)` checks, because the
    /// two registrations are not interchangeable: an adopted window's observer
    /// only unregisters it, while an opened window's observer also clears the
    /// persisted "reopen me" flag. Tearing the second one down through the
    /// undo of the first would leave the project reopening for ever.
    private var adoptedForScripting: Set<UUID> = []
    private weak var coordinator: ProjectsCoordinator?

    /// One `ProjectController` per open window, keyed the same way
    /// `controllers` is. Built in `openProject(_:)`, dropped in
    /// `observeClose(of:repoID:recordsOpenState:)`.
    private var projectControllers: [UUID: ProjectController] = [:]

    /// `NSWindow.didBecomeKeyNotification` observers installed by
    /// `observeBecameKey(of:repoID:)`, one per open window, so a worktree
    /// added or removed in a terminal shows up without a relaunch.
    private var keyObservers: [UUID: NSObjectProtocol] = [:]

    /// Injected so tests run against a throwaway client and hosts can share
    /// one rather than each `ProjectController` reaching for `GitClient.shared`
    /// on its own (`dependency-injection`).
    public var gitClient: GitClient = .shared

    /// Where each project's branch commands are registered. `nil` registers
    /// nothing — the configuration every test that does not ask for commands
    /// already runs in.
    public var commandRegistry: CommandRegistry?

    /// Builds the language-server stack for a project about to be opened, given
    /// its directory. Set once by the host at startup; `nil` in a host that
    /// wants no language support, and in every test that has not asked for it.
    ///
    /// A closure rather than a stored `TextDocumentStore` + settings pair
    /// because this type has no business knowing what a registry needs — the
    /// host already owns the app-wide document store and the settings, and this
    /// only has to know *when* to ask (`dependency-injection`).
    public var languageServicesFactory: (@MainActor (URL) -> ProjectLanguageServices)?

    public init() {}

    /// Wires the manager to the registry it opens projects from and registers
    /// itself as that registry's opener.
    public func attach(to coordinator: ProjectsCoordinator) {
        self.coordinator = coordinator
        coordinator.setOpener(self)
    }

    /// The frontmost project window, for anything that acts on "the current
    /// project" — menu validation, the scripting bridge.
    public var frontWindowController: ComposableTabsWindowController? {
        if let key = NSApp.keyWindow?.windowController as? ComposableTabsWindowController {
            return key
        }
        return NSApp.orderedWindows
            .compactMap { $0.windowController as? ComposableTabsWindowController }
            .first
    }

    /// Every open project's workspace, in the order their projects were
    /// opened — the same order as `openWindowControllers` below, and read out
    /// of the same two sources.
    public var openWorkspaces: [ProjectWorkspace] {
        openOrder.compactMap { controllers[$0]?.project }
    }

    /// Every open project window, in the order their projects were opened.
    public var openWindowControllers: [ComposableTabsWindowController] {
        openOrder.compactMap { controllers[$0] }
    }

    /// Republishes `openWorkspaceIDs` from the one ordering this type keeps.
    ///
    /// Every site that adds to or removes from `controllers` calls this, so
    /// the published ids, `openWorkspaces` and `openWindowControllers` are
    /// three views of the same pair — `openOrder` for the order, `controllers`
    /// for membership — and cannot disagree about either. Filtering through
    /// `controllers` rather than publishing `openOrder` itself keeps the
    /// membership answer in the dictionary alone: an id that outlives its
    /// controller is not open.
    private func refreshOpenWorkspaceIDs() {
        openWorkspaceIDs = openOrder.filter { controllers[$0] != nil }
    }

    /// Registers a window this manager did not open, so scripting can see it.
    /// Idempotent — adopting twice leaves one entry.
    ///
    /// For a host that builds a project window itself, and for the tests: the
    /// scripting surface is "which project windows are open", and a window this
    /// manager never opened is still open (`principle-of-least-astonishment`).
    ///
    /// Adoption undoes itself when the window closes, so a host that adopts and
    /// then forgets to unregister still cannot leave `openWindowControllers`
    /// naming a window that is gone — or leave `openProject(_:)` re-showing a
    /// dead controller. `forgetForScripting(_:)` is for undoing it *sooner*
    /// than that, not for making the close safe.
    ///
    /// It deliberately does not touch the persisted open flag, in either
    /// direction: that flag drives `restoreOpenProjects()`, and a window this
    /// manager never opened is not one it may decide should not reopen.
    public func adoptForScripting(_ controller: ComposableTabsWindowController) {
        let id = controller.project.id
        guard controllers[id] == nil else { return }
        controllers[id] = controller
        openOrder.append(id)
        refreshOpenWorkspaceIDs()
        adoptedForScripting.insert(id)
        observeClose(of: controller, repoID: id, recordsOpenState: false)
    }

    /// The undo of `adoptForScripting(_:)`, and only of that. Guarded on
    /// identity, so forgetting a stale controller cannot evict the live window
    /// that replaced it, and guarded on *how* the controller was registered,
    /// so it cannot undo an `openProject(_:)`: that registration owns the
    /// observer which clears the persisted open flag on close, and removing it
    /// would leave the project marked open for ever and reopening at every
    /// launch. A controller this manager opened is silently left alone —
    /// there is nothing here for the caller to undo.
    ///
    /// It takes the adoption's close observer with it, so the eager undo leaks
    /// no more than the automatic one does.
    public func forgetForScripting(_ controller: ComposableTabsWindowController) {
        let id = controller.project.id
        guard controllers[id] === controller, adoptedForScripting.contains(id) else { return }
        controllers.removeValue(forKey: id)
        openOrder.removeAll { $0 == id }
        refreshOpenWorkspaceIDs()
        adoptedForScripting.remove(id)
        if let observer = closeObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func windowController(for repoID: UUID) -> ComposableTabsWindowController? {
        controllers[repoID]
    }

    /// The project controller behind a window this manager opened. `nil` for
    /// a repo with no window, and for a window `adoptForScripting(_:)` merely
    /// registered — those are built and owned by whoever adopted them.
    public func projectController(for repoID: UUID) -> ProjectController? {
        projectControllers[repoID]
    }

    /// Whether a `NSWindow.didBecomeKeyNotification` observer is still
    /// registered for `repoID`. Internal, not `public`, and reached only
    /// through `@testable import` — the sole consumer is a test proving that
    /// closing a window's observer is actually gone, not merely unreachable
    /// because `projectControllers[repoID]` already went with it.
    func hasKeyObserver(for repoID: UUID) -> Bool {
        keyObservers[repoID] != nil
    }

    // MARK: - ProjectOpening

    public func openProject(_ repo: GitRepo) {
        if let existing = controllers[repo.id] {
            existing.project.update(repo: repo)
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        guard let database = coordinator?.database else {
            Self.logger.error("Cannot open \(repo.name, privacy: .public): no project database attached")
            return
        }
        let languageServices = languageServicesFactory?(repo.url)
        if languageServices == nil {
            // Info, not a warning: a host with no language-server wiring is a
            // supported configuration, and this is the one line that tells a
            // reader of the log why a window has no completions.
            Self.logger.info(
                "No language services for \(repo.name, privacy: .public): no factory wired"
            )
        }
        let workspace = ProjectWorkspace(repo: repo, database: database, languageServices: languageServices)
        languageServices?.start()
        let projectController = ProjectController(
            workspace: workspace,
            gitClient: gitClient,
            commandRegistry: commandRegistry
        )
        projectControllers[repo.id] = projectController
        let controller = ComposableTabsWindowController(project: workspace)
        controller.tabItemDataSource = projectController
        projectController.onTabsDidChange = { [weak controller] in controller?.reloadTabs() }
        controllers[repo.id] = controller
        openOrder.append(repo.id)
        refreshOpenWorkspaceIDs()
        controller.showWindow(nil)
        // `makeKeyAndOrderFront(nil)` runs before `observeBecameKey` is
        // installed below, so whether this window's own *initial* key
        // notification is seen by that observer is left to AppKit timing.
        // That is deliberately not guarded against: `reconcile(notify:)`
        // early-returns on `plan.isUnchanged` before ever calling
        // `onTabsDidChange?()`, so a redundant refresh this ordering might
        // let through costs one `git worktree list` and no rebuild — not
        // worth reordering two calls whose relative order is otherwise
        // arbitrary.
        controller.window?.makeKeyAndOrderFront(nil)
        observeClose(of: controller, repoID: repo.id, recordsOpenState: true)
        observeBecameKey(of: controller, repoID: repo.id)
        // The window is on screen with whatever tabs were stored; the checkout
        // scan runs git, so it is a task, and the window reloads when it lands.
        //
        // Ruling Q: `projectController` is captured strongly, so it outlives
        // its removal from `projectControllers` if the window closes mid-scan
        // — `ProjectController`'s own closed flag (set synchronously by
        // `markClosed()`, in the close handler's own turn) stops that from
        // persisting a dead window's tabs, but
        // this call site is outside `ProjectController` entirely, so it needs
        // its own guard: only reload when this controller is still the one
        // registered for `repo.id`, so a resurrected or replaced controller
        // can never drive a window that is no longer its own.
        Task { [weak self, weak controller] in
            await projectController.open()
            guard let self, self.projectControllers[repo.id] === projectController else { return }
            controller?.reloadTabs()
        }
        setWindowOpen(true, repoID: repo.id)
    }

    public func closeProject(repoID: UUID) {
        controllers[repoID]?.close()
    }

    // MARK: - Termination

    /// Shuts down every open project's language servers, concurrently.
    ///
    /// A task group rather than a `for` loop over `await`: each
    /// `LanguageServerSession.stop()` bottoms out in
    /// `SubprocessChannel.terminate()`, which is uncancellable and waits up to
    /// 2.5 seconds for a child that ignores SIGTERM. Those budgets do not
    /// share — five stubborn servers run sequentially is twelve seconds of a
    /// beachball on quit, and run concurrently is still two and a half.
    ///
    /// Called from `ProjectsCoordinator.terminate()`, which the host's
    /// termination sweep already awaits. The per-window path in
    /// `observeClose(of:repoID:)` covers the ordinary case; this covers quitting
    /// with windows still open, where no `willClose` shutdown has run yet.
    public func shutdownAllLanguageServices() async {
        let services = controllers.values.compactMap(\.project.languageServices)
        await withTaskGroup(of: Void.self) { group in
            for service in services {
                group.addTask { await service.shutdown() }
            }
        }
        // A project whose window closed moments ago is not in `controllers`
        // any more, and its shutdown may still be inside
        // `SubprocessChannel.terminate()`'s ~2.5 s budget. Close a window and
        // press Cmd-Q and the loop above finds nothing to wait for; without
        // this the process exits and takes the detached teardown with it,
        // leaving an orphaned language server behind. The early `guard` that
        // used to stand above the loop is gone for the same reason: "no open
        // windows" is not "nothing to wait for".
        await closeTeardowns.drain()
    }

    // MARK: - Restore

    /// Reopens every project whose window was open when the app last quit.
    /// Hosts call this once at launch, after the registry exists.
    ///
    /// Deliberately not routed through `ProjectsCoordinator.openProject(_:)`:
    /// restoring a window is not the user opening a project, and must not
    /// rewrite `lastOpened` and re-sort the browser on every launch.
    ///
    /// A project window is the app's workspace, not a document, so this does
    /// not consult `reopenOnLaunchPolicy` — that setting governs the recent-
    /// documents reopen in `WindowManager`. Closing the window is how you tell
    /// this to stop reopening it.
    public func restoreOpenProjects() {
        guard let coordinator else { return }
        let plan = Self.restorePlan(
            repos: coordinator.repos,
            wasOpen: { [weak self] in self?.isWindowOpen(repoID: $0.id) ?? false },
            existsOnDisk: { FileManager.default.fileExists(atPath: $0.path) }
        )
        for repo in plan.forget {
            Self.logger.info("Not reopening \(repo.name, privacy: .public): its folder is gone")
            setWindowOpen(false, repoID: repo.id)
        }
        for repo in plan.reopen {
            openProject(repo)
        }
    }

    /// Which of the projects flagged open at quit are worth reopening, and
    /// which should have the flag cleared instead.
    ///
    /// A folder deleted or renamed since the last run would reopen as a
    /// workspace with an empty tree and a terminal in `/` — a window that looks
    /// broken rather than absent. Deleting the row is the scan's job; restore
    /// only declines to resurrect it, and forgets the flag so it stops trying
    /// every launch.
    ///
    /// Pure, so the rule can be tested without opening a window.
    static func restorePlan(
        repos: [GitRepo],
        wasOpen: (GitRepo) -> Bool,
        existsOnDisk: (GitRepo) -> Bool
    ) -> (reopen: [GitRepo], forget: [GitRepo]) {
        let open = repos.filter(wasOpen)
        return (open.filter(existsOnDisk), open.filter { !existsOnDisk($0) })
    }

    private func isWindowOpen(repoID: UUID) -> Bool {
        guard let database = coordinator?.database else { return false }
        do {
            return try database.setting(repoID: repoID, key: Self.openWindowKey) == "1"
        } catch {
            Self.logger.error("Could not read window state for \(repoID.uuidString, privacy: .public): \(error)")
            return false
        }
    }

    private func setWindowOpen(_ isOpen: Bool, repoID: UUID) {
        guard let database = coordinator?.database else { return }
        do {
            try database.setSetting(repoID: repoID, key: Self.openWindowKey, value: isOpen ? "1" : nil)
        } catch {
            Self.logger.error("Could not record window state for \(repoID.uuidString, privacy: .public): \(error)")
        }
    }

    /// Re-reads worktrees when the window comes back to the front, so a
    /// worktree added or removed in a terminal shows up without a relaunch.
    private func observeBecameKey(of controller: ComposableTabsWindowController, repoID: UUID) {
        guard let window = controller.window else { return }
        keyObservers[repoID] = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let projectController = self?.projectControllers[repoID] else { return }
                Task { await projectController.refreshCheckouts() }
            }
        }
    }

    /// Drops the controller when its window closes, so reopening the project
    /// builds a fresh window rather than resurrecting a closed one.
    ///
    /// - Parameter recordsOpenState: whether the close should also clear the
    ///   persisted "reopen this next launch" flag. True for a window this
    ///   manager opened; false for one it merely adopted, whose open state is
    ///   not its to decide. The deregistration itself happens either way.
    private func observeClose(
        of controller: ComposableTabsWindowController,
        repoID: UUID,
        recordsOpenState: Bool
    ) {
        guard let window = controller.window else { return }
        // `queue: nil`, not `.main`: a queue makes delivery an *enqueue*, so the
        // block runs a runloop turn after the close. The scan closes a deleted
        // project's window and then deletes its row in the same turn, and a
        // block that lands after that deletes-then-writes — a foreign key that
        // no longer resolves, and a controller still registered for a project
        // that is gone. Running on the poster's thread (always the main one,
        // for a window close) keeps the order the caller wrote.
        closeObservers[repoID] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // AppKit closes still-open windows on the way out of the app.
                // Recording that as "the user closed it" would stop every open
                // project from reopening next launch, which is the opposite of
                // what quitting with windows open means.
                if recordsOpenState, !WindowManager.shared.isTerminating {
                    self.setWindowOpen(false, repoID: repoID)
                }
                // Captured strongly and *before* the controller is dropped:
                // dropping it releases the workspace and with it the services,
                // and a shutdown needs the object to still exist when the task
                // it schedules runs. Nothing waits for it *here* — a window
                // close must not block the main thread on a subprocess
                // exiting — but the quit path does, through `closeTeardowns`.
                //
                // Routed through the project controller when there is one,
                // since `ProjectController.shutdown()` and this inline path
                // both end at `languageServices.shutdown()` — running both
                // would shut the same services down twice. The inline path
                // stays for a window `adoptForScripting(_:)` registered,
                // which has no project controller of its own.
                //
                // `markClosed()` first, and synchronously: `shutdown()` sets
                // the same flag, but only once the task below is scheduled,
                // and a reconcile continuation already enqueued ahead of that
                // task would resume in between with the flag still down —
                // writing a closed window's checkouts, registering its
                // commands and persisting its tabs. The flag has to be down
                // before this turn ends, not merely soon.
                let projectController = self.projectControllers.removeValue(forKey: repoID)
                projectController?.markClosed()
                if let observer = self.keyObservers.removeValue(forKey: repoID) {
                    NotificationCenter.default.removeObserver(observer)
                }
                let services = self.controllers[repoID]?.project.languageServices
                self.controllers.removeValue(forKey: repoID)
                self.openOrder.removeAll { $0 == repoID }
                self.adoptedForScripting.remove(repoID)
                self.refreshOpenWorkspaceIDs()
                if let projectController {
                    self.closeTeardowns.add { await projectController.shutdown() }
                } else if let services {
                    self.closeTeardowns.add { await services.shutdown() }
                }
                if let observer = self.closeObservers.removeValue(forKey: repoID) {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }
    }
}

extension ProjectWindowManager: Loggable {
    public static nonisolated let logger = makeLogger()
}
