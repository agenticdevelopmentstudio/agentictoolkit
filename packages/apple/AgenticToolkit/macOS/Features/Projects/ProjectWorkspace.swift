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

    private var nextPaneNumber = 1
    private var fileBrowserDirectoriesByPrimary: [URL: FileBrowserDirectories] = [:]

    /// Set by the project controller so panes get the status provider of the
    /// branch that owns their directory instead of building their own.
    public var gitStatusProviderResolver: ((URL) -> GitStatusProvider?)?

    public init(
        repo: GitRepo,
        database: ProjectDatabase,
        layout: ComposableTabsLayout? = nil,
        languageServices: ProjectLanguageServices? = nil
    ) {
        self.repo = repo
        self.database = database
        self.layout = layout ?? ComposableTabsLayout.current ?? ComposableTabsLayout.placeholderOnly()
        self.languageServices = languageServices
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
        return (repaired, stored.activeTabID ?? repaired[0].id, stored.enabledEdges)
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
            self?.persistProjectDirectories(urls)
        }
        fileBrowserDirectoriesByPrimary[key] = directories
        return directories
    }

    /// The roots for panes working in the project's own directory.
    public var fileBrowserDirectories: FileBrowserDirectories {
        fileBrowserDirectories(primary: directoryURL)
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

    /// The status provider for panes working in `directory`, or `nil` when the
    /// project controller has not resolved one (a directory outside any known
    /// worktree, or a project with no resolver wired yet).
    public func gitStatusProvider(forDirectory directory: URL) -> GitStatusProvider? {
        gitStatusProviderResolver?(directory.resolvingSymlinksInPath())
    }
}

extension ProjectWorkspace: Loggable {
    public static nonisolated let logger = makeLogger()
}
