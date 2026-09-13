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
/// The declared minimum is only half of it. AppKit's minimum divider position
/// is the greater of that and the hosted view's `fittingSize.width`, and
/// `fittingSize` honours each item's own width-holding constraint at its
/// `holdingPriority`. Those are optional, so they never conflict and nothing is
/// logged — the enclosing pane just acquires a floor its content never asked
/// for, and a drag of its right divider that cannot shrink it slides the whole
/// nested split instead: the pane moves and a pane two away resizes.
///
/// `clampsToContainer` is the one switch that says which of the two a tree is,
/// and these pin every part of it: the default still imposes its minimums and
/// holds its own width, a clamped tree does neither, at both of the two places
/// that set them.
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

    /// Every pane in a subtree, at any depth.
    private func panes(under controller: NSViewController) -> [PaneViewController] {
        let here = (controller as? PaneViewController).map { [$0] } ?? []
        return here + controller.children.flatMap { panes(under: $0) }
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

    /// The other half of the same fact, and the one that moved the Document
    /// pane: an unclamped pane holds the width it was given, so a window resize
    /// comes out of its neighbours rather than being spread around.
    func testAnUnclampedSplitLetsItsPanesHoldTheirOwnWidth() throws {
        let root = try makeTree(twoEditors, clamped: false)

        XCTAssertEqual(root.splitViewItems.count, 2)
        XCTAssertTrue(
            root.splitViewItems.allSatisfy {
                $0.holdingPriority > ComposableTabsViewController.clampedHoldingPriority
            },
            "a window's own tree keeps the width it is given")
    }

    func testAClampedSplitsItemsHoldNoWidthOfTheirOwn() throws {
        let root = try makeTree(twoEditors, clamped: true)

        XCTAssertEqual(root.splitViewItems.count, 2)
        for item in root.splitViewItems {
            XCTAssertEqual(
                item.holdingPriority,
                ComposableTabsViewController.clampedHoldingPriority,
                "a clamped item's width is the container's to decide, so it asks for none")
        }
    }

    /// What the two declarations add up to, measured rather than asserted: the
    /// split asks for what is inside it and not a point more. With the items
    /// holding their own width this was fixed at a number their contents never
    /// needed — and unchanged as the pane grew, which is what made it a floor.
    func testAClampedSplitAsksForNoMoreWidthThanItsContentsNeed() throws {
        let root = try makeTree(twoEditors, clamped: true)
        root.view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        root.view.layoutSubtreeIfNeeded()

        let panes = root.splitView.arrangedSubviews
        let contents = panes.reduce(CGFloat.zero) { $0 + $1.fittingSize.width }
        let dividers = root.splitView.dividerThickness * CGFloat(max(0, panes.count - 1))

        XCTAssertEqual(panes.count, 2)
        XCTAssertLessThanOrEqual(
            root.splitView.fittingSize.width, contents + dividers + 1,
            "anything above this is a floor the enclosing pane never asked for")
    }

    /// `makeItem(for:)` is not the only place a minimum is set — `restoreSizing`
    /// re-derives one when a pane comes back from being collapsed or maximised.
    /// Both call sites route through the same wrapper, and this is what says so.
    func testRestoringAnItemsSizingKeepsItClamped() throws {
        let root = try makeTree(twoEditors, clamped: true)
        let item = try XCTUnwrap(root.splitViewItems.first)
        item.minimumThickness = 320
        item.holdingPriority = .defaultHigh

        root.restoreSizing(of: item)

        XCTAssertEqual(item.minimumThickness, NSSplitViewItem.unspecifiedDimension)
        XCTAssertEqual(
            item.holdingPriority, ComposableTabsViewController.clampedHoldingPriority)
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
                XCTAssertEqual(
                    item.holdingPriority,
                    ComposableTabsViewController.clampedHoldingPriority)
            }
        }
    }

    /// The split's items are not the only thing in a clamped tree that can
    /// demand width: each pane's chrome does too, through a required chain of
    /// its own, and one floor per pane is what made a fourth editor widen the
    /// Document pane. So a pane is stamped exactly as a nested split is.
    func testAClampedSplitTellsItsPanesTheirWidthIsNotTheirs() throws {
        let root = try makeTree(twoEditors, clamped: true)
        let panes = panes(under: root)

        XCTAssertEqual(panes.count, 2)
        for pane in panes {
            XCTAssertTrue(
                pane.clampsToContainer,
                "a pane's chrome is the other half of what the enclosing pane pays for")
        }
    }

    func testAnUnclampedSplitsPanesKeepTheirOwnWidth() throws {
        let root = try makeTree(twoEditors, clamped: false)
        let panes = panes(under: root)

        XCTAssertEqual(panes.count, 2)
        XCTAssertTrue(panes.allSatisfy { !$0.clampsToContainer })
    }

    /// A pane under a nested split inherits it the same way, one level down.
    func testANestedSplitsPanesAreToldToo() throws {
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
            XCTAssertFalse(panes(under: split).isEmpty)
            XCTAssertTrue(panes(under: split).allSatisfy { $0.clampsToContainer })
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
            XCTAssertTrue(
                panes(under: split).allSatisfy { $0.clampsToContainer },
                "and so does its chrome's")
            for item in split.splitViewItems {
                XCTAssertEqual(item.minimumThickness, NSSplitViewItem.unspecifiedDimension)
                XCTAssertEqual(
                    item.holdingPriority,
                    ComposableTabsViewController.clampedHoldingPriority)
            }
        }
    }
}
