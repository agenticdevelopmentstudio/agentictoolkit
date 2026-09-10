import AgenticToolkitCore
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class MultiTabbedHostedItemTests: XCTestCase {
    /// A bar item that records highlight changes and can ask to close.
    private final class HostedItem: NSViewController, TabBarHostedItem {
        var isHighlighted = false { didSet { highlightChanges.append(isHighlighted) } }
        var onClose: (() -> Void)?
        var highlightChanges: [Bool] = []
        override func loadView() {
            view = NSView()
            preferredContentSize = NSSize(width: 200, height: 64)
        }
    }

    private func makeController() -> MultiTabbedViewController {
        let controller = MultiTabbedViewController()
        controller.loadViewIfNeeded()
        return controller
    }

    private func makeContent() -> NSViewController {
        let content = NSViewController()
        content.view = NSView()
        return content
    }

    func testAViewControllerItemIsParentedToTheTabbedController() {
        let controller = makeController()
        let item = HostedItem()
        controller.addTab(.init(item: .viewController(item), viewController: makeContent()), on: .left)
        XCTAssertTrue(item.parent === controller)
        XCTAssertNotNil(item.view.superview)
    }

    func testSelectingATabHighlightsItsHostedItem() {
        let controller = makeController()
        let first = HostedItem()
        let second = HostedItem()
        let firstID = UUID()
        let secondID = UUID()
        controller.addTab(.init(id: firstID, item: .viewController(first), viewController: makeContent()), on: .left)
        controller.addTab(.init(id: secondID, item: .viewController(second), viewController: makeContent()), on: .left)
        controller.selectTab(id: secondID, on: .left)
        XCTAssertFalse(first.isHighlighted)
        XCTAssertTrue(second.isHighlighted)
    }

    func testTheBarGrowsToTheHostedItemsPreferredSize() throws {
        let controller = makeController()
        controller.addTab(.init(item: .viewController(HostedItem()), viewController: makeContent()), on: .left)
        controller.view.layoutSubtreeIfNeeded()
        let bar = try XCTUnwrap(controller.tabBars[.left])
        XCTAssertGreaterThanOrEqual(bar.thicknessConstraint?.constant ?? 0, 200)
    }

    func testRemovingATabRemovesItsHostedItemFromTheParent() {
        let controller = makeController()
        let item = HostedItem()
        let id = UUID()
        controller.addTab(.init(id: id, item: .viewController(item), viewController: makeContent()), on: .left)
        controller.removeTab(id: id)
        XCTAssertNil(item.parent)
    }

    func testRenameIsIgnoredForViewControllerItems() {
        let controller = makeController()
        let id = UUID()
        controller.addTab(.init(id: id, item: .viewController(HostedItem()), viewController: makeContent()), on: .top)
        controller.renameTab(id: id, title: "Renamed")
        XCTAssertEqual(controller.tabs(on: .top).first?.title, "")
    }

    func testTitleItemsStillRename() {
        let controller = makeController()
        let id = UUID()
        controller.addTab(.init(id: id, title: "Tab 1", viewController: makeContent()), on: .top)
        controller.renameTab(id: id, title: "Renamed")
        XCTAssertEqual(controller.tabs(on: .top).first?.title, "Renamed")
    }
}
