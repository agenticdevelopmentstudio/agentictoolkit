import AppKit
import os
import AgenticToolkitCore

/// Keeps one window per project, keyed by `git_repo.id`.
///
/// The key is the row id and not the path, so opening "the same project" twice
/// means the same window even after the repository has been moved or renamed —
/// which is the whole reason the registry has ids in the first place.
@MainActor
public final class ProjectWindowManager: ProjectOpening {

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

    /// The order projects were opened in.
    ///
    /// `controllers` is a `Dictionary`, whose value order is seeded per
    /// process; scripting enumerates windows, tabs and panes through this, and
    /// a script that lists `panes` twice must get the same order twice.
    private var openOrder: [UUID] = []

    private var closeObservers: [UUID: NSObjectProtocol] = [:]

    /// The projects registered by `adoptForScripting(_:)` rather than opened
    /// here. Membership is what `forgetForScripting(_:)` checks, because the
    /// two registrations are not interchangeable: an adopted window's observer
    /// only unregisters it, while an opened window's observer also clears the
    /// persisted "reopen me" flag. Tearing the second one down through the
    /// undo of the first would leave the project reopening for ever.
    private var adoptedForScripting: Set<UUID> = []
    private weak var coordinator: ProjectsCoordinator?

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

    public var openWorkspaces: [ProjectWorkspace] {
        controllers.values.map(\.project)
    }

    /// Every open project window, in the order their projects were opened.
    public var openWindowControllers: [ComposableTabsWindowController] {
        openOrder.compactMap { controllers[$0] }
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
        adoptedForScripting.remove(id)
        if let observer = closeObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func windowController(for repoID: UUID) -> ComposableTabsWindowController? {
        controllers[repoID]
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
        let controller = ComposableTabsWindowController(project: workspace)
        controllers[repo.id] = controller
        openOrder.append(repo.id)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        observeClose(of: controller, repoID: repo.id, recordsOpenState: true)
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
        guard !services.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for service in services {
                group.addTask { await service.shutdown() }
            }
        }
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
                // it schedules runs. Best-effort — nothing waits for it here,
                // because a window close must not block the main thread on a
                // subprocess exiting.
                let services = self.controllers[repoID]?.project.languageServices
                self.controllers.removeValue(forKey: repoID)
                self.openOrder.removeAll { $0 == repoID }
                self.adoptedForScripting.remove(repoID)
                if let services {
                    Task { await services.shutdown() }
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
