import AgenticToolkitCore
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// Which tab a project reopens on.
///
/// The selection is written down by `persistAllTabs()`, and `persistAllTabs()`
/// has no argument — it writes whichever tab is active the moment it is called.
/// So every assertion here is about *ordering*: the window must not write the
/// selection down at a moment when the active tab is still a placeholder, and
/// must not skip writing it down when something other than a click made the
/// choice.
@MainActor
final class ProjectTabSelectionMemoryTests: XCTestCase {

    private let alpha = ComposableTabsViewID("test.alpha")

    /// Layout first, then the workspace: `ProjectWorkspace` captures
    /// `ComposableTabsLayout.current` in its initialiser.
    private func makeProject() -> ProjectWorkspace {
        let registry = ComposableTabsViewRegistry()
        registry.register(alpha, descriptor: .init(displayName: "Alpha", minimumThickness: 150)) { _ in
            let content = NSViewController()
            content.view = NSView()
            return content
        }
        // swiftlint:disable:next force_try
        ComposableTabsLayout.install(try! ComposableTabsLayout(
            registry: registry,
            spec: .pane(alpha, allows: [.unbounded(alpha)])
        ))
        return ProjectWindowTestSupport.makeProject(label: "ProjectTabSelectionMemoryTests")
    }

    override func tearDown() {
        ComposableTabsLayout.install(nil)
        super.tearDown()
    }

    /// A launch that tops up must not forget which tab was selected.
    ///
    /// Two tabs stored on `.top` with the second one active, and `.left`
    /// enabled with no members — so opening the window creates a `.left`
    /// member per group and persists them. That write used to run before the
    /// stored selection was restored, and so recorded the tab the first
    /// `insertTab` had auto-selected: the *first* tab. The window still showed
    /// the right one, which is why this only ever surfaced one launch later.
    func testAToppedUpLaunchStillRemembersTheSelectedTab() {
        let project = makeProject()
        let first = TabRecord(edge: .top, title: "main", root: .leaf(contentType: alpha))
        let second = TabRecord(edge: .top, title: "feature", root: .leaf(contentType: alpha))
        project.persistTabs([first, second], activeTabID: second.id, enabledEdges: [.top, .left])

        let controller = ComposableTabsWindowController(project: project)
        controller.showWindow(nil)

        let stored = project.storedTabs()
        XCTAssertTrue(
            stored?.tabs.contains { $0.edge == .left } == true,
            "the top-up should have run, or this test proves nothing"
        )
        XCTAssertEqual(stored?.activeTabID, second.id)
        controller.close()
    }

    /// A tab picked by a script is remembered the same as one picked by a
    /// click. `selected tab`'s setter routes through `selectTab(id:)`, which
    /// reaches `activeTabDidChange` — a callback that deliberately only
    /// recomputes chrome — and so used to leave nothing written down.
    func testSelectingATabProgrammaticallyRemembersIt() {
        let project = makeProject()
        let first = TabRecord(edge: .top, title: "main", root: .leaf(contentType: alpha))
        let second = TabRecord(edge: .top, title: "feature", root: .leaf(contentType: alpha))
        project.persistTabs([first, second], activeTabID: first.id, enabledEdges: [.top])

        let controller = ComposableTabsWindowController(project: project)
        controller.showWindow(nil)
        let target = controller.scriptingTabs(branch: { _ in nil })
            .first { $0.name == "feature" }
        XCTAssertNotNil(target)
        controller.selectedTabIdentifier = target?.uniqueID ?? ""

        XCTAssertEqual(project.storedTabs()?.activeTabID, second.id)
        controller.close()
    }
}
