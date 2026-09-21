import AppKit
import Foundation
import Testing
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The pane side of webview restoration: one registered identifier, one row of
/// pane state per panel, and the two ways a pane gets its panel — handed one
/// that was just created, or rebuilt from what was written down.
///
/// The factory is driven through `ComposableTabsViewRegistry.makeContentViewController`
/// rather than through a real split, because a split is a window and a window
/// is a screen this project's rules keep out of a test run. What the split
/// eventually does to the factory is supply a node id and a project, which is
/// exactly what that method takes.
@MainActor
@Suite
struct WebviewPanelSerializerTests {

    // MARK: - Fixtures

    /// A workspace whose repository is *registered*: `pane_state.repo_id`
    /// references `git_repo(id)` under `PRAGMA foreign_keys=ON`, so a project
    /// the database has never heard of silently refuses every write — and a
    /// test about persistence would pass on the strength of two absences.
    private static func makeWorkspace() -> ProjectWorkspace {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebviewPanelSerializerTests-\(UUID().uuidString)")
            .appendingPathComponent("Test.db").path
        let repo = GitRepo(path: NSTemporaryDirectory(), name: "Test")
        // A failure here is a broken test environment, not a case to handle.
        // swiftlint:disable force_try
        let database = try! ProjectDatabase(path: path)
        try! database.insert(repo)
        // swiftlint:enable force_try
        return ProjectWorkspace(repo: repo, database: database)
    }

    private func makePanel(
        viewType: String = "markdown.preview",
        title: String = "Preview",
        options: WebviewPanelOptions = WebviewPanelOptions(
            enableScripts: nil, enableForms: nil, localResourceRoots: nil)
    ) -> WebviewPanelViewController {
        WebviewPanelViewController(
            viewType: viewType, title: title, options: options, localResourceRoots: [])
    }

    /// Runs the registered factory for `nodeID` exactly as a pane would.
    private func makeContent(
        _ registry: ComposableTabsViewRegistry,
        nodeID: UUID,
        project: ProjectWorkspace,
        paneNumber: Int = 1
    ) -> NSViewController {
        registry.makeContentViewController(
            for: WebviewPanelSerializer.viewID,
            nodeID: nodeID,
            project: project,
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
            paneNumber: paneNumber)
    }

    private func storedState(
        _ project: ProjectWorkspace, _ nodeID: UUID
    ) throws -> WebviewPanelState? {
        guard let text = project.paneState(
            nodeID: nodeID, key: WebviewPanelSerializer.paneStateKey)
        else { return nil }
        return try WebviewPanelState(json: text)
    }

    // MARK: - Registration

    /// Without this the whole design fails silently: a persisted layout naming
    /// the identifier would resolve to nothing and every restored panel would
    /// come back as a numbered rectangle.
    @Test("the one shared identifier is registered on construction")
    func theViewIDIsRegistered() {
        let registry = ComposableTabsViewRegistry()
        #expect(!registry.isRegistered(WebviewPanelSerializer.viewID))

        _ = WebviewPanelSerializer(registry: registry) { _ in nil }

        #expect(registry.isRegistered(WebviewPanelSerializer.viewID))
    }

    // MARK: - Placing a newly created panel

    @Test("a panel named for a pane is that pane's content")
    func aPendingPanelFillsItsPane() {
        let project = Self.makeWorkspace()
        let registry = ComposableTabsViewRegistry()
        let serializer = WebviewPanelSerializer(registry: registry) { _ in nil }
        let panel = makePanel()
        let nodeID = UUID()

        serializer.prepareToPlace(panel, panesBeforeSplit: [])
        serializer.didPlace(panel, in: nodeID)

        #expect(makeContent(registry, nodeID: nodeID, project: project) === panel)
    }

