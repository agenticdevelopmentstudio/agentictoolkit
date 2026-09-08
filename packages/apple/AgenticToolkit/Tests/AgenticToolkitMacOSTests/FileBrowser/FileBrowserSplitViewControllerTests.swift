import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// Clicking a file has to show it. The tree and the viewer are separate
/// controllers joined by one `FileBrowserSelection`, so these pin the join —
/// a second selection object, or a viewer reading its own, is the shape of the
/// bug where selecting a file changes nothing.
@MainActor
final class FileBrowserSplitViewControllerTests: XCTestCase {

    /// A throwaway folder to browse, torn down with the test. Built here rather
    /// than in `setUp`, whose hooks are nonisolated while everything below is
    /// main-actor state.
    private func makeDirectory() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FileBrowserSplitTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    /// The autosave name defaults to a fresh one per split, because AppKit
    /// persists divider positions in `UserDefaults` globally: a fixed name lets
    /// one run's collapsed tree be restored into the next run's assertions.
    private func makeSplit(
        in directory: URL,
        autosaveName: String = "test-file-browser-split-\(UUID().uuidString)"
    ) -> FileBrowserSplitViewController {
        FileBrowserSplitViewController(
            rootURL: directory,
            excludedURL: directory.appendingPathComponent("Cache.pkg"),
            autosaveName: autosaveName
        )
    }

    func testTheTreeAndTheViewerShareOneSelection() {
        let split = makeSplit(in: makeDirectory())
        XCTAssertTrue(split.browserViewController.selection === split.selection)
        XCTAssertTrue(split.viewerViewController.selection === split.selection)
        split.paneContentWillBeDiscarded()
    }

    func testSelectingAFileInTheTreeReachesTheViewer() {
        let directory = makeDirectory()
        let split = makeSplit(in: directory)
        let url = directory.appendingPathComponent("hello.swift")
        try? "let x = 1\n".write(to: url, atomically: true, encoding: .utf8)

        split.browserViewController.selection.selectedNode = FileTreeNode(url: url, isDirectory: false)

        XCTAssertEqual(split.viewerViewController.selection.selectedNode?.url, url)
        split.paneContentWillBeDiscarded()
    }

    func testLoadingInstallsTheTreeBesideTheViewer() {
        let split = makeSplit(in: makeDirectory())
        split.loadViewIfNeeded()

        XCTAssertEqual(split.splitViewItems.count, 2)
        XCTAssertTrue(split.splitViewItems[0].viewController === split.browserViewController)
        XCTAssertTrue(split.splitViewItems[1].viewController === split.viewerViewController)
        XCTAssertTrue(split.splitView.isVertical, "the tree sits beside the file, not above it")
        split.paneContentWillBeDiscarded()
    }

    /// AppKit keys divider positions globally, so two browsers alive at once
    /// under one name overwrite each other's.
    func testTheAutosaveNameIsTheCallersToChoose() {
        let directory = makeDirectory()
        let first = makeSplit(in: directory, autosaveName: "browser-a")
        let second = makeSplit(in: directory, autosaveName: "browser-b")
        first.loadViewIfNeeded()
        second.loadViewIfNeeded()

        XCTAssertEqual(first.splitView.autosaveName, "browser-a")
        XCTAssertNotEqual(first.splitView.autosaveName, second.splitView.autosaveName)

        first.paneContentWillBeDiscarded()
        second.paneContentWillBeDiscarded()
    }

    // MARK: - What the footer is told

    /// The last segment of the window's display path, for a browser with
    /// nothing selected and then with a file selected.
    func testTheSelectionDescriptionIsTheSelectedFilesName() {
        let directory = makeDirectory()
        let split = makeSplit(in: directory)
        XCTAssertNil(split.paneSelectionDescription, "nothing selected ends the path at the pane")

        let url = directory.appendingPathComponent("main.swift")
        try? "let x = 1\n".write(to: url, atomically: true, encoding: .utf8)
        split.selection.selectedNode = FileTreeNode(url: url, isDirectory: false)

        XCTAssertEqual(split.paneSelectionDescription, "main.swift")
        split.paneContentWillBeDiscarded()
    }

    /// The browser reports; the footer does not poll. Asserting what the
    /// callback *shows an observer* rather than that it ran: `@Published`
    /// publishes from `willSet`, so a report made too early hands the footer
    /// the previously selected file and a call-count assertion is green
    /// through the whole bug.
    func testSelectingAFileTellsTheFooterToRecompute() {
        let directory = makeDirectory()
        let split = makeSplit(in: directory)
        let reported = expectation(description: "the footer was told about the selection")
        var described: String?
        split.onPaneSelectionChange = { [weak split] in
            described = split?.paneSelectionDescription
            reported.fulfill()
        }

        let url = directory.appendingPathComponent("main.swift")
        try? "let x = 1\n".write(to: url, atomically: true, encoding: .utf8)
        split.selection.selectedNode = FileTreeNode(url: url, isDirectory: false)

        wait(for: [reported], timeout: 2)
        XCTAssertEqual(
            described, "main.swift",
            "the footer has to be able to read the new selection back when it is told")
        split.paneContentWillBeDiscarded()
    }

    func testCollapsingTheTreeLeavesTheViewerTheWholePane() {
        let split = makeSplit(in: makeDirectory())
        split.loadViewIfNeeded()
        XCTAssertFalse(split.splitViewItems[0].isCollapsed)

        // `toggleTree` animates for the user's benefit; the assertion waits for
        // the animator proxy to commit rather than racing it.
        let collapsed = expectation(description: "tree collapsed")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            split.toggleTree()
        } completionHandler: {
            collapsed.fulfill()
        }
        wait(for: [collapsed], timeout: 2)

        XCTAssertTrue(split.splitViewItems[0].isCollapsed)
        split.paneContentWillBeDiscarded()
    }
}
