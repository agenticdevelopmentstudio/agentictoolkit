import AgenticToolkitCore
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class ComposableTabsTabItemDataSourceTests: XCTestCase {
    private final class RecordingSource: ComposableTabsTabItemDataSource {
        var seen: [(record: TabRecord, edge: Edge)] = []
        var hosted: [UUID: NSViewController] = [:]
        func composableTabsWindowController(_ controller: ComposableTabsWindowController,
                                            tabItemFor record: TabRecord, on edge: Edge) -> TabItem {
            seen.append((record, edge))
            let item = NSViewController()
            item.view = NSView()
            item.title = "hosted-\(record.title)"
            hosted[record.id] = item
            return .viewController(item)
        }
    }

    private let alpha = ComposableTabsViewID("test.alpha")

    /// Layout first, then the workspace: `ProjectWorkspace` captures
    /// `ComposableTabsLayout.current` in its initialiser. Same shape as
    /// `ProjectScriptingTests.makeProject()`.
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
        return ProjectWindowTestSupport.makeProject(label: "ComposableTabsTabItemDataSourceTests")
    }

    override func tearDown() {
        ComposableTabsLayout.install(nil)
        super.tearDown()
    }

    func testStoredTabsAreInstalledThroughTheDataSource() {
        let project = makeProject()
        let record = TabRecord(edge: .left, title: "main", root: .leaf(contentType: alpha))
        project.persistTabs([record], activeTabID: record.id, enabledEdges: [.left])
        let source = RecordingSource()

        let controller = ComposableTabsWindowController(project: project)
        controller.tabItemDataSource = source
        controller.showWindow(nil)
        controller.reloadTabs()

        XCTAssertEqual(source.seen.map(\.record.id), [record.id])
        XCTAssertEqual(source.seen.map(\.edge), [.left])
        XCTAssertTrue(source.hosted[record.id]?.parent != nil)
        XCTAssertEqual(controller.scriptingTabs(branch: { _ in nil }).map(\.name), ["hosted-main"])
        controller.close()
    }

    func testWithoutADataSourceTabsKeepTheirTitles() {
        let project = makeProject()
        let record = TabRecord(edge: .left, title: "main", root: .leaf(contentType: alpha))
        project.persistTabs([record], activeTabID: record.id, enabledEdges: [.left])
        let controller = ComposableTabsWindowController(project: project)
        controller.showWindow(nil)
        controller.reloadTabs()
        XCTAssertEqual(controller.scriptingTabs(branch: { _ in nil }).map(\.name), ["main"])
        controller.close()
    }

    /// Ruling A: `reloadTabs()` must not let a mid-loop `didSelectTab` persist
    /// a shrinking tab set. Two tabs on the same edge, the first active:
    /// removing it activates the second and (unguarded) persists `[second]`
    /// before the second is also removed — silently losing the first tab
    /// forever. Both must survive a reload with their original ids.
    func testReloadTabsPreservesBothTabsAcrossTheRemovalLoop() {
        let project = makeProject()
        let first = TabRecord(edge: .left, title: "first", root: .leaf(contentType: alpha))
        let second = TabRecord(edge: .left, title: "second", root: .leaf(contentType: alpha))
        project.persistTabs([first, second], activeTabID: first.id, enabledEdges: [.left])

        let controller = ComposableTabsWindowController(project: project)
        controller.showWindow(nil)
        controller.reloadTabs()

        let reloaded = project.storedTabs()
        XCTAssertEqual(Set(reloaded?.tabs.map(\.id) ?? []), Set([first.id, second.id]))
        controller.close()
    }

    /// A window with one stored tab on the left edge, already reloaded
    /// through `source`, and the count of records the source has been asked
    /// about so far. The three tests below each exercise one of the install
    /// paths from that point.
    private func makeReloadedWindow() -> (ComposableTabsWindowController, RecordingSource, Int) {
        let project = makeProject()
        let record = TabRecord(edge: .left, title: "main", root: .leaf(contentType: alpha))
        project.persistTabs([record], activeTabID: record.id, enabledEdges: [.left])
        let source = RecordingSource()
        let controller = ComposableTabsWindowController(project: project)
        controller.tabItemDataSource = source
        controller.showWindow(nil)
        controller.reloadTabs()
        return (controller, source, source.seen.count)
    }

    /// `addTabGroup()` is the second install path, and the only one a user
    /// reaches by clicking "+". Its argument is the tab bar's own controller,
    /// which the implementation ignores.
    func testANewTabGroupIsInstalledThroughTheDataSource() {
        let (controller, source, before) = makeReloadedWindow()

        controller.multiTabbedViewControllerNeedsNewTab(MultiTabbedViewController())

        XCTAssertEqual(source.seen.count, before + 1)
        XCTAssertEqual(source.seen.last?.edge, .left)
        XCTAssertEqual(source.seen.last?.record.title, "Tab 2")
        // Storage writes `nil` for the project's own directory, so a record
        // built for a brand-new tab must say `nil` too, or a data source that
        // branches on nil sees the same tab two ways.
        XCTAssertNil(source.seen.last?.record.workingDirectory)
        controller.close()
    }

    /// `topUpTabs(on:)` is the third install path: enabling an edge gives
    /// every existing group a member on it.
    func testEnablingAnEdgeTopsUpThroughTheDataSource() {
        let (controller, source, before) = makeReloadedWindow()

        controller.setEdgeEnabled(.right, true)

        XCTAssertEqual(source.seen.count, before + 1)
        XCTAssertEqual(source.seen.last?.edge, .right)
        XCTAssertEqual(source.seen.last?.record.title, "main")
        controller.close()
    }

    /// A hosted item's title is whatever its view controller reports, and
    /// `RecordingSource` derives it from the record — so persisting
    /// `tab.title` would rewrite the stored `"main"` as `"hosted-main"`, and
    /// the next persist as `"hosted-hosted-main"`. The stored title is the
    /// group's, permanently.
    func testPersistingKeepsTheStoredTitleNotTheHostedItems() {
        let (controller, _, _) = makeReloadedWindow()
        let project = controller.project

        controller.setEdgeEnabled(.right, true)
        XCTAssertEqual(Set(project.storedTabs()?.tabs.map(\.title) ?? []), ["main"])

        controller.setEdgeEnabled(.right, false)
        controller.setEdgeEnabled(.right, true)
        XCTAssertEqual(Set(project.storedTabs()?.tabs.map(\.title) ?? []), ["main"])
        controller.close()
    }
}