    /// The factory can run *inside* `split(_:adding:direction:)`, before the
    /// caller has a node id to name the pane with. That is the case
    /// `prepareToPlace` alone covers.
    @Test("a panel prepared but not yet named still fills the pane being built")
    func anUnnamedPanelFillsTheNextPane() {
        let project = Self.makeWorkspace()
        let registry = ComposableTabsViewRegistry()
        let serializer = WebviewPanelSerializer(registry: registry) { _ in nil }
        let panel = makePanel()

        serializer.prepareToPlace(panel, panesBeforeSplit: [])

        #expect(makeContent(registry, nodeID: UUID(), project: project) === panel)
    }

    /// A panel left waiting after a split that never happened would be picked
    /// up by the *next* extension webview pane — a panel appearing somewhere
    /// nobody asked to put it.
    @Test("a cancelled placement leaves nothing behind for the next pane")
    func aCancelledPlacementIsNotPickedUpLater() {
        let project = Self.makeWorkspace()
        let registry = ComposableTabsViewRegistry()
        let serializer = WebviewPanelSerializer(registry: registry) { _ in nil }
        let panel = makePanel()

        serializer.prepareToPlace(panel, panesBeforeSplit: [])
        serializer.cancelPlacement(of: panel)

        let content = makeContent(registry, nodeID: UUID(), project: project)
        #expect(content !== panel)
        #expect(content is PlaceholderPaneViewController)
    }

    /// The same rule one step later. `didPlace` moves the panel out of
    /// `unplaced` and files it against a node id, so a cancellation that only
    /// looked at `unplaced` would leave it filed — and the next pane built at
    /// that node id would be handed a panel whose placement was called off.
    @Test("a placement cancelled after the pane was named leaves nothing filed")
    func aCancelledPlacementIsDroppedEvenAfterItsPaneWasNamed() {
        let project = Self.makeWorkspace()
        let registry = ComposableTabsViewRegistry()
        let serializer = WebviewPanelSerializer(registry: registry) { _ in nil }
        let panel = makePanel()
        let nodeID = UUID()

        serializer.prepareToPlace(panel, panesBeforeSplit: [])
        serializer.didPlace(panel, in: nodeID)
        serializer.cancelPlacement(of: panel)

        let content = makeContent(registry, nodeID: nodeID, project: project)
        #expect(content !== panel)
        #expect(content is PlaceholderPaneViewController)
    }

    /// A created panel is the one case where nothing else will ever know the
    /// pane's node id — so the row has to be written the moment the two meet,
    /// not at the next retitle.
    @Test("a placed panel is written down immediately")
    func aPlacedPanelIsPersistedAtOnce() throws {
        let project = Self.makeWorkspace()
        let registry = ComposableTabsViewRegistry()
        let serializer = WebviewPanelSerializer(registry: registry) { _ in nil }
        let panel = makePanel(
            viewType: "markdown.preview", title: "Preview README.md",
            options: WebviewPanelOptions(
                enableScripts: true, enableForms: nil, localResourceRoots: []))
        let nodeID = UUID()

        serializer.prepareToPlace(panel, panesBeforeSplit: [])
        serializer.didPlace(panel, in: nodeID)
        _ = makeContent(registry, nodeID: nodeID, project: project)

        let stored = try #require(try storedState(project, nodeID))
        #expect(stored.viewType == "markdown.preview")
        #expect(stored.title == "Preview README.md")
        #expect(stored.options.enableScripts)
    }

    /// `onPaneTitleChange` is the pane's, claimed in `viewDidLoad` — after the
    /// factory returned. This asserts the serializer listens to the callback
    /// that is actually its own, which is the whole reason there are two.
    @Test("a retitle after the pane is built updates what was written down")
    func aRetitleIsWrittenDown() throws {
        let project = Self.makeWorkspace()
        let registry = ComposableTabsViewRegistry()
        let serializer = WebviewPanelSerializer(registry: registry) { _ in nil }
        let panel = makePanel(title: "Preview")
        let nodeID = UUID()
        serializer.prepareToPlace(panel, panesBeforeSplit: [])
        serializer.didPlace(panel, in: nodeID)
        _ = makeContent(registry, nodeID: nodeID, project: project)

        panel.title = "Preview CHANGELOG.md"

        #expect(try storedState(project, nodeID)?.title == "Preview CHANGELOG.md")
    }

