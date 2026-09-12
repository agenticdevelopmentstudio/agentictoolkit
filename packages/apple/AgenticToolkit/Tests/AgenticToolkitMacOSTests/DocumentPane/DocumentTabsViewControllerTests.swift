import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class DocumentTabsViewControllerTests: XCTestCase {

    private func makeController(paneNodeID: UUID = UUID()) throws -> DocumentTabsViewController {
        let project = ProjectWindowTestSupport.makeProject(label: "DocumentTabsViewControllerTests")
        return DocumentTabsViewController(
            project: project,
            workingDirectory: project.directoryURL,
            documentLayout: try ProjectWindowTestSupport.makeDocumentLayout(),
            documentViewID: ComposableTabsViewID("document.editor"),
            paneNodeID: paneNodeID
        )
    }

    func testItStartsWithOneTabHoldingOneEmptyEditor() throws {
        let controller = try makeController()
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.tabs(on: .top).count, 1)
        XCTAssertNotNil(controller.focusedEditor)
        XCTAssertNil(controller.focusedEditor?.fileURL, "a new tab arrives with an empty editor, never zero panes")
    }

    func testTheTabIsTitledAfterTheFile() throws {
        let controller = try makeController()
        controller.loadViewIfNeeded()

        controller.openInSelectedPane(URL(fileURLWithPath: "/tmp/example/Readme.md"))

        XCTAssertEqual(controller.tabs(on: .top).first?.title, "Readme.md")
    }

    /// The tab names the file the user is working in, and opening to the side
    /// moves that. Filling the new editor before it is the focused one retitles
    /// the tab from the *old* pane, leaving a tab called A.swift over an editor
    /// showing B.swift.
    func testOpeningToTheSideRetitlesTheTabAfterTheNewFile() throws {
        let controller = try makeController()
        controller.loadViewIfNeeded()
        controller.openInSelectedPane(URL(fileURLWithPath: "/tmp/example/A.swift"))

        controller.openToTheSide(URL(fileURLWithPath: "/tmp/example/B.swift"))

        XCTAssertEqual(controller.tabs(on: .top).first?.title, "B.swift")
    }

    func testOpeningInANewTabAddsATabAndFocusesIt() throws {
        let controller = try makeController()
        controller.loadViewIfNeeded()

        controller.openInNewTab(URL(fileURLWithPath: "/tmp/example/Second.swift"))

        XCTAssertEqual(controller.tabs(on: .top).count, 2)
        XCTAssertEqual(controller.focusedEditor?.fileURL?.lastPathComponent, "Second.swift")
    }

    func testOpeningToTheSideAddsAPaneToTheCurrentTab() throws {
        let controller = try makeController()
        controller.loadViewIfNeeded()

        controller.openToTheSide(URL(fileURLWithPath: "/tmp/example/Side.swift"))

        XCTAssertEqual(controller.tabs(on: .top).count, 1, "to the side is a pane, not a tab")
        XCTAssertEqual(controller.editors(inTabAt: 0).count, 2)
    }

    /// Opening to the side hands the user a new editor, so that is the one
    /// they are working in: the next file they pick in the tree belongs in it,
    /// and the tree's highlight has to name the file they just opened rather
    /// than the one still sitting beside it.
    func testOpeningToTheSideMakesTheNewEditorTheFocusedOne() throws {
        let controller = try makeController()
        controller.loadViewIfNeeded()
        controller.openInSelectedPane(URL(fileURLWithPath: "/tmp/example/A.swift"))

        controller.openToTheSide(URL(fileURLWithPath: "/tmp/example/B.swift"))

        XCTAssertEqual(controller.focusedEditor?.fileURL?.lastPathComponent, "B.swift")
    }

    /// Focus decides two things — which file the tree highlights, and which
    /// editor the next click in the tree fills — and AppKit announces neither.
    /// Worse, the click that asks the second question has already moved the
    /// first responder into the tree, so the answer has to be recorded when
    /// focus *arrives* and read back afterwards.
    ///
    /// The editor's real text view belongs to `CodeEditSourceEditor` and is
    /// never built in a headless test, so a text field parked inside the
    /// editor stands in for it. What is under test is which pane the first
    /// responder landed in, not what kind of view it was.
    func testFocusLandingInAnEditorIsRememberedAndReported() throws {
        let controller = try makeController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.loadViewIfNeeded()
        // What showing the window does for itself; a test window is never
        // shown, and the focus observer is installed here.
        controller.viewDidAppear()

        controller.openInSelectedPane(URL(fileURLWithPath: "/tmp/example/A.swift"))
        controller.openToTheSide(URL(fileURLWithPath: "/tmp/example/B.swift"))
        let editors = controller.editors(inTabAt: 0)
        XCTAssertEqual(editors.count, 2)

        var reported: [String?] = []
        controller.onFocusedDocumentChange = { reported.append($0?.lastPathComponent) }

        let caret = NSTextField()
        editors[0].view.addSubview(caret)
        XCTAssertTrue(window.makeFirstResponder(caret))

        XCTAssertEqual(controller.focusedEditor?.fileURL?.lastPathComponent, "A.swift")
        XCTAssertEqual(reported, ["A.swift"])

        // What a click in the file tree does: focus leaves the Document pane
        // altogether. The editor the user was last in has to survive that,
        // because the click is about to ask which editor to fill.
        let elsewhere = NSTextField()
        controller.view.addSubview(elsewhere)
        XCTAssertTrue(window.makeFirstResponder(elsewhere))

        XCTAssertEqual(controller.focusedEditor?.fileURL?.lastPathComponent, "A.swift")
        XCTAssertEqual(reported, ["A.swift"], "focus leaving is not a different document")
    }

    /// Each side-split fills the pane it just created. Reaching for "the last
    /// editor in the tab" instead lands the file on whatever sits rightmost,
    /// which after the focus moves to each new pane is the pane the previous
    /// side-open filled.
    func testASecondSideOpenDoesNotOverwriteTheFirst() throws {
        let controller = try makeController()
        controller.loadViewIfNeeded()

        controller.openToTheSide(URL(fileURLWithPath: "/tmp/example/B.swift"))
        controller.openToTheSide(URL(fileURLWithPath: "/tmp/example/C.swift"))

        let editors = controller.editors(inTabAt: 0)
        XCTAssertEqual(editors.count, 3)
        XCTAssertEqual(
            Set(editors.compactMap { $0.fileURL?.lastPathComponent }),
            ["B.swift", "C.swift"],
            "each side-open keeps its own file"
        )
    }

    func testThreePanesEndUpEqualThirds() throws {
        let controller = try makeController()
        controller.loadViewIfNeeded()
        controller.openToTheSide(URL(fileURLWithPath: "/tmp/example/B.swift"))
        controller.openToTheSide(URL(fileURLWithPath: "/tmp/example/C.swift"))

        let fractions = controller.paneFractions(inTabAt: 0)

        XCTAssertEqual(fractions.count, 3)
        for fraction in fractions {
            XCTAssertEqual(fraction, 1.0 / 3.0, accuracy: 0.01, "the proportional arranger governs this tree")
        }
    }

    /// `openToTheSide` re-walks the whole tab after each split, so an editor
    /// that survives several splits gets handed to the wiring code several
    /// times. The handlers chain rather than replace, so a non-idempotent
    /// wiring pass would make the first editor report every open request once
    /// per split it lived through.
    func testAnEditorReportsAnOpenRequestExactlyOncePerRequest() throws {
        let controller = try makeController()
        controller.loadViewIfNeeded()
        let firstEditor = try XCTUnwrap(controller.focusedEditor)
        controller.openToTheSide(URL(fileURLWithPath: "/tmp/example/B.swift"))
        controller.openToTheSide(URL(fileURLWithPath: "/tmp/example/C.swift"))

        var reported: [URL] = []
        controller.onOpenRequest = { reported.append($0) }
        firstEditor.onOpenRequest?(URL(fileURLWithPath: "/tmp/example/Target.swift"))

        XCTAssertEqual(reported.count, 1, "two side-splits must not triple one editor's handler")
    }

    func testTheLastTabCannotBeClosed() throws {
        let controller = try makeController()
        controller.loadViewIfNeeded()
        let onlyTab = try XCTUnwrap(controller.tabs(on: .top).first)

        controller.multiTabbedViewController(controller, didRequestCloseTab: onlyTab.id, on: .top)

        XCTAssertEqual(controller.tabs(on: .top).count, 1, "the floor is one tab")
    }

    func testClosingTheLastPaneOfTheLastTabEmptiesItInstead() throws {
        let controller = try makeController()
        controller.loadViewIfNeeded()
        controller.openInSelectedPane(URL(fileURLWithPath: "/tmp/example/Readme.md"))
        let onlyTab = try XCTUnwrap(controller.tabs(on: .top).first)

        controller.multiTabbedViewController(controller, didRequestCloseTab: onlyTab.id, on: .top)

        XCTAssertEqual(controller.tabs(on: .top).count, 1)
        XCTAssertEqual(controller.editors(inTabAt: 0).count, 1)
        XCTAssertNil(controller.focusedEditor?.fileURL, "the document goes, the pane and tab stay")
        XCTAssertEqual(controller.tabs(on: .top).first?.title, "Untitled")
    }

    func testASecondTabCanBeClosed() throws {
        let controller = try makeController()
        controller.loadViewIfNeeded()
        controller.openInNewTab(URL(fileURLWithPath: "/tmp/example/Second.swift"))
        let second = try XCTUnwrap(controller.tabs(on: .top).last)

        controller.multiTabbedViewController(controller, didRequestCloseTab: second.id, on: .top)

        XCTAssertEqual(controller.tabs(on: .top).count, 1)
    }

    func testTabsAndDocumentsSurviveASaveRestoreCycle() throws {
        let project = ProjectWindowTestSupport.makeProject(label: "DocumentTabsViewControllerTests")
        let layout = try ProjectWindowTestSupport.makeDocumentLayout()
        let sharedPaneNodeID = UUID()

        // `DocumentEditorViewController.restoreStoredDocument()` only restores
        // a path that still exists on disk — a fictional `/tmp/example/...`
        // path would silently come back empty, so this round trip needs real
        // files, not just remembered ones.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentTabsViewControllerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileA = directory.appendingPathComponent("A.swift")
        let fileB = directory.appendingPathComponent("B.swift")
        let fileC = directory.appendingPathComponent("C.swift")
        for file in [fileA, fileB, fileC] {
            try Data().write(to: file)
        }

        let first = DocumentTabsViewController(
            project: project,
            workingDirectory: project.directoryURL,
            documentLayout: layout,
            documentViewID: ComposableTabsViewID("document.editor"),
            paneNodeID: sharedPaneNodeID
        )
        first.loadViewIfNeeded()
        first.openInSelectedPane(fileA)
        first.openToTheSide(fileB)
        first.openInNewTab(fileC)
        first.persistTabs()

        let restored = DocumentTabsViewController(
            project: project,
            workingDirectory: project.directoryURL,
            documentLayout: layout,
            documentViewID: ComposableTabsViewID("document.editor"),
            paneNodeID: sharedPaneNodeID
        )
        restored.loadViewIfNeeded()

        XCTAssertEqual(restored.tabs(on: .top).count, 2)
        XCTAssertEqual(restored.editors(inTabAt: 0).compactMap { $0.fileURL?.lastPathComponent },
                       ["A.swift", "B.swift"])
        XCTAssertEqual(restored.editors(inTabAt: 1).compactMap { $0.fileURL?.lastPathComponent },
                       ["C.swift"])
    }

    /// A tab's title and the file in its editor are one fact, and the two are
    /// written down at different moments: the editor records its file the
    /// instant it changes, while the tab list is only rewritten when the
    /// arrangement is. Believing a stored title on restore is therefore
    /// believing the older of two copies — which is what puts a tab named
    /// after yesterday's file above an editor showing today's.
    func testARestoredTabIsTitledAfterTheFileItsEditorActuallyHolds() throws {
        let project = ProjectWindowTestSupport.makeProject(label: "DocumentTabsViewControllerTests")
        let layout = try ProjectWindowTestSupport.makeDocumentLayout()
        let paneNodeID = UUID()

        // Real files, for the reason `testTabsAndDocumentsSurviveASaveRestoreCycle`
        // gives: a remembered path whose file is gone restores as empty.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentTabsViewControllerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileA = directory.appendingPathComponent("A.swift")
        let fileB = directory.appendingPathComponent("B.swift")
        for file in [fileA, fileB] { try Data().write(to: file) }

        func makeController() -> DocumentTabsViewController {
            DocumentTabsViewController(
                project: project,
                workingDirectory: project.directoryURL,
                documentLayout: layout,
                documentViewID: ComposableTabsViewID("document.editor"),
                paneNodeID: paneNodeID
            )
        }

        let first = makeController()
        first.loadViewIfNeeded()
        first.openInSelectedPane(fileA)
        first.persistTabs()
        // Picking a file in the tree changes the editor, not the arrangement,
        // so nothing rewrites the tab list — exactly the divergence above.
        first.openInSelectedPane(fileB)

        let restored = makeController()
        restored.loadViewIfNeeded()

        XCTAssertEqual(restored.editors(inTabAt: 0).first?.fileURL?.lastPathComponent, "B.swift")
        XCTAssertEqual(restored.tabs(on: .top).first?.title, "B.swift")
    }

    /// The window sweeps `pane_state` on every save: a row whose node is no
    /// longer a layout node belongs to a pane that is gone. The Document pane's
    /// editors live in a tree of its own, so *none* of their nodes are layout
    /// nodes — remembering a file against the editor's own node id means the
    /// next sweep silently empties every editor, which is what a relaunch shows.
    func testTheRememberedFilesSurviveTheWindowsPaneStateSweep() throws {
        let project = ProjectWindowTestSupport.makeProject(label: "DocumentTabsViewControllerTests")
        let layout = try ProjectWindowTestSupport.makeDocumentLayout()
        let paneNodeID = UUID()

        // Real files, for the reason `testTabsAndDocumentsSurviveASaveRestoreCycle`
        // gives: a remembered path whose file is gone restores as empty.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentTabsViewControllerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileA = directory.appendingPathComponent("A.swift")
        let fileB = directory.appendingPathComponent("B.swift")
        for file in [fileA, fileB] { try Data().write(to: file) }

        func makeController() -> DocumentTabsViewController {
            DocumentTabsViewController(
                project: project,
                workingDirectory: project.directoryURL,
                documentLayout: layout,
                documentViewID: ComposableTabsViewID("document.editor"),
                paneNodeID: paneNodeID
            )
        }

        let first = makeController()
        first.loadViewIfNeeded()
        first.openInSelectedPane(fileA)
        first.openToTheSide(fileB)

        // What the window does whenever anything about its arrangement changes.
        // The Document pane is a layout node; the editors inside it never are.
        project.persistTabs(
            [TabRecord(title: "Tab", root: .leaf(id: paneNodeID, contentType: ComposableTabsViewID("document")))],
            activeTabID: nil,
            enabledEdges: [.top]
        )

        let restored = makeController()
        restored.loadViewIfNeeded()

        XCTAssertEqual(
            restored.editors(inTabAt: 0).compactMap { $0.fileURL?.lastPathComponent },
            ["A.swift", "B.swift"]
        )
    }

    func testTheStoredLayoutMirrorRoundTrips() throws {
        let tree = LayoutNode.split(
            orientation: .horizontal,
            first: .leaf(contentType: ComposableTabsViewID("document.editor"), thicknessFraction: 0.25),
            second: .leaf(contentType: ComposableTabsViewID("document.editor"), thicknessFraction: 0.75)
        )

        let data = try JSONEncoder().encode(LayoutNodeCodable(tree))
        let back = try JSONDecoder().decode(LayoutNodeCodable.self, from: data).node

        guard case .split(_, let first, let second) = back.kind else { return XCTFail("expected a split") }
        XCTAssertEqual(first.thicknessFraction, 0.25)
        XCTAssertEqual(second.thicknessFraction, 0.75)
        XCTAssertEqual(back.id, tree.id)
    }
}
