import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// A split item's `minimumThickness` is a **required** constraint, and a
/// required constraint does not stop at a view-controller boundary. A window's
/// own tree wants that — the window can grow, so a pane that needs 400pt gets
/// them. A tree nested inside one pane of a bigger tree cannot: growing there
/// means taking width from the pane's neighbours, so the same constraint
/// instead pushes the *enclosing* pane wider, and clicking between two tabs
/// holding different numbers of editors resizes the Document pane.
///
/// `clampsToContainer` is the one switch that says which of the two a tree is,
/// and these pin both halves of it: the default still imposes its minimums,
/// and a clamped tree imposes none at either of the two places that set them.
@MainActor
final class PaneContainerClampTests: XCTestCase {

    private let editor = ComposableTabsViewID("document.editor")

    private func makeProject() -> ProjectWorkspace {
        ProjectWindowTestSupport.makeProject(label: "PaneContainerClampTests")
    }

    /// A tab's tree as `DocumentTabsViewController` builds one: the editor-only
    /// layout as an override, and the flag set before the view loads, because
    /// `viewDidLoad` is where the split items — and their minimums — are made.
    private func makeTree(
        _ node: LayoutNode,
        clamped: Bool
    ) throws -> ComposableTabsViewController {
        let project = makeProject()
        let root = ComposableTabsViewController.make(
            from: node,
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )
        root.layoutOverride = try ProjectWindowTestSupport.makeDocumentLayout(viewID: editor)
        root.clampsToContainer = clamped
        root.loadViewIfNeeded()
        return root
    }

    private var twoEditors: LayoutNode {
        .split(
            orientation: .horizontal,
            first: .leaf(contentType: editor),
            second: .leaf(contentType: editor)
        )
    }

    /// Every `ComposableTabsViewController` in a subtree, the root included.
    private func splits(under controller: NSViewController) -> [ComposableTabsViewController] {
        let here = (controller as? ComposableTabsViewController).map { [$0] } ?? []
        return here + controller.children.flatMap { splits(under: $0) }
    }

    // MARK: - The default

    /// A window's tree is the unclamped case, and nothing about it changes: the
    /// panes still say how narrow they may be made.
    func testAnUnclampedSplitImposesTheRegisteredMinimums() throws {
        let root = try makeTree(twoEditors, clamped: false)

        XCTAssertEqual(root.splitViewItems.count, 2)
        XCTAssertTrue(
            root.splitViewItems.allSatisfy { $0.minimumThickness > 0 },
            "a window's own tree asks the window for the width its panes need")
    }

    func testClampingIsOffUnlessAHostAsksForIt() throws {
        let root = try makeTree(twoEditors, clamped: false)

        XCTAssertFalse(root.clampsToContainer)
    }

    // MARK: - Clamped to the container

    func testAClampedSplitImposesNoMinimumOnTheContainer() throws {
        let root = try makeTree(twoEditors, clamped: true)

        XCTAssertEqual(root.splitViewItems.count, 2)
        for item in root.splitViewItems {
            XCTAssertEqual(
                item.minimumThickness, NSSplitViewItem.unspecifiedDimension,
                "the panes divide the width the container has, however little that is")
        }
    }

    /// `makeItem(for:)` is not the only place a minimum is set — `restoreSizing`
    /// re-derives one when a pane comes back from being collapsed or maximised.
    /// Both call sites route through the same wrapper, and this is what says so.
    func testRestoringAnItemsSizingKeepsItClamped() throws {
        let root = try makeTree(twoEditors, clamped: true)
        let item = try XCTUnwrap(root.splitViewItems.first)
        item.minimumThickness = 320

        root.restoreSizing(of: item)

        XCTAssertEqual(item.minimumThickness, NSSplitViewItem.unspecifiedDimension)
    }

    /// Clamping is a fact about a tree, not about a node, so a nested split has
    /// to inherit it — otherwise a tab the user splits twice re-acquires the
    /// constraint the outer split just gave up.
    func testANestedSplitInheritsTheClampAndItsItemsToo() throws {
        let root = try makeTree(
            .split(
                orientation: .horizontal,
                first: .leaf(contentType: editor),
                second: twoEditors
            ),
            clamped: true
        )

        let nested = splits(under: root).filter { $0 !== root }

        XCTAssertFalse(nested.isEmpty, "the fixture builds a nested split")
        for split in nested {
            XCTAssertTrue(split.clampsToContainer)
            for item in split.splitViewItems {
                XCTAssertEqual(item.minimumThickness, NSSplitViewItem.unspecifiedDimension)
            }
        }
    }

    // MARK: - The Document pane

    /// The defect this exists for, at the level the user sees it: two tabs, one
    /// holding one editor and one holding two, and neither of them any wider a
    /// demand on the pane than the other.
    func testEveryDocumentTabRootIsClampedToItsContainer() throws {
        let project = makeProject()
        let controller = DocumentTabsViewController(
            project: project,
            workingDirectory: project.directoryURL,
            documentLayout: try ProjectWindowTestSupport.makeDocumentLayout(viewID: editor),
            documentViewID: editor,
            paneNodeID: UUID()
        )
        controller.loadViewIfNeeded()
        controller.openToTheSide(URL(fileURLWithPath: "/tmp/example/Side.swift"))
        controller.openInNewTab(URL(fileURLWithPath: "/tmp/example/Second.swift"))

        let trees = splits(under: controller)

        XCTAssertFalse(trees.isEmpty, "the tabs are built from split trees")
        for split in trees {
            XCTAssertTrue(
                split.clampsToContainer,
                "the Document pane's width belongs to the window's tree, not to a tab's pane count")
            for item in split.splitViewItems {
                XCTAssertEqual(item.minimumThickness, NSSplitViewItem.unspecifiedDimension)
            }
        }
    }
}
