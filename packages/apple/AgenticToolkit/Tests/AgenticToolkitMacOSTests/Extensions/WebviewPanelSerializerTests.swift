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

        serializer.prepareToPlace(panel)
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

        serializer.prepareToPlace(panel)

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

        serializer.prepareToPlace(panel)
        serializer.cancelPlacement(of: panel)

        let content = makeContent(registry, nodeID: UUID(), project: project)
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

        serializer.prepareToPlace(panel)
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
        serializer.prepareToPlace(panel)
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
        serializer.prepareToPlace(panel)
        serializer.didPlace(panel, in: nodeID)
        _ = makeContent(registry, nodeID: nodeID, project: project)

        #expect(makeContent(registry, nodeID: UUID(), project: project) !== panel)
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

        #expect(asked == [saved])
        let panel = try #require(content as? WebviewPanelViewController)
        #expect(panel.viewType == "markdown.preview")
        #expect(panel.title == "Preview README.md")
        // Seeded before the first document load, which is what makes the
        // page's own `getState()` right on the very first render.
        #expect(panel.state == #"{"scrollTop":420}"#)
        #expect(panel.options.enableScripts)
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
