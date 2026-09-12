import AppKit
import Combine

import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticToolkitLanguage

/// A file browser — the tree, and the footer that adds and removes roots — so
/// one can be dropped into any AppKit container: a document pane, a sidebar, a
/// window.
///
/// Owns one `FileTreeManager` per root directory, and starts/stops watching with
/// the view's appearance: a browser in a hidden tab has no business running an
/// FSEvents stream and re-shelling `git status` every time a build writes.
@MainActor
public final class FileBrowserViewController: NSViewController {

    /// The roots this browser shows. A host that wants the `+`/`−` footer to
    /// outlive the pane owns this object and hands it in.
    public let directories: FileBrowserDirectories

    /// The primary root's manager. Exposed so a host can force a resync or read
    /// the detected IDE — those are questions about *the project*, which is the
    /// primary root, not about a directory someone dragged in beside it.
    public var manager: FileTreeManager { managerForPrimary }

    /// What the user has clicked. Shared rather than private so a host can
    /// drive it directly — restoring a selection, or reacting to one.
    public let selection: FileBrowserSelection

    /// What was open and what was selected last time. Shared rather than
    /// private for the same reason `selection` is: the host that persists it
    /// owns it, and a browser used alone gets one of its own that nobody reads.
    public let restoration: FileBrowserRestorationState

    /// `PaneSelectionDescribing`'s change callback. Stored here rather than in
    /// the conformance below because Swift has no stored properties in
    /// extensions, and the protocol declares it `{ get set }`.
    public var onPaneSelectionChange: (() -> Void)?

    /// Where a file the user picked in the tree should be shown — a plain
    /// click, or one of the context menu's three verbs. Forwarded straight
    /// from `tree`, whose own `onOpenRequest` is `internal`: this is the seam
    /// a host outside the module (the app, wiring the File Browser pane to the
    /// Document pane) actually reaches.
    public var onOpenRequest: ((URL, DocumentDestination) -> Void)? {
        get { tree.onOpenRequest }
        set { tree.onOpenRequest = newValue }
    }

    /// Moves the highlight onto a file an editor has come into focus showing,
    /// opening whatever folders it takes to get there. The return trip of
    /// `onOpenRequest`, and forwarded for the same reason: `tree` is internal,
    /// and the host wiring these two panes together is outside the module.
    public func reveal(_ url: URL) {
        tree.reveal(url)
    }

    /// Clears the highlight — the editor the tree is following has no file
    /// open, so there is nothing in the tree to point at.
    public func revealNothing() {
        tree.revealNothing()
    }

    /// Watches `selection` so `onPaneSelectionChange` fires for every way a
    /// file gets selected — the tree, a restore, a host setting it directly —
    /// rather than only for the clicks the tree happens to route through a
    /// delegate (`dry`).
    private var selectionObserver: AnyCancellable?

    private let excludedURL: URL
    private let config: FileTreeConfig
    private let ignorePatterns: [String]

    /// The app-wide open-document registry, threaded down to the tree so it
    /// can show a dirty indicator on a node with unsaved changes.
    private let documentStore: TextDocumentStore

    /// A status provider handed in from outside — for the root it belongs to,
    /// used instead of a freshly built one. `nil` for every browser that has
    /// no reason to share one, which is today's behaviour: a provider per root.
    private let injectedGitStatusProvider: GitStatusProvider?

    /// One manager per root, keyed by the root it scans, so rebuilding the list
    /// after an add or a remove reuses every manager that survived — a scanned
    /// tree is not rescanned because a *different* directory appeared. Internal
    /// read so a test can see which manager serves which root; write stays
    /// private — nothing outside this class may mutate it.
    private(set) var managersByRoot: [URL: FileTreeManager] = [:]
    private let roots = FileBrowserRootsModel()

    private lazy var tree = FileTreeOutlineViewController(
        roots: roots,
        directories: directories,
        selection: selection,
        restoration: restoration,
        documentStore: documentStore
    )

    private let addButton = NSButton(title: "", target: nil, action: nil)
    private let removeButton = NSButton(title: "", target: nil, action: nil)

    private var isWatching = false
    private var hasLoaded = false
    private var cancellables = Set<AnyCancellable>()

