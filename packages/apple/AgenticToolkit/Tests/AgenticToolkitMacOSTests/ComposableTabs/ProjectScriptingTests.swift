import AppKit
import XCTest
import AgenticDeveloperToolkitUI
@testable import AgenticToolkitMacOS

/// The AppleScript vocabulary for project windows, tabs and panes.
///
/// These test the layer the commands call, not `NSScriptCommand` itself: a
/// command subclass here is a lookup and one method call, and standing up a
/// synthetic `NSScriptCommand` would test Cocoa Scripting rather than us.
@MainActor
final class ProjectScriptingTests: XCTestCase {

    private let alpha = ComposableTabsViewID("test.alpha")

    /// Content with a selection to name and a search to receive, so a wrapper
    /// that reports a selection and one that routes a query are both
    /// observable rather than inferred.
    private final class SelectingContent: NSViewController, PaneSelectionDescribing, PaneSearchable {
        var paneSelectionDescription: String? = "src/main.swift"
        var onPaneSelectionChange: (() -> Void)?
        var paneSearchPlaceholder = "Search Alpha"
        private(set) var queries: [String] = []
        func paneSearch(for query: String) { self.queries.append(query) }
    }

    /// Every content this suite's registry has vended, in creation order, so a
    /// test can ask the pane's own content what it was told.
    private var contents: [SelectingContent] = []

    /// Layout first, then the workspace: `ProjectWorkspace` captures
    /// `ComposableTabsLayout.current` in its initialiser.
    private func makeProject(named name: String = "api-server") -> ProjectWorkspace {
        let registry = ComposableTabsViewRegistry()
        registry.register(alpha, descriptor: .init(displayName: "Alpha", minimumThickness: 150)) { [weak self] _ in
            let content = SelectingContent()
            content.view = NSView()
            self?.contents.append(content)
            return content
        }
        // swiftlint:disable:next force_try
        ComposableTabsLayout.install(try! ComposableTabsLayout(
            registry: registry,
            spec: .pane(alpha, allows: [.unbounded(alpha)])
        ))
        return ProjectWindowTestSupport.makeProject(label: "ProjectScriptingTests", named: name)
    }

    private func makeController(for project: ProjectWorkspace) -> ComposableTabsWindowController {
        let controller = ComposableTabsWindowController(project: project)
        controller.showWindow(nil)
        return controller
    }

    /// A window whose one tab holds two panes side by side.
    ///
    /// Seeded through the database rather than by splitting a live pane, the
    /// same way `ProjectWindowSearchTests` does: a pane in a *horizontal*
    /// split is the only shape in which the host will honour a minimize at
    /// all, and a root leaf — which is what a default project has — refuses
    /// every edge.
    private func makeTwoPaneController() -> ComposableTabsWindowController {
        let project = makeProject()
        let tabID = UUID()
        project.persistTabs(
            [TabRecord(
                id: tabID,
                edge: .top,
                title: "Tab 1",
                root: .split(
                    orientation: .horizontal,
                    first: .leaf(id: UUID(), contentType: alpha),
                    second: .leaf(id: UUID(), contentType: alpha)
                )
            )],
            activeTabID: tabID,
            enabledEdges: [.top]
        )
        return makeController(for: project)
    }

    /// A window with two project tabs on one edge, the first of them selected —
    /// so the second tab's panes exist but are not in the view hierarchy.
    private func makeTwoTabController() -> ComposableTabsWindowController {
        let project = makeProject()
        let first = UUID()
        let second = UUID()
        project.persistTabs(
            [
                TabRecord(id: first, edge: .top, title: "Tab 1",
                          root: .leaf(id: UUID(), contentType: alpha)),
                TabRecord(id: second, edge: .top, title: "Tab 2",
                          root: .leaf(id: UUID(), contentType: alpha))
            ],
            activeTabID: first,
            enabledEdges: [.top]
        )
        return makeController(for: project)
    }

    nonisolated override func tearDown() {
        ComposableTabsLayout.install(nil)
        super.tearDown()
    }

    // MARK: - Panes

