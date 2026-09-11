import AgenticToolkitCore
import XCTest
@testable import AgenticToolkitMacOS

final class ProjectTabReconcilerTests: XCTestCase {
    private let project = URL(fileURLWithPath: "/repo")
    private let worktree = URL(fileURLWithPath: "/repo/.claude/worktrees/tabs")
    private let leaf = LayoutNode.leaf(contentType: ComposableTabsViewID("test.editor"), paneLabel: nil)

    private var main: ProjectCheckout { ProjectCheckout(directory: project, branch: "main", isMain: true) }
    private var tabs: ProjectCheckout { ProjectCheckout(directory: worktree, branch: "tabs", isMain: false) }

    /// A fresh `LayoutNode` on every call, the way `layout.blueprint()` does
    /// in production — `LayoutNode.leaf`'s `id` defaults to a new `UUID()`.
    private func makeBlueprint() -> LayoutNode {
        LayoutNode.leaf(contentType: ComposableTabsViewID("test.editor"), paneLabel: nil)
    }

    func testAFreshProjectAddsEveryCheckout() {
        let plan = ProjectTabReconciler.plan(
            stored: [], checkouts: [main, tabs], projectDirectory: project, existsOnDisk: { _ in true }
        )
        XCTAssertTrue(plan.keep.isEmpty)
        XCTAssertEqual(plan.add, [main, tabs])
        XCTAssertTrue(plan.drop.isEmpty)
        XCTAssertFalse(plan.isUnchanged)
    }

    func testStoredTabsForKnownCheckoutsAreKeptNotDuplicated() {
        let stored = [
            TabRecord(edge: .left, title: "main", root: leaf),
            TabRecord(edge: .left, title: "tabs", root: leaf, workingDirectory: worktree)
        ]
        let plan = ProjectTabReconciler.plan(
            stored: stored, checkouts: [main, tabs], projectDirectory: project, existsOnDisk: { _ in true }
        )
        XCTAssertEqual(plan.keep.map(\.id), stored.map(\.id))
        XCTAssertTrue(plan.add.isEmpty)
        XCTAssertTrue(plan.isUnchanged)
    }

    func testATabWhoseDirectoryVanishedIsDropped() {
        let gone = URL(fileURLWithPath: "/repo/.claude/worktrees/gone")
        let stored = [TabRecord(edge: .left, title: "gone", root: leaf, workingDirectory: gone)]
        let plan = ProjectTabReconciler.plan(
            stored: stored, checkouts: [main], projectDirectory: project, existsOnDisk: { $0 != gone }
        )
        XCTAssertEqual(plan.drop, stored.map(\.id))
        XCTAssertEqual(plan.add, [main])
    }

    func testAUserTabInAnotherExistingFolderSurvives() {
        let elsewhere = URL(fileURLWithPath: "/somewhere/else")
        let stored = [TabRecord(edge: .left, title: "notes", root: leaf, workingDirectory: elsewhere)]
        let plan = ProjectTabReconciler.plan(
            stored: stored, checkouts: [main], projectDirectory: project, existsOnDisk: { _ in true }
        )
        XCTAssertEqual(plan.keep.map(\.id), stored.map(\.id))
        XCTAssertTrue(plan.drop.isEmpty)
    }

    func testMakeRecordsProducesOneMemberPerEdgeSharingAGroup() {
        let records = ProjectTabReconciler.makeRecords(
            for: tabs, enabledEdges: [.left, .top], blueprint: makeBlueprint
        )
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(Set(records.map(\.groupID)).count, 1)
        XCTAssertEqual(records.map(\.edge), [.left, .top])
        XCTAssertEqual(records.map(\.title), ["tabs", "tabs"])
        XCTAssertEqual(records.compactMap(\.workingDirectory), [worktree, worktree])
    }

    /// Ruling A: `layout_nodes.id` is a `TEXT PRIMARY KEY`, and `saveTabs`
    /// inserts `tab.root` once per member of a group in the same transaction
    /// (`ProjectDatabase+Layout.swift:90,134-137`). Sharing one `LayoutNode`
    /// value across every edge member gives every member's root the same
    /// node id, so the second member's insert violates the primary key and
    /// rolls the whole save back. Each member's root must carry a distinct id.
    func testMakeRecordsGivesEachEdgeMemberADistinctRootNodeID() {
        let records = ProjectTabReconciler.makeRecords(
            for: tabs, enabledEdges: [.left, .top], blueprint: makeBlueprint
        )
        XCTAssertEqual(Set(records.map(\.root.id)).count, 2)
    }

    /// A stored record reached the directory by one route and the checkout by
    /// another — which is what actually happens, since `git worktree list`
    /// resolves symlinks and the window's own directory does not. Matching
    /// only after standardizing would add a second tab group for a checkout
    /// that already has a tab.
    func testARecordReachingACheckoutThroughASymlinkIsStillTheSameTab() throws {
        let manager = FileManager.default
        let target = manager.temporaryDirectory
            .appendingPathComponent("reconciler-symlink-test-\(UUID().uuidString)")
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        let link = target.deletingLastPathComponent()
            .appendingPathComponent(target.lastPathComponent + "-link")
        try manager.createSymbolicLink(at: link, withDestinationURL: target)
        defer {
            try? manager.removeItem(at: link)
            try? manager.removeItem(at: target)
        }

        let checkout = ProjectCheckout(directory: target, branch: "main", isMain: true)
        let stored = [TabRecord(edge: .left, title: "main", root: makeBlueprint(), workingDirectory: link)]
        let plan = ProjectTabReconciler.plan(
            stored: stored, checkouts: [checkout], projectDirectory: project, existsOnDisk: { _ in true }
        )

        XCTAssertEqual(plan.keep.map(\.id), stored.map(\.id))
        XCTAssertTrue(plan.add.isEmpty)
        XCTAssertTrue(plan.drop.isEmpty)
        XCTAssertTrue(plan.isUnchanged)
    }
}
