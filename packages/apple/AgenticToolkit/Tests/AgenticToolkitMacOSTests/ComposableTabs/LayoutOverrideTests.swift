import XCTest
@testable import AgenticToolkitMacOS

/// `ProjectWorkspace.layout` is already injectable per project — but the File
/// Browser and Document panes live in the **same** project, so a project-level
/// layout cannot separate them. The override is therefore per split node,
/// consulted ahead of `project.layout`.
@MainActor
final class LayoutOverrideTests: XCTestCase {

    private static let documentID = ComposableTabsViewID("test.document")

    private func makeProject() -> ProjectWorkspace {
        ProjectWindowTestSupport.makeProject(label: "LayoutOverrideTests")
    }

    private func makeRestrictedLayout() throws -> ComposableTabsLayout {
        let registry = ComposableTabsViewRegistry()
        registry.register(Self.documentID, descriptor: .init(displayName: "Document")) { _ in
            NSViewController()
        }
        return try ComposableTabsLayout(
            registry: registry,
            spec: .split(
                axis: .horizontal,
                children: [.pane(Self.documentID)],
                allows: [.unbounded(Self.documentID), .unbounded(.placeholder)]
            )
        )
    }

    func testWithNoOverrideTheProjectsLayoutStillWins() throws {
        let project = makeProject()
        let controller = ComposableTabsViewController.make(
            from: .leaf(contentType: .placeholder),
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )
        XCTAssertNil(controller.layoutOverride)
        XCTAssertTrue(controller.layout === project.layout)
    }

    func testAnOverrideIsInheritedByNestedSplitsAndPanes() throws {
        let project = makeProject()
        let restricted = try makeRestrictedLayout()
        let controller = ComposableTabsViewController.make(
            from: .split(
                orientation: .horizontal,
                first: .leaf(contentType: Self.documentID),
                second: .leaf(contentType: Self.documentID)
            ),
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )

        controller.layoutOverride = restricted

        for child in controller.layoutChildren {
            if let pane = child as? ComposableTabsPaneViewController {
                XCTAssertTrue(pane.layoutOverride === restricted)
            }
            if let split = child as? ComposableTabsViewController {
                XCTAssertTrue(split.layoutOverride === restricted)
            }
        }
    }

    func testARestoredNonDocumentLeafResolvesToAPlaceholder() throws {
        let project = makeProject()
        let restricted = try makeRestrictedLayout()
        let controller = ComposableTabsViewController.make(
            from: .leaf(contentType: ComposableTabsViewID("terminal")),
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )
        controller.layoutOverride = restricted

        let pane = try XCTUnwrap(controller.layoutChildren.first as? ComposableTabsPaneViewController)
        pane.loadViewIfNeeded()

        XCTAssertTrue(
            pane.contentViewController is PlaceholderPaneViewController,
            "a restricted registry must constrain restore, not merely the menus"
        )
    }
}