    func testAPanesIdIsThePersistedNodeID() throws {
        let controller = makeController(for: makeProject())
        let pane = try XCTUnwrap(controller.allPanes().first)
        let scriptable = ScriptablePane(pane: pane)

        XCTAssertEqual(scriptable.uniqueID, pane.nodeID.uuidString)
    }

    func testAPaneReportsItsNameProjectTabAndSelection() throws {
        let controller = makeController(for: makeProject())
        let pane = try XCTUnwrap(controller.allPanes().first)
        let scriptable = ScriptablePane(pane: pane)

        XCTAssertEqual(scriptable.name, pane.resolvedTitle)
        XCTAssertFalse(scriptable.name.isEmpty)
        XCTAssertEqual(scriptable.paneProject, "api-server")
        XCTAssertEqual(scriptable.paneTab, "Tab 1")
        XCTAssertEqual(scriptable.paneSelection, "src/main.swift")
    }

    /// A pane on a tab that is not in front is still in a project and still in
    /// a tab, and the dictionary promises to name both.
    ///
    /// It has no `view.window` until its tab is selected, so a wrapper that
    /// asked the view hierarchy would answer `""` for every pane behind the
    /// front tab — which is most of them in a real window.
    func testAPaneOnABackgroundTabStillNamesItsProjectAndTab() throws {
        let controller = makeTwoTabController()
        ProjectWindowManager.shared.adoptForScripting(controller)
        defer { ProjectWindowManager.shared.forgetForScripting(controller) }

        let panes = ProjectWindowManager.shared.scriptablePanes
        XCTAssertEqual(panes.count, 2)
        XCTAssertEqual(panes.map(\.paneProject), ["api-server", "api-server"])
        XCTAssertEqual(panes.map(\.paneTab), ["Tab 1", "Tab 2"])
    }

    /// `minimized` is the edge's own name, and `"no"` when it is not
    /// minimized — a string rather than a boolean, because "minimized" and
    /// "minimized *where*" are one fact and splitting them into two properties
    /// makes them possible to disagree.
    func testMinimizedIsTheEdgeNameOrNo() throws {
        let controller = makeController(for: makeProject())
        let pane = try XCTUnwrap(controller.allPanes().first)
        let scriptable = ScriptablePane(pane: pane)
        XCTAssertEqual(scriptable.paneMinimized, "no")

        pane.setMinimized(to: .leading)
        XCTAssertEqual(scriptable.paneMinimized, "leading")

        pane.setMinimized(to: nil)
        XCTAssertEqual(scriptable.paneMinimized, "no")
    }

    func testZoomedIsABoolean() throws {
        let controller = makeTwoPaneController()
        let pane = try XCTUnwrap(controller.allPanes().first)
        let scriptable = ScriptablePane(pane: pane)
        XCTAssertFalse(scriptable.paneZoomed)

        scriptable.zoomPane()
        XCTAssertTrue(scriptable.paneZoomed)

        scriptable.zoomPane()
        XCTAssertFalse(scriptable.paneZoomed)
    }

    /// Not "the pane did not move": a wrapper whose `minimizePane` is an empty
    /// function passes that. The pane has to actually reach the edge the
    /// script asked for, by the same path the title-bar arrow takes.
    func testMinimizingThroughTheScriptableWrapperGoesThroughTheHost() throws {
        let controller = makeTwoPaneController()
        let panes = controller.allPanes()
        XCTAssertEqual(panes.count, 2, "the seeded two-pane layout did not survive being loaded")
        let scriptable = ScriptablePane(pane: try XCTUnwrap(panes.first))

        scriptable.minimizePane(to: "leading")
        XCTAssertEqual(scriptable.paneMinimized, "leading")

        scriptable.minimizePane(to: "none")
        XCTAssertEqual(scriptable.paneMinimized, "no")
    }