    /// - Parameters:
    ///   - directories: The roots to show. The primary is the project itself;
    ///     the rest are the user's additions.
    ///   - excludedURL: A directory left out of the tree and the watcher. For
    ///     a document-backed browser this is the document's own package, so the
    ///     browser neither indexes nor thrashes on it.
    ///   - config: Which directory extensions are opaque packages, and the
    ///     `UserDefaults` keys backing the browser's settings.
    ///   - ignorePatterns: Wildcard filename patterns to leave out of the tree.
    ///   - selection: The selection this tree drives. Defaults to one of its
    ///     own, so a browser used alone needs to know nothing about it.
    ///   - documentStore: The app-wide open-document registry, threaded down
    ///     to the tree for its dirty indicator. Injected — never built here.
    ///   - gitStatusProvider: A status provider to hand to the manager for
    ///     whichever root it belongs to; `nil` (the default) keeps today's
    ///     behaviour of one freshly built provider per root.
    public init(
        directories: FileBrowserDirectories,
        excludedURL: URL,
        config: FileTreeConfig = .default,
        ignorePatterns: [String] = [],
        selection: FileBrowserSelection = FileBrowserSelection(),
        restoration: FileBrowserRestorationState = FileBrowserRestorationState(),
        documentStore: TextDocumentStore,
        gitStatusProvider: GitStatusProvider? = nil
    ) {
        self.directories = directories
        self.excludedURL = excludedURL
        self.config = config
        self.ignorePatterns = ignorePatterns
        self.selection = selection
        self.restoration = restoration
        self.documentStore = documentStore
        self.injectedGitStatusProvider = gitStatusProvider
        super.init(nibName: nil, bundle: nil)

        rebuildManagers()
        directories.$additional
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildManagers() }
            .store(in: &cancellables)

