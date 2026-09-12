import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS
import os

/// One open project: the repository it is, the database rows that belong to
/// it, and the tab/split arrangement its window shows.
///
/// This is what `NSDocument` used to be here, minus the document. There is no
/// file to read, write, autosave, revert or name — a project is a `git_repo`
/// row plus the rows keyed to it, so every edit is already saved and a
/// repository can move on disk without the project noticing.
@MainActor
public final class ProjectWorkspace {

    public private(set) var repo: GitRepo
    public let database: ProjectDatabase

    /// The views this project may show and the arrangements it may show them
    /// in. Defaults to whatever the app installed; a host can hand a different
    /// one to the projects it opens (`dependency-injection`).
    public var layout: ComposableTabsLayout

    /// This project's language servers, or `nil` when the host wired none.
    ///
    /// Held here because a `ProjectWorkspace` is what every pane in the window
    /// is handed, so it is the one object already threaded to the file editor.
    /// `ProjectWindowManager` owns the lifecycle — it builds this through its
    /// `languageServicesFactory` and shuts it down when the window closes.
    ///
    /// Optional, and defaulted, on purpose. A `ProjectWorkspace` is constructed
    /// in tests and in hosts that want no language support, and the production
    /// registry starts real language-server subprocesses; a non-optional
    /// parameter would spawn `sourcekit-lsp` from every one of those.
    public let languageServices: ProjectLanguageServices?

    /// The git client every per-directory object this project vends is built
    /// on, so a host that injects a configured client gets it everywhere
    /// (`dependency-injection`).
    public let gitClient: GitClient

    /// A `[URL: Object]` whose entries live exactly as long as something else
    /// holds them.
    ///
    /// The project mints one object per directory and hands it out; the panes
    /// and controllers that asked are what keep it alive. Holding the values
    /// strongly meant a project accumulated one `FileBrowserDirectories` and
    /// one `GitStatusProvider` for every directory anything had *ever* asked
    /// about — every worktree visited, every checkout opened and closed again
    /// — for as long as the project stayed open, each one still observing a
    /// directory with nothing left on screen to show for it.
    ///
    /// Weak values end an entry with its last holder without weakening the
    /// invariant the cache exists for: while *anything* is still holding the
    /// object for a directory, everyone asking about that directory is handed
    /// that same object.
    private struct WeakCache<Object: AnyObject> {
        private struct Box {
            weak var object: Object?
        }

        private var boxes: [URL: Box] = [:]

        /// Every value still held somewhere, keyed as it was stored.
        var liveEntries: [(key: URL, object: Object)] {
            boxes.compactMap { key, box in box.object.map { (key, $0) } }
        }

        subscript(key: URL) -> Object? {
            get { boxes[key]?.object }
            set {
                // A dead entry's key goes with it rather than staying behind
                // as an empty box: nothing here may grow with the number of
                // directories a long-lived project has visited.
                boxes = boxes.filter { $0.value.object != nil }
                boxes[key] = newValue.map(Box.init(object:))
            }
        }
    }

    private var nextPaneNumber = 1
    private var fileBrowserDirectoriesByPrimary = WeakCache<FileBrowserDirectories>()
    private var gitStatusProvidersByRoot = WeakCache<GitStatusProvider>()

    public init(
        repo: GitRepo,
        database: ProjectDatabase,
        layout: ComposableTabsLayout? = nil,
        languageServices: ProjectLanguageServices? = nil,
        gitClient: GitClient = .shared
    ) {
        self.repo = repo
        self.database = database
        self.layout = layout ?? ComposableTabsLayout.current ?? ComposableTabsLayout.placeholderOnly()
        self.languageServices = languageServices
        self.gitClient = gitClient
    }

    public var id: UUID { repo.id }
    public var displayName: String { repo.name }
    /// The repository's own folder — the root every pane defaults to.
    public var directoryURL: URL { repo.url }

    /// Where panes may write derived data for this project — file-tree scan
    /// caches and the like.
    ///
    /// Beside the database, not inside the repository: a project owns no files
    /// in the folder it is about, so nothing it caches can show up in the
    /// user's diff or have to be excluded from its own file tree.
    /// Answering where it is does not create it: every caller so far only names
    /// the folder — the file browser excludes it from the tree — and a getter
    /// that quietly makes a directory on disk (for every project, whether or
    /// not anything ever caches into it) is a side effect nobody reading
    /// `project.cacheDirectoryURL` would expect. Whoever writes there first
    /// creates it (`explicit-over-implicit`).
    public var cacheDirectoryURL: URL {
        URL(fileURLWithPath: database.databasePath)
            .deletingLastPathComponent()
            .appendingPathComponent("caches", isDirectory: true)
            .appendingPathComponent(repo.id.uuidString, isDirectory: true)
    }