    /// Starting from a pane that really is minimized, so "unchanged" and
    /// "restored" are answers this can tell apart.
    func testAnUnknownEdgeNameRestoresRatherThanGuessing() throws {
        let controller = makeTwoPaneController()
        let scriptable = ScriptablePane(pane: try XCTUnwrap(controller.allPanes().first))
        scriptable.minimizePane(to: "leading")
        XCTAssertEqual(scriptable.paneMinimized, "leading")

        scriptable.minimizePane(to: "sideways")
        XCTAssertEqual(scriptable.paneMinimized, "no")
    }

    /// A root leaf has no edges available, so the host refuses and the pane
    /// stays put. That refusal is the host's, not the wrapper's.
    func testAHostThatRefusesLeavesThePaneWhereItWas() throws {
        let controller = makeController(for: makeProject())
        let scriptable = ScriptablePane(pane: try XCTUnwrap(controller.allPanes().first))

        scriptable.minimizePane(to: "leading")

        XCTAssertEqual(scriptable.paneMinimized, "no")
    }

    // MARK: - Tabs

    func testATabsIdIsThePersistedTabID() throws {
        let controller = makeController(for: makeProject())
        let tab = try XCTUnwrap(controller.scriptingTabs.first)

        XCTAssertEqual(tab.name, "Tab 1")
        XCTAssertEqual(tab.tabEdges, ["top"])
        XCTAssertEqual(tab.tabProject, "api-server")
        XCTAssertFalse(tab.uniqueID.isEmpty)
    }

    /// A project-level tab is a group with one member per enabled edge, all
    /// sharing a title. Vending the members would show a script two tabs both
    /// called "Tab 1" where the reader sees one.
    func testAProjectTabIsOneGroupAcrossEveryEdgeItIsDrawnOn() throws {
        let controller = makeController(for: makeProject())
        controller.setEdgeEnabled(.right, true)

        XCTAssertEqual(controller.scriptingTabs.count, 1)
        let tab = try XCTUnwrap(controller.scriptingTabs.first)
        XCTAssertEqual(tab.tabEdges, ["top", "right"])
    }

    /// Disabling an edge keeps its member tabs, so that re-enabling restores
    /// them — but a script must see what the reader sees, and the reader sees
    /// no tab bar and no panes there.
    func testADisabledEdgesPanesAreNotVended() {
        let controller = makeController(for: makeProject())
        XCTAssertEqual(controller.allPanes().count, 1)

        controller.setEdgeEnabled(.right, true)
        XCTAssertEqual(controller.allPanes().count, 2)

        controller.setEdgeEnabled(.right, false)
        XCTAssertEqual(controller.allPanes().count, 1)
        XCTAssertEqual(controller.scriptingTabs.count, 1)
    }

    // MARK: - The window

    func testAWindowsIdIsTheProjectID() {
        let project = makeProject()
        let controller = makeController(for: project)
        let scriptable = ScriptableProjectWindow(controller: controller)

        XCTAssertEqual(scriptable.uniqueID, project.id.uuidString)
        XCTAssertEqual(scriptable.name, "api-server")
    }

    func testHelpVisibleIsReadableAndWritable() {
        let controller = makeController(for: makeProject())
        let scriptable = ScriptableProjectWindow(controller: controller)
        XCTAssertFalse(scriptable.helpVisible)

        scriptable.helpVisible = true
        XCTAssertTrue(controller.isHelpVisible)
        XCTAssertEqual(scriptable.drawerTab, "help")

        scriptable.helpVisible = false
        XCTAssertFalse(controller.isHelpVisible)
    }

    /// Saying it twice means the same as saying it once: the setter is a
    /// setting, not a toggle wearing a boolean's clothes.
    func testSettingHelpVisibleTwiceLeavesItVisible() {
        let controller = makeController(for: makeProject())
        let scriptable = ScriptableProjectWindow(controller: controller)

        scriptable.helpVisible = true
        scriptable.helpVisible = true

        XCTAssertTrue(controller.isHelpVisible)
    }

