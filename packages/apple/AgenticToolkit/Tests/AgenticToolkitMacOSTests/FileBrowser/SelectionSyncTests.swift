import Combine
import XCTest
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// `reveal(_:)` is the tree following the editor, not the editor following the
/// tree — `FileTreeOpenOnSelectionTests` already covers that direction. This
/// pins the return trip: an editor gaining focus moves the highlight without
/// echoing a selection change back out, through the same `isSyncingSelection`
/// guard that already protects a model-driven restore.
@MainActor
final class SelectionSyncTests: XCTestCase {

    /// Builds a one-root browser over a real `root/sub/nested.swift` on disk,
    /// with every level already read, so nothing an outline expansion triggers
    /// needs the manager's usual async disk read. That keeps the `reveal(_:)`
    /// exercises deterministic: the rows it looks for are already there.
    ///
    /// Every node below the root is read off disk by `loadChildren(for:)`, the
    /// same call the browser itself uses, and the file the test reveals is the
    /// URL that read handed back. That matters more than it looks: a directory
    /// read returns paths with their symlinks resolved, so a node spelled by
    /// hand as `/var/folders/…` and its own child spelled `/private/var/…`
    /// would never match in a lookup by path. In the app every URL a reveal
    /// can arrive with came from one of these reads, so the fixture uses them
    /// too rather than spelling paths of its own.
    private func makeControllerWithNestedFile() throws -> (FileTreeOutlineViewController, URL) {
        let created = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelectionSyncTests-\(UUID().uuidString)")
        let subdirectory = created.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        try "// nested".write(to: subdirectory.appendingPathComponent("nested.swift"),
                             atomically: true,
                             encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: created) }
        // The root is named the way the file system names it, so the root row
        // and the rows read out of it share one spelling. `/var` is a symlink
        // to `/private/var`, and a project whose own path holds a symlink is
        // the one case the tree cannot follow a reveal through.
        let directory = URL(fileURLWithPath: try XCTUnwrap(
            created.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath
        ))

        let rootNode = FileTreeNode(url: directory, isDirectory: true, loadChildren: true)
        let subNode = try XCTUnwrap(rootNode.children?.first, "the root should list its one subdirectory")
        // `loadChildren: true` reads one level; the children it returns come
        // back unread, and the outline is never asked to draw a row whose
        // contents are still loading.
        subNode.children = FileTreeNode.loadChildren(for: subNode.url)
        let fileURL = try XCTUnwrap(subNode.children?.first, "the subdirectory should list its one file").url

        let manager = FileTreeManager(
            repoRootURL: directory,
            packageURL: directory.appendingPathComponent(".build"),
            config: .default
        )

        let roots = FileBrowserRootsModel()
        roots.managers = [manager]

        let controller = FileTreeOutlineViewController(
            roots: roots,
            directories: FileBrowserDirectories(primary: directory),
            selection: FileBrowserSelection(),
            restoration: FileBrowserRestorationState(),
            documentStore: TextDocumentStore()
        )
        controller.loadViewIfNeeded()
        // `roots.$managers` is delivered `.receive(on: RunLoop.main)`, so the
        // controller's own subscriptions — including the one that turns a
        // `manager.$rootNode` change into a reload — need a turn of the run
        // loop before they exist.
        //
        // `FileTreeManager.init` also forwards its (never-started)
        // coordinator's `$rootNode`, which begins at `nil`, through that same
        // kind of deferred pipe. Setting the manager's real tree *before* that
        // one-time `nil` lands would only have it clobbered a moment later —
        // so the pump runs first, against an empty manager, and the real tree
        // goes in only once that has settled.
        pumpRunLoop()
        manager.rootNode = rootNode
        pumpRunLoop()

        return (controller, fileURL)
    }

    private func pumpRunLoop() {
        for _ in 0..<10 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    func testRevealingAFileSelectsItWithoutReemittingASelectionChange() throws {
        let (controller, fileURL) = try makeControllerWithNestedFile()
        var selectionChanges = 0
        let observer = controller.selectionPublisherForTesting.sink { _ in selectionChanges += 1 }
        defer { observer.cancel() }

        controller.reveal(fileURL)

        XCTAssertEqual(controller.selectedURLForTesting, fileURL)
        XCTAssertEqual(selectionChanges, 0, "a reveal came from an editor; it must not be echoed back")
    }

    func testRevealingExpandsCollapsedAncestors() throws {
        let (controller, fileURL) = try makeControllerWithNestedFile()
        controller.collapseAllForTesting()

        controller.reveal(fileURL)

        XCTAssertEqual(controller.selectedURLForTesting, fileURL,
                       "a file buried in collapsed folders still has to be reachable")
    }

    func testRevealingTheAlreadySelectedFileIsANoOp() throws {
        let (controller, fileURL) = try makeControllerWithNestedFile()
        controller.reveal(fileURL)

        controller.reveal(fileURL)

        XCTAssertEqual(controller.selectedURLForTesting, fileURL)
    }

    func testRevealingNilClearsTheHighlight() throws {
        let (controller, fileURL) = try makeControllerWithNestedFile()
        controller.reveal(fileURL)

        controller.revealNothing()

        XCTAssertNil(controller.selectedURLForTesting, "an empty editor highlights nothing")
    }
}