    /// One split, one panel. A second pane built afterwards must not be handed
    /// the panel the first one already took.
    @Test("a pane built after the panel was taken does not get it again")
    func aPendingPanelIsHandedOverOnlyOnce() {
        let project = Self.makeWorkspace()
        let registry = ComposableTabsViewRegistry()
        let serializer = WebviewPanelSerializer(registry: registry) { _ in nil }
        let panel = makePanel()
        let nodeID = UUID()
        serializer.prepareToPlace(panel, panesBeforeSplit: [])
        serializer.didPlace(panel, in: nodeID)
        _ = makeContent(registry, nodeID: nodeID, project: project)

        #expect(makeContent(registry, nodeID: UUID(), project: project) !== panel)
    }

    /// The bug this pins. A split forces a layout pass, and a layout pass
    /// builds any pane that had been left lazy — a restored extension webview
    /// pane in a tab the user had not looked at yet is exactly that. It runs
    /// the same factory, under the same one identifier, and used to be handed
    /// the panel the split was still in the middle of making room for.
    ///
    /// Two panes went wrong at once: the old one showed a panel that belongs
    /// to a pane elsewhere instead of the one it had saved, and the new one
    /// came up empty. So the placement is told which panes already existed,
    /// and none of them can claim what the split is carrying.
    @Test("a pane that already existed cannot take the panel a split is making")
    func anOlderPaneCannotClaimTheWaitingPanel() {
        let project = Self.makeWorkspace()
        let registry = ComposableTabsViewRegistry()
        let serializer = WebviewPanelSerializer(registry: registry) { _ in nil }
        let panel = makePanel()
        let older = UUID()

        serializer.prepareToPlace(panel, panesBeforeSplit: [older])

        #expect(makeContent(registry, nodeID: older, project: project) !== panel)
        #expect(makeContent(registry, nodeID: UUID(), project: project) === panel)
    }

    /// And the placer has to be able to find out where it went.
    ///
    /// When the factory runs inside `split(_:adding:direction:)` the panel is
    /// in a pane before the call returns, so `didPlace` has nothing left to
    /// file — and if the placer then fails to name the new pane by difference
    /// it would cancel a placement that already happened, leaving a panel on
    /// screen in a pane the extension cannot reveal or close.
    @Test("the pane that claimed a panel mid-split can be named")
    func theClaimingPaneCanBeNamed() {
        let project = Self.makeWorkspace()
        let registry = ComposableTabsViewRegistry()
        let serializer = WebviewPanelSerializer(registry: registry) { _ in nil }
        let panel = makePanel()
        let nodeID = UUID()

        serializer.prepareToPlace(panel, panesBeforeSplit: [])
        #expect(serializer.nodeIDOfPaneThatClaimed(panel) == nil)

        _ = makeContent(registry, nodeID: nodeID, project: project)

        #expect(serializer.nodeIDOfPaneThatClaimed(panel) == nodeID)
    }

    // MARK: - Rebuilding a pane from what was written down

    @Test("a stored pane is rebuilt from the state it saved")
    func aStoredPaneComesBack() throws {
        let project = Self.makeWorkspace()
        let registry = ComposableTabsViewRegistry()
        let nodeID = UUID()
        let saved = WebviewPanelState(
            viewType: "markdown.preview", title: "Preview README.md",
            state: #"{"scrollTop":420}"#,
            options: WebviewPanelOptions(
                enableScripts: true, enableForms: nil, localResourceRoots: nil))
        project.setPaneState(
            nodeID: nodeID, key: WebviewPanelSerializer.paneStateKey, value: try saved.encoded())

        var asked: [WebviewPanelState] = []
        let serializer = WebviewPanelSerializer(registry: registry) { state in
            asked.append(state)
            return WebviewPanelViewController(restoring: state, localResourceRoots: [])
        }

        let content = makeContent(registry, nodeID: nodeID, project: project)
        // The registry captures the serializer weakly, so this binding is the
        // only thing keeping it alive long enough to answer — not decoration.
        withExtendedLifetime(serializer) {}

        #expect(asked == [saved])
        let panel = try #require(content as? WebviewPanelViewController)
        #expect(panel.viewType == "markdown.preview")
        #expect(panel.title == "Preview README.md")
        // Seeded before the first document load, which is what makes the
        // page's own `getState()` right on the very first render.
        #expect(panel.state == #"{"scrollTop":420}"#)
        // Read back through `restorationState` rather than the stored options:
        // that is the property a later save actually writes, so this asserts
        // the round trip closes rather than that one ivar was assigned.
        #expect(panel.restorationState.options.enableScripts)
    }