    /// Picks up a rename or a move without rebuilding the window.
    public func update(repo: GitRepo) {
        guard repo.id == self.repo.id else { return }
        self.repo = repo
    }

    public func allocatePaneNumber() -> Int {
        let allocated = nextPaneNumber
        nextPaneNumber += 1
        return allocated
    }

    // MARK: - Tabs

    /// What the database holds for this project's tabs, or `nil` when nothing
    /// was ever saved (a project being opened for the first time, or a load
    /// that failed).
    public struct StoredTabs {
        public let tabs: [TabRecord]
        public let activeTabID: UUID?
        public let enabledEdges: [Edge]
    }

    /// The persisted tabs, or `nil` when there is nothing stored to read
    /// through: a fresh project, or one whose load failed.
    public func storedTabs() -> StoredTabs? {
        guard let loaded = try? database.loadTabs(repoID: repo.id), !loaded.tabs.isEmpty else { return nil }
        return StoredTabs(tabs: loaded.tabs, activeTabID: loaded.activeTabID, enabledEdges: loaded.enabledEdges)
    }

    /// The tabs the window controller should display: the stored set, or one
    /// default tab for a project being opened for the first time.
    public func initialTabs() -> (tabs: [TabRecord], activeTabID: UUID, enabledEdges: [Edge]) {
        guard let stored = storedTabs() else {
            let tab = TabRecord(title: "Tab 1", root: layout.blueprint())
            return ([tab], tab.id, [.top])
        }
        // A stored tree can outlive the spec that made it, so it is repaired on
        // the way in rather than allowed to contradict the rules the split menu
        // enforces from here on.
        let repaired = stored.tabs.map { record -> TabRecord in
            var record = record
            record.root = layout.spec.reconcile(record.root)
            return record
        }
        // One arrangement per project. Tabs stored before that was true — and
        // any that drifted since, a repair above included — take the shape of
        // the tab that is coming up in front, each in its own node ids so the
        // panes it remembers come back with it.
        let arrangement = ProjectTabReconciler.arrangement(of: repaired, activeTabID: stored.activeTabID)
        let shared = repaired.map { record -> TabRecord in
            var record = record
            if let arrangement {
                record.root = record.root.reshaped(toMatch: arrangement)
            }
            // Both rewrites above can retire a node id: the spec repair drops a
            // pane the spec no longer allows, and a reshape onto a smaller
            // arrangement has fewer slots than the tab had ids. The remembered
            // focus is not rewritten with them, and `project_tabs
            // .focused_node_id` is a foreign key into `layout_nodes` — so one
            // stale id made the *entire* `saveTabs` transaction fail with
            // `FOREIGN KEY constraint failed`, which `persistTabs` logs and
            // swallows. The symptom was never a missing focus ring: it was this
            // project's tabs silently never being saved again, for the rest of
            // the session and every session after it.
            if let focused = record.focusedNodeID, !record.root.leafIDs.contains(focused) {
                record.focusedNodeID = nil
            }
            return record
        }
        return (shared, stored.activeTabID ?? shared[0].id, stored.enabledEdges)
    }

