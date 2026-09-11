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
    ///
    /// The two leaf ids come back with it: they are what the panes were
    /// *persisted* under, so a test can assert an id against the value that
    /// went into the database rather than against the expression that reads it
    /// out again.
    private func makeTwoPaneController() -> (
        controller: ComposableTabsWindowController, firstPane: UUID, secondPane: UUID
    ) {
        let project = makeProject()
        let tabID = UUID()
        let firstPane = UUID()
        let secondPane = UUID()
        project.persistTabs(
            [TabRecord(
                id: tabID,
                edge: .top,
                title: "Tab 1",
                root: .split(
                    orientation: .horizontal,
                    first: .leaf(id: firstPane, contentType: alpha),
                    second: .leaf(id: secondPane, contentType: alpha)
                )
            )],
            activeTabID: tabID,
            enabledEdges: [.top]
        )
        return (makeController(for: project), firstPane, secondPane)
    }

    /// A window with two project tabs on one edge, the first of them selected —
    /// so the second tab's panes exist but are not in the view hierarchy.
    ///
    /// Both tab ids come back: `selected tab` is declared `rw` and a test that
    /// cannot name the *other* tab can only ever write an id the setter
    /// rejects, which is how the write path went uncovered.
    private func makeTwoTabController() -> (
        controller: ComposableTabsWindowController, first: UUID, second: UUID
    ) {
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
        return (makeController(for: project), first, second)
    }

    nonisolated override func tearDown() {
        ComposableTabsLayout.install(nil)
        super.tearDown()
    }

    // MARK: - Panes

    /// The sdef promises a pane id is "stable across relaunches". So this
    /// asserts the ids the leaves were *persisted* under, read back off a
    /// window built from that database — not `pane.nodeID` restated back at
    /// the expression that produced it.
    func testAPanesIdIsThePersistedNodeID() {
        let (controller, firstPane, secondPane) = makeTwoPaneController()

        XCTAssertEqual(
            controller.allPanes().map { ScriptablePane(pane: $0, in: controller).uniqueID },
            [firstPane.uuidString, secondPane.uuidString])
    }

    func testAPaneReportsItsNameProjectTabAndSelection() throws {
        let controller = makeController(for: makeProject())
        let pane = try XCTUnwrap(controller.allPanes().first)
        let scriptable = ScriptablePane(pane: pane, in: controller)

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
        let (controller, _, _) = makeTwoTabController()
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
        let scriptable = ScriptablePane(pane: pane, in: controller)
        XCTAssertEqual(scriptable.paneMinimized, "no")

        pane.setMinimized(to: .leading)
        XCTAssertEqual(scriptable.paneMinimized, "leading")

        pane.setMinimized(to: nil)
        XCTAssertEqual(scriptable.paneMinimized, "no")
    }

    func testZoomedIsABoolean() throws {
        let (controller, _, _) = makeTwoPaneController()
        let pane = try XCTUnwrap(controller.allPanes().first)
        let scriptable = ScriptablePane(pane: pane, in: controller)
        XCTAssertFalse(scriptable.paneZoomed)

        scriptable.zoomPane()
        XCTAssertTrue(scriptable.paneZoomed)

        scriptable.zoomPane()
        XCTAssertFalse(scriptable.paneZoomed)
    }

    /// `close pane` is the one command that destroys something, and an empty
    /// `closePane()` leaves every other test in this suite green while the
    /// command still reports `true`.
    ///
    /// The count alone is not enough either: closing the *wrong* pane also
    /// leaves one behind. The survivor has to be the pane that was not asked
    /// to close.
    func testClosingThroughTheScriptableWrapperRemovesThatPane() throws {
        let (controller, firstPane, secondPane) = makeTwoPaneController()
        let panes = controller.allPanes()
        XCTAssertEqual(panes.count, 2, "the seeded two-pane layout did not survive being loaded")
        let scriptable = ScriptablePane(pane: try XCTUnwrap(panes.first), in: controller)
        XCTAssertEqual(scriptable.uniqueID, firstPane.uuidString)

        scriptable.closePane()

        let survivors = controller.allPanes()
        XCTAssertEqual(survivors.count, 1)
        XCTAssertEqual(survivors.first?.nodeID, secondPane)
    }

    /// Not "the pane did not move": a wrapper whose `minimizePane` is an empty
    /// function passes that. The pane has to actually reach the edge the
    /// script asked for, by the same path the title-bar arrow takes.
    func testMinimizingThroughTheScriptableWrapperGoesThroughTheHost() throws {
        let (controller, _, _) = makeTwoPaneController()
        let panes = controller.allPanes()
        XCTAssertEqual(panes.count, 2, "the seeded two-pane layout did not survive being loaded")
        let scriptable = ScriptablePane(pane: try XCTUnwrap(panes.first), in: controller)

        scriptable.minimizePane(to: "leading")
        XCTAssertEqual(scriptable.paneMinimized, "leading")

        scriptable.minimizePane(to: "none")
        XCTAssertEqual(scriptable.paneMinimized, "no")
    }

    /// Starting from a pane that really is minimized, so "unchanged" and
    /// "restored" are answers this can tell apart.
    func testAnUnknownEdgeNameRestoresRatherThanGuessing() throws {
        let (controller, _, _) = makeTwoPaneController()
        let scriptable = ScriptablePane(pane: try XCTUnwrap(controller.allPanes().first), in: controller)
        scriptable.minimizePane(to: "leading")
        XCTAssertEqual(scriptable.paneMinimized, "leading")

        scriptable.minimizePane(to: "sideways")
        XCTAssertEqual(scriptable.paneMinimized, "no")
    }

    /// A root leaf has no edges available, so the host refuses and the pane
    /// stays put. That refusal is the host's, not the wrapper's.
    func testAHostThatRefusesLeavesThePaneWhereItWas() throws {
        let controller = makeController(for: makeProject())
        let scriptable = ScriptablePane(pane: try XCTUnwrap(controller.allPanes().first), in: controller)

        scriptable.minimizePane(to: "leading")

        XCTAssertEqual(scriptable.paneMinimized, "no")
    }

    // MARK: - What `close pane` reports

    /// A hand-built command, since Cocoa Scripting is not running here.
    /// `MainActorScriptCommandTests` uses the same shape and explains why the
    /// four-char codes are arbitrary: nothing dispatches this by AppleEvent.
    private func makeCloseCommand(id identifier: String) throws -> ClosePaneCommand {
        let description = try XCTUnwrap(NSScriptCommandDescription(
            suiteName: "AgenticTestSuite",
            commandName: "closePane",
            dictionary: [
                "CommandClass": "NSScriptCommand",
                "AppleEventCode": "clsP",
                "AppleEventClassCode": "tstS"
            ]
        ))
        let command = ClosePaneCommand(commandDescription: description)
        command.directParameter = identifier
        return command
    }

    /// The spec vetoes closing a tab's last pane, so `remove(_:)` declines and
    /// the pane is still there afterwards. The command used to return `true`
    /// regardless, which is a script being told a pane is gone while looking
    /// straight at it.
    func testClosePaneReportsFalseWhenTheTreeRefusesTheClose() throws {
        let refusals = recordingRefusals()
        let controller = makeController(for: makeProject())
        ProjectWindowManager.shared.adoptForScripting(controller)
        defer { ProjectWindowManager.shared.forgetForScripting(controller) }
        let pane = try XCTUnwrap(controller.allPanes().first)

        let command = try makeCloseCommand(id: pane.nodeID.uuidString)
        let result = command.performDefaultImplementation()

        XCTAssertEqual(result as? Bool, false, "the pane is still in the window")
        XCTAssertEqual(controller.allPanes().count, 1)
        XCTAssertEqual(command.scriptErrorNumber, 0,
                       "a veto is a legitimate answer; the error channel is for \"no such pane\"")
        XCTAssertEqual(refusals.count, 1,
                       "the veto reached the same announcement a clicked close button would")
    }

    func testClosePaneReportsTrueWhenThePaneIsActuallyGone() throws {
        let (controller, firstPane, secondPane) = makeTwoPaneController()
        ProjectWindowManager.shared.adoptForScripting(controller)
        defer { ProjectWindowManager.shared.forgetForScripting(controller) }
        XCTAssertEqual(controller.allPanes().count, 2)

        let command = try makeCloseCommand(id: firstPane.uuidString)
        let result = command.performDefaultImplementation()

        XCTAssertEqual(result as? Bool, true)
        XCTAssertEqual(controller.allPanes().map(\.nodeID), [secondPane])
        XCTAssertEqual(command.scriptErrorNumber, 0)
    }

    /// Round 1's rule, pinned so the honesty fix above does not quietly swap
    /// which channel a missing pane comes back on.
    func testClosePaneStillRaisesNoSuchObjectForAPaneThatDoesNotExist() throws {
        let controller = makeController(for: makeProject())
        ProjectWindowManager.shared.adoptForScripting(controller)
        defer { ProjectWindowManager.shared.forgetForScripting(controller) }

        let command = try makeCloseCommand(id: UUID().uuidString)
        let result = command.performDefaultImplementation()

        XCTAssertEqual(result as? Bool, false)
        XCTAssertEqual(command.scriptErrorNumber, Int(errAENoSuchObject))
    }

    // MARK: - Tabs

    /// The sdef promises a tab id is "stable across relaunches". These are the
    /// group ids the two tabs were persisted under, in order — non-empty was
    /// the whole of what this used to assert, and every wrong id is non-empty.
    func testATabsIdIsThePersistedTabID() throws {
        let (controller, first, second) = makeTwoTabController()

        XCTAssertEqual(
            controller.scriptingTabs(branch: { _ in nil }).map(\.uniqueID),
            [first.uuidString, second.uuidString])

        let tab = try XCTUnwrap(controller.scriptingTabs(branch: { _ in nil }).first)
        XCTAssertEqual(tab.name, "Tab 1")
        XCTAssertEqual(tab.tabEdges, ["top"])
        XCTAssertEqual(tab.tabProject, "api-server")
    }

    /// A project-level tab is a group with one member per enabled edge, all
    /// sharing a title. Vending the members would show a script two tabs both
    /// called "Tab 1" where the reader sees one.
    func testAProjectTabIsOneGroupAcrossEveryEdgeItIsDrawnOn() throws {
        let controller = makeController(for: makeProject())
        controller.setEdgeEnabled(.right, true)

        XCTAssertEqual(controller.scriptingTabs(branch: { _ in nil }).count, 1)
        let tab = try XCTUnwrap(controller.scriptingTabs(branch: { _ in nil }).first)
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
        XCTAssertEqual(controller.scriptingTabs(branch: { _ in nil }).count, 1)
    }

    // MARK: - The window

    /// Read back out of `git_repo` rather than off the workspace this test is
    /// holding: "stable across relaunches" is a claim about the persisted row,
    /// and `project.id` is the very expression the window's id is read through.
    func testAWindowsIdIsTheProjectID() throws {
        let project = makeProject()
        let controller = makeController(for: project)
        let scriptable = ScriptableProjectWindow(controller: controller)
        let persisted = try XCTUnwrap(project.database.allRepos().first)

        XCTAssertEqual(scriptable.uniqueID, persisted.id.uuidString)
        XCTAssertEqual(scriptable.name, persisted.name)
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

    /// On a window with two tabs, because `selectTab(id:)` rejects an unknown
    /// id at its `guard` — so on a one-tab window the only write a test could
    /// make never reached the loop, and an empty `selectTab(id:)` passed.
    func testTheSelectedTabIsReadableAndWritable() {
        let (controller, first, second) = makeTwoTabController()
        let scriptable = ScriptableProjectWindow(controller: controller)

        XCTAssertEqual(scriptable.selectedTab, first.uuidString)

        scriptable.selectedTab = second.uuidString
        XCTAssertEqual(scriptable.selectedTab, second.uuidString)

        // An id that names no tab is ignored rather than deselecting.
        scriptable.selectedTab = UUID().uuidString
        XCTAssertEqual(scriptable.selectedTab, second.uuidString)
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

    /// Adoption undoes itself. A host that adopts a window it built and never
    /// calls `forgetForScripting` must not leave the manager naming a window
    /// that has closed — `openWindowControllers` would keep reporting it, and
    /// `openProject(_:)` would take its `if let existing` branch and try to
    /// re-show a dead controller.
    ///
    /// And the close must leave the persisted open flag alone: that flag drives
    /// `restoreOpenProjects()`, and a window this manager never opened is not
    /// one it may decide should not reopen. Planted here rather than written by
    /// the manager, so the assertion is that the close found it and left it.
    func testAnAdoptedWindowDeregistersItselfWhenItsWindowCloses() {
        let project = makeProject()
        project.setSetting(ProjectWindowManager.openWindowKey, to: "1")
        let controller = makeController(for: project)
        ProjectWindowManager.shared.adoptForScripting(controller)
        defer { ProjectWindowManager.shared.forgetForScripting(controller) }
        XCTAssertEqual(ProjectWindowManager.shared.openWindowControllers.count, 1)

        controller.close()

        XCTAssertTrue(ProjectWindowManager.shared.openWindowControllers.isEmpty,
                      "an adopted window is deregistered by its own close")
        XCTAssertEqual(project.setting(ProjectWindowManager.openWindowKey), "1",
                       "an adopted window's close is not the manager's to record")
    }

    /// Assigning the whole set is not the same as setting each edge in turn.
    /// `setEdgeEnabled` refuses to turn off the *last* enabled edge, and that
    /// rule is stated per call — so walking `Edge.allCases` in order asks to
    /// disable top before bottom exists, the refusal stands, and a script that
    /// said "bottom" gets a window with two tab bars. Every enable has to
    /// happen before any disable.
    func testMovingTheTabBarToAnotherEdgeIsOneAssignment() {
        let project = makeProject()
        let controller = makeController(for: project)
        XCTAssertEqual(controller.enabledTabEdgeNames, ["top"])

        controller.enabledTabEdgeNames = ["bottom"]

        XCTAssertEqual(controller.enabledTabEdgeNames, ["bottom"],
                       "the edge the script named, and only it")
    }

    /// The last-edge rule still holds where it is supposed to: an assignment
    /// that names no edge at all would leave the window with no tab bar, no
    /// tabs, and no control anywhere to bring one back.
    func testEmptyingTheEdgesLeavesTheLastTabBarAlone() {
        let project = makeProject()
        let controller = makeController(for: project)

        controller.enabledTabEdgeNames = []

        XCTAssertEqual(controller.enabledTabEdgeNames, ["top"])
    }

    /// `forgetForScripting` is the undo of `adoptForScripting`, and only of
    /// that. The two registrations are not interchangeable: an opened window's
    /// close observer also clears the persisted "reopen me" flag, so undoing
    /// that registration through the wrong door would leave the project marked
    /// open for ever and reopening at every launch with no window to close it.
    func testForgettingCannotUndoAWindowTheManagerOpenedItself() throws {
        let project = makeProject()
        let manager = ProjectWindowManager()
        // A registry of its own: this test is about which registration a
        // window close undoes, and nothing here reads a command back out.
        let coordinator = try ProjectsCoordinator(
            database: project.database,
            commandRegistry: CommandRegistry()
        )
        manager.attach(to: coordinator)

        manager.openProject(project.repo)
        let controller = try XCTUnwrap(manager.windowController(for: project.id))

        manager.forgetForScripting(controller)

        XCTAssertEqual(manager.openWindowControllers.count, 1,
                       "an opened window is not an adopted one, so there is nothing here to undo")

        // The proof that the *right* observer is still the one installed: it is
        // the one that clears the flag, and only an opened window has it.
        XCTAssertEqual(project.setting(ProjectWindowManager.openWindowKey), "1")
        controller.close()
        XCTAssertTrue(manager.openWindowControllers.isEmpty)
        XCTAssertNil(project.setting(ProjectWindowManager.openWindowKey))
    }

    func testTheManagerFindsATabAndAWindowByID() throws {
        let project = makeProject()
        let controller = makeController(for: project)
        ProjectWindowManager.shared.adoptForScripting(controller)
        defer { ProjectWindowManager.shared.forgetForScripting(controller) }

        let tab = try XCTUnwrap(controller.scriptingTabs(branch: { _ in nil }).first)
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