    /// The extension was uninstalled or disabled since the layout was saved.
    /// That is a real state, and it costs the pane's content — never the pane,
    /// and never the window's layout.
    @Test("a view type nobody claims leaves the pane empty rather than losing it")
    func anUnclaimedViewTypeLeavesAPlaceholder() throws {
        let project = Self.makeWorkspace()
        let registry = ComposableTabsViewRegistry()
        let nodeID = UUID()
        let saved = WebviewPanelState(
            viewType: "gone.preview", title: "Preview", state: nil,
            options: WebviewPanelOptions(
                enableScripts: nil, enableForms: nil, localResourceRoots: nil))
        project.setPaneState(
            nodeID: nodeID, key: WebviewPanelSerializer.paneStateKey, value: try saved.encoded())
        let serializer = WebviewPanelSerializer(registry: registry) { _ in nil }
        _ = serializer

        #expect(makeContent(registry, nodeID: nodeID, project: project)
            is PlaceholderPaneViewController)
    }

    @Test("a pane with nothing stored comes back empty")
    func aPaneWithNoStoredPanelComesBackEmpty() {
        let project = Self.makeWorkspace()
        let registry = ComposableTabsViewRegistry()
        var asked = 0
        let serializer = WebviewPanelSerializer(registry: registry) { _ in
            asked += 1
            return nil
        }
        _ = serializer

        #expect(makeContent(registry, nodeID: UUID(), project: project)
            is PlaceholderPaneViewController)
        #expect(asked == 0)
    }

    /// A corrupted row should cost one pane's content, not the window it is in
    /// — and certainly not a trap.
    @Test("a stored panel this app cannot read comes back empty")
    func anUnreadableRowComesBackEmpty() {
        let project = Self.makeWorkspace()
        let registry = ComposableTabsViewRegistry()
        let nodeID = UUID()
        project.setPaneState(
            nodeID: nodeID, key: WebviewPanelSerializer.paneStateKey, value: "not a panel")
        let serializer = WebviewPanelSerializer(registry: registry) { _ in
            Issue.record("a row that cannot be decoded must not reach the restorer")
            return nil
        }
        _ = serializer

        #expect(makeContent(registry, nodeID: nodeID, project: project)
            is PlaceholderPaneViewController)
    }

    /// A restored panel is written down again on the spot, so a panel whose
    /// extension never retitles it and never calls `setState` still survives
    /// the *next* quit rather than only the first.
    @Test("a restored panel is written down again for the next quit")
    func aRestoredPanelIsPersistedAgain() throws {
        let project = Self.makeWorkspace()
        let registry = ComposableTabsViewRegistry()
        let nodeID = UUID()
        let saved = WebviewPanelState(
            viewType: "markdown.preview", title: "Preview", state: nil,
            options: WebviewPanelOptions(
                enableScripts: nil, enableForms: nil, localResourceRoots: nil))
        project.setPaneState(
            nodeID: nodeID, key: WebviewPanelSerializer.paneStateKey, value: try saved.encoded())
        let serializer = WebviewPanelSerializer(registry: registry) { state in
            WebviewPanelViewController(restoring: state, localResourceRoots: [])
        }
        _ = serializer

        let content = makeContent(registry, nodeID: nodeID, project: project)
        let panel = try #require(content as? WebviewPanelViewController)
        panel.title = "Preview CHANGELOG.md"

        #expect(try storedState(project, nodeID)?.title == "Preview CHANGELOG.md")
    }
}