    /// Persists the current tabs, which one is active, and the enabled edges.
    /// Called whenever a tab is added/removed/reordered, an edge is toggled, or
    /// the split layout inside a tab changes.
    public func persistTabs(_ tabs: [TabRecord], activeTabID: UUID?, enabledEdges: [Edge]) {
        do {
            try database.saveTabs(tabs, activeTabID: activeTabID, enabledEdges: enabledEdges, repoID: repo.id)
        } catch {
            Self.logger.error("Failed to save project tabs: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Pane state

    /// What the pane at `nodeID` remembered under `key`, or `nil`.
    ///
    /// A pane reaches this through the `nodeID` its factory is handed
    /// (`ComposableTabsViewContext`), so remembering something new costs a key
    /// rather than a schema change or a new path through the window controller.
    ///
    /// **The `chrome.` prefix is reserved.** `ProjectPaneStateStore` writes
    /// everything the pane *chrome* remembers — its minimize edge, its zoom,
    /// its spacing override — into this same bag under that prefix. A pane's
    /// content picks its own keys and must not begin one with `chrome.`, or it
    /// lands on the chrome's row for the same node. Nothing checks this: the
    /// prefix is what keeps chrome off content's keys, and this sentence is
    /// what keeps content off chrome's. A check would have to let the one
    /// caller that is *supposed* to write the prefix through, which buys less
    /// than the sentence does.
    public func paneState(nodeID: UUID, key: String) -> String? {
        do {
            return try database.paneState(repoID: repo.id, nodeID: nodeID, key: key)
        } catch {
            logPaneStateFailure("load", nodeID: nodeID, key: key, error: error)
            return nil
        }
    }

    /// See `paneState(nodeID:key:)` for the reserved `chrome.` prefix.
    ///
    /// A failure is logged and dropped rather than reported. Every piece of
    /// chrome keeps its own in-memory copy of what it wrote, so the session
    /// stays correct and only the *next* launch shows the loss — the right
    /// trade for a minimize edge, and the reason the log has to name the row:
    /// without that, a report from the field cannot say which pane forgot.
    public func setPaneState(nodeID: UUID, key: String, value: String?) {
        do {
            try database.setPaneState(repoID: repo.id, nodeID: nodeID, key: key, value: value)
        } catch {
            logPaneStateFailure("save", nodeID: nodeID, key: key, error: error)
        }
    }

    /// Names the row a failed pane-state access was about.
    ///
    /// All three parts, because the failure this is most likely to be is a
    /// foreign-key refusal — a repo the database has never heard of — and that
    /// one is unrecognisable without the repo id sitting beside the node and
    /// the key. `localizedDescription` alone says "constraint failed".
    private func logPaneStateFailure(_ verb: String, nodeID: UUID, key: String, error: any Error) {
        Self.logger.error("""
            Failed to \(verb, privacy: .public) pane state \
            (repo \(self.repo.id.uuidString, privacy: .public), \
            node \(nodeID.uuidString, privacy: .public), \
            key \(key, privacy: .public)): \
            \(error.localizedDescription, privacy: .public)
            """)
    }

    /// A list of strings, stored as JSON in one pane-state value.
    ///
    /// JSON rather than a separator, because the lists panes remember are file
    /// paths and no character is illegal in one.
    public func paneStateList(nodeID: UUID, key: String) -> [String] {
        guard let raw = paneState(nodeID: nodeID, key: key),
              let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    public func setPaneStateList(nodeID: UUID, key: String, values: [String]) {
        guard !values.isEmpty else {
            setPaneState(nodeID: nodeID, key: key, value: nil)
            return
        }
        guard let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8) else { return }
        setPaneState(nodeID: nodeID, key: key, value: json)
    }

    // MARK: - Project settings

    /// What this project remembered under `key`, or `nil`.
    ///
    /// The same untyped bag `paneState` is, one level up: keyed to the project
    /// rather than to a pane inside it. This is where a window remembers
    /// something about *itself* — which is why the settings window's equivalent
    /// lives in `UserSettings` and this one cannot. There is one settings
    /// window; there is one project window per project, and they disagree.
    public func setting(_ key: String) -> String? {
        do {
            return try database.setting(repoID: repo.id, key: key)
        } catch {
            Self.logger.error("Failed to load project setting: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// A `nil` value deletes the row, so "never set" and "set back to the
    /// default" are the same state and neither accumulates.
    public func setSetting(_ key: String, to value: String?) {
        do {
            try database.setSetting(repoID: repo.id, key: key, value: value)
        } catch {
            Self.logger.error("Failed to save project setting: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Project directories

    /// The extra directories this project's file browser shows, beyond the
    /// repository's own folder.
    public func projectDirectories() -> [URL] {
        do {
            return try database.loadProjectDirectories(repoID: repo.id).map { URL(fileURLWithPath: $0) }
        } catch {
            Self.logger.error("Failed to load project directories: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// The roots every file browser pane working in `primary` shows — one
    /// object per directory, not one per pane, so every pane in a tab shares
    /// and observes the same additional-roots list.
    ///
    /// Each pane used to build its own from a snapshot taken when it was
    /// created, and each wrote the *whole* list back on any change: a directory
    /// added in one pane was silently dropped the next time another pane saved
    /// (`dry` — one representation of the project's roots). Which root a pane's
    /// footer is aimed at stays per-pane, on `FileBrowserSelection`.
    ///
    /// The cache holds it weakly, so the caller owns what it is handed —
    /// `FileBrowserViewController.directories` is the reference that keeps a
    /// pane's roots alive. Closing the last pane on a directory therefore
    /// forgets that directory, which is the point: a project that has been
    /// open all day has visited far more directories than it is showing.
    public func fileBrowserDirectories(primary: URL) -> FileBrowserDirectories {
        // Resolved, like every other directory identity on this path: the same
        // folder arrives here both as a checkout directory git already
        // resolved and as the unresolved path the project was opened with, and
        // a lexical key would hand those two callers two different objects —
        // which is exactly the per-pane duplication this cache exists to end.
        let key = primary.resolvingSymlinksInPath()
        if let cached = fileBrowserDirectoriesByPrimary[key] {
            return cached
        }
        let directories = FileBrowserDirectories(
            primary: key,
            additional: projectDirectories()
        )
        directories.onChange = { [weak self] urls in
            self?.projectDirectoriesDidChange(urls, from: key)
        }
        fileBrowserDirectoriesByPrimary[key] = directories
        return directories
    }

    /// The roots for panes working in the project's own directory.
    public var fileBrowserDirectories: FileBrowserDirectories {
        fileBrowserDirectories(primary: directoryURL)
    }

    /// One pane's `+`/`−`, applied to the whole project.
    ///
    /// The added-roots list is stored once per *repository*, and
    /// `saveProjectDirectories` writes it by deleting every row for the repo
    /// and re-inserting what it was handed. A project window that is showing a
    /// worktree as well as the main checkout holds two
    /// `FileBrowserDirectories` — one per checkout directory — each with its
    /// own copy of that one list, taken when it was created. Left alone, the
    /// second one to save wrote its stale copy over the first one's addition
    /// and the folder vanished from disk with no error. Every sibling is
    /// refreshed here, before anything else can save.
    ///
    /// The merge exists because an object cannot represent its own primary: it
    /// filters that root out of `additional` (it is already shown, and it is
    /// not removable). If the stored list names it — the user added a
    /// worktree's folder as an extra root of the main checkout, then opened
    /// that worktree in its own tab — the reporting object would otherwise
    /// silently delete it on the next `+`.
    private func projectDirectoriesDidChange(_ urls: [URL], from primary: URL) {
        let stored = projectDirectories().map { $0.resolvingSymlinksInPath() }
        var merged = urls.map { $0.resolvingSymlinksInPath() }
        if stored.contains(primary), !merged.contains(primary) {
            merged.append(primary)
        }

        persistProjectDirectories(merged)
        for (key, directories) in fileBrowserDirectoriesByPrimary.liveEntries where key != primary {
            directories.replaceAdditional(with: merged)
        }
    }

    /// Persists the extra directories. Called whenever the browser's `+`/`−`
    /// changes the list.
    public func persistProjectDirectories(_ urls: [URL]) {
        do {
            try database.saveProjectDirectories(urls.map(\.path), repoID: repo.id)
        } catch {
            Self.logger.error("Failed to save project directories: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Git status

    /// The status provider for everything working in `directory` — one object
    /// per resolved directory, minted on demand and held weakly for as long as
    /// its holders live, exactly as `fileBrowserDirectories(primary:)` mints
    /// its roots. A provider outlives the pane it was first asked for whenever
    /// the checkout's `BranchController` still holds it, and both of them
    /// outlive nothing at all.
    ///
    /// The project owns these, not the branch controllers, because of *when*
    /// they are asked for. A pane is built while the window installs its stored
    /// tabs, which happens before the first `git worktree list` has returned and
    /// so before any `BranchController` exists; a provider resolved through the
    /// controllers therefore answered `nil` for every pane the window opened
    /// with, and `FileBrowserViewController` latches what it is handed at init
    /// and never asks again — so those panes went on running a private provider
    /// of their own for the rest of the session, and the `Refresh Status`
    /// command reached a different object than the one their badges came from.
    /// Minting here removes the ordering question rather than moving it: the
    /// pane and the `BranchController` that appears a moment later ask the same
    /// question of the same cache and get the same live object.
    public func gitStatusProvider(forDirectory directory: URL) -> GitStatusProvider {
        // Resolved for the same reason `fileBrowserDirectories(primary:)`
        // resolves: a checkout directory arrives already resolved from `git
        // worktree list`, the project's own directory arrives as the user
        // opened it, and a lexical key would hand one folder two providers.
        let key = directory.resolvingSymlinksInPath()
        if let cached = gitStatusProvidersByRoot[key] {
            return cached
        }
        let provider = GitStatusProvider(repoRoot: key, client: gitClient)
        gitStatusProvidersByRoot[key] = provider
        return provider
    }
}

extension ProjectWorkspace: Loggable {
    public static nonisolated let logger = makeLogger()
}

/// This project's roots, as `vscode.workspace` needs them.
///
/// A fact about what a project is, not a fact about extensions — see
/// `ExtensionWorkspaceRoots`'s own doc, in `MainThreadWorkspace.swift`, for
/// why the extension host takes this narrow protocol rather than a
/// `ProjectWorkspace` itself.
extension ProjectWorkspace: ExtensionWorkspaceRoots {

    public var workspaceDisplayName: String? { displayName }

    /// Every root this project's file browser shows, primary first —
    /// `fileBrowserDirectories.all`, the same list every pane already reads.
    public var workspaceRootURLs: [URL] { fileBrowserDirectories.all }
}
