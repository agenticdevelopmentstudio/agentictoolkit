import AppKit
import Combine

import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// A file browser that shows what you click: the tree on the left, the selected
/// file on the right.
///
/// The two halves are separate controllers wired by a shared
/// `FileBrowserSelection`, so this type is only composition — divider,
/// thicknesses, autosave (`composition-over-inheritance`). It is what a host
/// installs when it wants "the file browser"; `FileBrowserViewController` alone
/// remains the right choice for a tree with no room for a viewer beside it.
@MainActor
public final class FileBrowserSplitViewController: ThemedSplitViewController {

    /// The tree half. Exposed so a host can force a resync or read the manager.
    public let browserViewController: FileBrowserViewController

    /// The display half.
    public let viewerViewController: FileViewerViewController

    /// What the tree selects and the viewer shows.
    public let selection: FileBrowserSelection

    /// The folders that were open and the file that was selected. Forwarded so
    /// a host can hand in what it stored without reaching through the tree.
    public var restoration: FileBrowserRestorationState { browserViewController.restoration }

    /// The roots the tree shows. Forwarded so a host does not have to reach
    /// through `browserViewController` to add or remove one.
    public var directories: FileBrowserDirectories { browserViewController.directories }

    /// Divider-position autosave key. AppKit keys these globally, so two split
    /// views alive at once under one name fight over the same stored position.
    /// Callers that can have more than one pass a distinct name.
    private let splitAutosaveName: String

    /// `PaneSelectionDescribing`'s change callback. Stored here rather than in
    /// the conformance below because Swift has no stored properties in
    /// extensions, and the protocol declares it `{ get set }`.
    public var onPaneSelectionChange: (() -> Void)?

    /// Watches the shared selection so the callback above fires for every way
    /// a file gets selected — the tree, a restore, a host setting it directly
    /// — rather than only for the clicks the tree happens to route through a
    /// delegate (`dry`).
    private var selectionObserver: AnyCancellable?

    /// - Parameters:
    ///   - directories: The roots to show — the project itself, plus whatever
    ///     the user has added with the tree's `+`.
    ///   - excludedURL: A directory left out of the tree and the watcher.
    ///   - config: Which directory extensions are opaque packages, and the
    ///     `UserDefaults` keys backing the browser's settings.
    ///   - ignorePatterns: Wildcard filename patterns to leave out of the tree.
    ///   - autosaveName: Divider-position key; distinct per pane when a host can
    ///     open more than one.
    public init(
        directories: FileBrowserDirectories,
        excludedURL: URL,
        config: FileTreeConfig = .default,
        ignorePatterns: [String] = [],
        autosaveName: String = "file-browser-split",
        restoration: FileBrowserRestorationState = FileBrowserRestorationState()
    ) {
        let selection = FileBrowserSelection()
        self.selection = selection
        self.browserViewController = FileBrowserViewController(
            directories: directories,
            excludedURL: excludedURL,
            config: config,
            ignorePatterns: ignorePatterns,
            selection: selection,
            restoration: restoration
        )
        self.viewerViewController = FileViewerViewController(selection: selection)
        self.splitAutosaveName = autosaveName
        super.init(nibName: nil, bundle: nil)

        // `@Published` publishes from `willSet`, so a synchronous sink reads
        // the *previous* node back out of `selection` — the footer would name
        // the file clicked before this one. Hopping to the run loop lets the
        // store complete first, the same compensation
        // `FileTreeOutlineViewController` and `FileBrowserViewController`
        // already make (`dry`). `removeDuplicates` keeps a re-click on the row
        // that is already selected from re-rendering the whole path.
        selectionObserver = selection.$selectedNode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.onPaneSelectionChange?() }
    }

    /// A browser over a single directory, with nothing to add or remove.
    public convenience init(
        rootURL: URL,
        excludedURL: URL,
        config: FileTreeConfig = .default,
        ignorePatterns: [String] = [],
        autosaveName: String = "file-browser-split",
        restoration: FileBrowserRestorationState = FileBrowserRestorationState()
    ) {
        self.init(
            directories: FileBrowserDirectories(primary: rootURL),
            excludedURL: excludedURL,
            config: config,
            ignorePatterns: ignorePatterns,
            autosaveName: autosaveName,
            restoration: restoration
        )
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        let treeItem = NSSplitViewItem(viewController: browserViewController)
        treeItem.minimumThickness = 180
        // No maximum: a deep tree of long filenames is exactly when the user
        // wants to drag the column wide, and a cap there reads as the divider
        // being broken. The viewer's own minimum is what stops the drag.
        treeItem.canCollapse = true
        // The tree keeps its width when the pane is resized; the viewer, which
        // has the text in it, takes the space.
        treeItem.holdingPriority = .defaultLow + 1

        let viewerItem = NSSplitViewItem(viewController: viewerViewController)
        // Below this the gutter and minimap crowd out the text itself.
        viewerItem.minimumThickness = 320

        addSplitViewItem(treeItem)
        addSplitViewItem(viewerItem)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = NSSplitView.AutosaveName(splitAutosaveName)
    }

    /// Collapses or restores the tree, leaving the viewer the whole pane.
    public func toggleTree() {
        guard let treeItem = splitViewItems.first else { return }
        treeItem.animator().isCollapsed = !treeItem.isCollapsed
    }
}

extension FileBrowserSplitViewController: PaneContentTeardown {
    /// Forwarded to the tree, which owns the FSEvents stream and the debounced
    /// git work. A closed pane must stop both whether or not its view ever got a
    /// `viewDidDisappear`.
    public func paneContentWillBeDiscarded() {
        browserViewController.paneContentWillBeDiscarded()
    }
}

extension FileBrowserSplitViewController: PaneSelectionDescribing {
    /// The selected file's name, not its path: the footer already names the
    /// project and the pane in the segments before this one, and a repo-rooted
    /// path repeated there would push the part the user is looking for off the
    /// truncation.
    public var paneSelectionDescription: String? {
        selection.selectedNode?.name
    }
}