    /// Setting the query has to *search*, not just fill the field in — a script
    /// that sets it and reads the pane back would otherwise see nothing.
    func testTheSearchQueryRoundTripsAndReachesThePane() throws {
        let controller = makeController(for: makeProject())
        ProjectWindowTestSupport.buildToolbarItems(controller)
        let scriptable = ScriptableProjectWindow(controller: controller)
        let content = try XCTUnwrap(contents.first)

        scriptable.searchQuery = "main"

        XCTAssertEqual(scriptable.searchQuery, "main")
        XCTAssertEqual(controller.searchField?.stringValue, "main")
        XCTAssertEqual(content.queries, ["main"])
    }

    func testTheSelectedTabIsReadableAndWritable() throws {
        let controller = makeController(for: makeProject())
        let scriptable = ScriptableProjectWindow(controller: controller)
        let first = try XCTUnwrap(controller.scriptingTabs.first)

        XCTAssertEqual(scriptable.selectedTab, first.uniqueID)

        // An id that names no tab is ignored rather than deselecting.
        scriptable.selectedTab = UUID().uuidString
        XCTAssertEqual(scriptable.selectedTab, first.uniqueID)
    }

    // MARK: - The lookups the bridge uses

    func testTheManagerFindsAPaneByItsID() throws {
        let project = makeProject()
        let controller = makeController(for: project)
        ProjectWindowManager.shared.adoptForScripting(controller)
        defer { ProjectWindowManager.shared.forgetForScripting(controller) }

        let pane = try XCTUnwrap(controller.allPanes().first)
        let found = ProjectWindowManager.shared.scriptablePane(uniqueID: pane.nodeID.uuidString)

        XCTAssertEqual(found?.uniqueID, pane.nodeID.uuidString)
        XCTAssertNil(ProjectWindowManager.shared.scriptablePane(uniqueID: UUID().uuidString))
    }

    func testTheManagerListsWindowsTabsAndPanes() {
        let controller = makeController(for: makeProject())
        ProjectWindowManager.shared.adoptForScripting(controller)
        defer { ProjectWindowManager.shared.forgetForScripting(controller) }

        XCTAssertEqual(ProjectWindowManager.shared.scriptableProjectWindows.count, 1)
        XCTAssertEqual(ProjectWindowManager.shared.scriptableProjectTabs.count, 1)
        XCTAssertEqual(ProjectWindowManager.shared.scriptablePanes.count, 1)

        // A second edge draws the same project tab twice and gives it a second
        // pane. One tab, two panes — not two tabs.
        controller.setEdgeEnabled(.right, true)
        XCTAssertEqual(ProjectWindowManager.shared.scriptableProjectTabs.count, 1)
        XCTAssertEqual(ProjectWindowManager.shared.scriptablePanes.count, 2)
    }

    /// Adopting twice leaves one entry, and forgetting a controller the
    /// manager never had leaves the ones it does have alone.
    func testAdoptingForScriptingIsIdempotent() {
        let controller = makeController(for: makeProject())
        ProjectWindowManager.shared.adoptForScripting(controller)
        ProjectWindowManager.shared.adoptForScripting(controller)
        defer { ProjectWindowManager.shared.forgetForScripting(controller) }

        XCTAssertEqual(ProjectWindowManager.shared.scriptableProjectWindows.count, 1)
    }

    func testTheManagerFindsATabAndAWindowByID() throws {
        let project = makeProject()
        let controller = makeController(for: project)
        ProjectWindowManager.shared.adoptForScripting(controller)
        defer { ProjectWindowManager.shared.forgetForScripting(controller) }

        let tab = try XCTUnwrap(controller.scriptingTabs.first)
        XCTAssertEqual(
            ProjectWindowManager.shared.scriptableProjectTab(uniqueID: tab.uniqueID)?.uniqueID,
            tab.uniqueID)
        XCTAssertEqual(
            ProjectWindowManager.shared.scriptableProjectWindow(uniqueID: project.id.uuidString)?.name,
            "api-server")
        XCTAssertNil(ProjectWindowManager.shared.scriptableProjectTab(uniqueID: UUID().uuidString))
        XCTAssertNil(ProjectWindowManager.shared.scriptableProjectWindow(uniqueID: UUID().uuidString))
    }
}
