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