        // `@Published` publishes from `willSet`, so a synchronous sink reads
        // the *previous* node back out of `selection` — the footer would name
        // the file clicked before this one. Hopping to the run loop lets the
        // store complete first. `removeDuplicates` keeps a re-click on the row
        // that is already selected from re-rendering the whole path, and
        // `dropFirst` drops the value `@Published` replays on subscribe: a
        // report made before the host installs `onPaneSelectionChange` would
        // otherwise surface one turn late, as a change nobody asked about.
        selectionObserver = selection.$selectedNode
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.onPaneSelectionChange?() }
    }

    /// A browser over a single directory, with nothing to add to or remove.
    public convenience init(
        rootURL: URL,
        excludedURL: URL,
        config: FileTreeConfig = .default,
        ignorePatterns: [String] = [],
        selection: FileBrowserSelection = FileBrowserSelection(),
        restoration: FileBrowserRestorationState = FileBrowserRestorationState(),
        documentStore: TextDocumentStore,
        gitStatusProvider: GitStatusProvider? = nil
    ) {
        self.init(
            directories: FileBrowserDirectories(primary: rootURL),
            excludedURL: excludedURL,
            config: config,
            ignorePatterns: ignorePatterns,
            selection: selection,
            restoration: restoration,
            documentStore: documentStore,
            gitStatusProvider: gitStatusProvider
        )
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func loadView() {
        let container = ThemedBackgroundView(role: .windowBackground)
        container.frame = NSRect(x: 0, y: 0, width: 260, height: 400)

        addChild(tree)
        let treeView = tree.view
        treeView.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let footer = makeFooter()

        container.addSubview(treeView)
        container.addSubview(divider)
        container.addSubview(footer)

        NSLayoutConstraint.activate([
            treeView.topAnchor.constraint(equalTo: container.topAnchor),
            treeView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            treeView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            divider.topAnchor.constraint(equalTo: treeView.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            footer.topAnchor.constraint(equalTo: divider.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        view = container
    }

    /// The `+`/`−` strip under the tree.
    private func makeFooter() -> NSView {
        let footer = ThemedBackgroundView(role: .surface)
        footer.translatesAutoresizingMaskIntoConstraints = false

        for (button, symbol, action) in [
            (addButton, "plus", #selector(addDirectory)),
            (removeButton, "minus", #selector(removeSelectedDirectory))
        ] {
            button.bezelStyle = .accessoryBar
            button.isBordered = false
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.target = self
            button.action = action
        }
        addButton.toolTip = "Add a directory to this project"
        addButton.accessibilityID("file-browser.add-directory")
        removeButton.accessibilityID("file-browser.remove-directory")

        let stack = NSStackView(views: [addButton, removeButton])
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: footer.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: footer.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -4)
        ])
        return footer
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        // `−` is only ever aimed at a root the user added, and which root that
        // is changes with every click in the tree.
        Publishers.Merge(
            selection.$selectedRoot.map { _ in () },
            directories.$additional.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.updateFooter() }
        .store(in: &cancellables)
        updateFooter()
    }

    private func updateFooter() {
        let root = selection.selectedRoot
        let removable = root.map { directories.isRemovable($0) } ?? false
        removeButton.isEnabled = removable
        // Saying *why* the button is off beats an unexplained grey minus.
        removeButton.toolTip = removable && root != nil
            ? "Remove “\(root!.lastPathComponent)” from this project"
            : "Select an added directory to remove it"
    }

    public override func viewWillAppear() {
        super.viewWillAppear()
        // `loadInitial()` reads each root's top level; doing it once keeps a
        // tab switch from re-reading it.
        if !hasLoaded {
            hasLoaded = true
            managersByRoot.values.forEach { $0.loadInitial() }
        }
        startWatching()
    }

    public override func viewDidDisappear() {
        super.viewDidDisappear()
        stopWatching()
    }

    // MARK: - Directories

    /// Asks for directories and adds them. Public so a menu item or a host's
    /// own button can drive the same path the footer's `+` does (`dry`).
    @objc public func addDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose directories to show in this project's file browser."
        guard panel.runModal() == .OK else { return }
        // A directory already in the list is not an error worth a dialog: the
        // user asked for it to be there, and it is.
        panel.urls.forEach { directories.add($0) }
        // The footer aims at what this browser just added — in this browser
        // only, since the list is the project's but the aim is the pane's.
        if let added = panel.urls.last?.standardizedFileURL, directories.isRemovable(added) {
            selection.selectedRoot = added
        }
    }

    /// Removes the root the footer's `−` targets, if it is a removable one.
    @objc public func removeSelectedDirectory() {
        guard let root = selection.selectedRoot else { RefusalFeedback.announce(); return }
        if directories.remove(root) {
            selection.selectedRoot = nil
        } else {
            RefusalFeedback.announce()
        }
    }

    /// Rebuilds the manager list to match `directories.all`, reusing the
    /// managers whose roots are still listed and tearing down the rest.
    private func rebuildManagers() {
        let wanted = directories.all
        var rebuilt: [URL: FileTreeManager] = [:]
        var ordered: [FileTreeManager] = []

        for root in wanted {
            let manager = managersByRoot[root] ?? makeManager(for: root)
            rebuilt[root] = manager
            ordered.append(manager)
        }

        for (root, manager) in managersByRoot where rebuilt[root] == nil {
            manager.stopWatching()
            // A pane's selection must not outlive the directory it came from,
            // or the viewer keeps showing a file the tree no longer lists.
            if let selected = selection.selectedNode?.url,
               selected.path == root.path || selected.path.hasPrefix(root.path + "/") {
                selection.selectedNode = nil
            }
            // Nor may the footer keep aiming at a root that is gone — which it
            // can be because *another* pane of the same project removed it.
            if selection.selectedRoot == root { selection.selectedRoot = nil }
        }

        managersByRoot = rebuilt
        roots.managers = ordered

        // A directory added while the browser is already on screen has missed
        // both `viewWillAppear` hooks, so it gets them here.
        if hasLoaded {
            for manager in ordered where manager.rootNode == nil {
                manager.loadInitial()
            }
        }
        if isWatching {
            ordered.forEach { $0.startWatching() }
        }
    }

    private func makeManager(for root: URL) -> FileTreeManager {
        // `resolvingSymlinksInPath()`, not `standardizedFileURL`, for the
        // reason `ProjectCheckout.swift:12` documents: the injected provider's
        // `repoRoot` is a resolved checkout directory, and this root is
        // whatever the window was opened with. A lexical comparison misses
        // whenever a symlink stands between them, and the miss is silent — the
        // pane quietly builds a second, uninstrumented provider of its own.
        let provider = injectedGitStatusProvider.flatMap { candidate in
            candidate.repoRoot.resolvingSymlinksInPath() == root.resolvingSymlinksInPath() ? candidate : nil
        }
        return FileTreeManager(
            repoRootURL: root,
            packageURL: excludedURL,
            config: config,
            ignorePatterns: ignorePatterns,
            gitStatusProvider: provider
        )
    }

    private var managerForPrimary: FileTreeManager {
        // `rebuildManagers()` runs in `init` and always inserts the primary, so
        // a miss here means the invariant broke — say so rather than papering
        // over it with a throwaway manager (`fail-fast`).
        guard let manager = managersByRoot[directories.primary] else {
            preconditionFailure("No manager for the primary root \(directories.primary.path)")
        }
        return manager
    }

    // MARK: - Watching

    private func startWatching() {
        guard !isWatching else { return }
        isWatching = true
        managersByRoot.values.forEach { $0.startWatching() }
    }

    private func stopWatching() {
        guard isWatching else { return }
        isWatching = false
        managersByRoot.values.forEach { $0.stopWatching() }
    }
}

extension FileBrowserViewController: PaneContentTeardown {
    /// Closing the pane ends the FSEvents streams and the debounced git/IDE
    /// work, whether or not the view ever got a `viewDidDisappear`.
    public func paneContentWillBeDiscarded() {
        stopWatching()
    }
}

extension FileBrowserViewController: PaneSelectionDescribing {
    /// The selected file's name, not its path: the footer already names the
    /// project and the pane in the segments before this one, and a repo-rooted
    /// path repeated there would push the part the user is looking for off the
    /// truncation.
    public var paneSelectionDescription: String? {
        selection.selectedNode?.name
    }
}

/// The managers the pane draws, as one observable list.
///
/// The tree cannot observe a dictionary owned by a view controller, and making
/// the controller itself observable would publish far more than the one fact
/// the tree needs (`separation-of-concerns`).
@MainActor
final class FileBrowserRootsModel: ObservableObject {
    @Published var managers: [FileTreeManager] = []
}
