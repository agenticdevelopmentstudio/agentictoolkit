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

    /// Adopts `MultiTabbedViewControllerDelegate` with no overrides, so the
    /// default extension's `didRequestCloseTab` — which calls
    /// `controller.removeTab(id:)` — is what actually runs.
    private final class NoOpDelegate: MultiTabbedViewControllerDelegate {}

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

        // The assertions above are also satisfiable by `setSelected(_:)`
        // alone, since both go through it. Force a full `rebuildButtons()`
        // for an edge whose selection is already settled — `moveTab` reaches
        // `syncTabBar` without ever calling `setSelected` — after corrupting
        // the already-correct state directly, so only `rebuildButtons`'s own
        // `hosted.isHighlighted = (item.id == selectedID)` can restore it.
        second.isHighlighted = false
        controller.moveTab(id: firstID, to: 1, on: .left)
        XCTAssertTrue(second.isHighlighted)
    }

    func testTheBarGrowsToTheHostedItemsPreferredSize() throws {
        let controller = makeController()
        controller.addTab(.init(item: .viewController(HostedItem()), viewController: makeContent()), on: .left)
        controller.view.layoutSubtreeIfNeeded()
        let bar = try XCTUnwrap(controller.tabBars[.left])
        // Exact rather than a floor: pins both the `+ 16` padding and the
        // floor at the button default (140), neither of which a `>=` against
        // 200 would catch a regression in.
        XCTAssertEqual(bar.thicknessConstraint?.constant, 216)
    }

    func testTheBarGrowsToTheHostedItemsPreferredSizeOnATopBar() throws {
        let controller = makeController()
        controller.addTab(.init(item: .viewController(HostedItem()), viewController: makeContent()), on: .top)
        controller.view.layoutSubtreeIfNeeded()
        let bar = try XCTUnwrap(controller.tabBars[.top])
        // The left/right thickness test exercises only `.width` + 16; this
        // pins the separate `.top`/`.bottom` branch, `.height` + 4.
        XCTAssertEqual(bar.thicknessConstraint?.constant, 68)
    }

    func testRemovingATabRemovesItsHostedItemFromTheParent() {
        let controller = makeController()
        let item = HostedItem()
        let id = UUID()
        controller.addTab(.init(id: id, item: .viewController(item), viewController: makeContent()), on: .left)
        controller.removeTab(id: id)
        XCTAssertNil(item.parent)
        XCTAssertNil(item.view.superview)
    }

    func testRenameIsIgnoredForViewControllerItems() {
        let controller = makeController()
        let id = UUID()
        let item = HostedItem()
        // A hard-coded `""` would satisfy an assertion against `""`; give
        // the item a real title so only "rename was actually ignored" (not
        // "the title was always empty") makes this pass.
        item.title = "Live"
        controller.addTab(.init(id: id, item: .viewController(item), viewController: makeContent()), on: .top)
        controller.renameTab(id: id, title: "Renamed")
        XCTAssertEqual(controller.tabs(on: .top).first?.title, "Live")
    }

    func testTitleItemsStillRename() {
        let controller = makeController()
        let id = UUID()
        controller.addTab(.init(id: id, title: "Tab 1", viewController: makeContent()), on: .top)
        controller.renameTab(id: id, title: "Renamed")
        XCTAssertEqual(controller.tabs(on: .top).first?.title, "Renamed")
    }

    // MARK: - Previously untested behaviour

    func testChangingPreferredContentSizeGrowsTheBar() throws {
        let controller = makeController()
        let item = HostedItem()
        controller.addTab(.init(item: .viewController(item), viewController: makeContent()), on: .left)
        controller.view.layoutSubtreeIfNeeded()

        item.preferredContentSize = NSSize(width: 400, height: 64)
        controller.preferredContentSizeDidChange(for: item)

        let bar = try XCTUnwrap(controller.tabBars[.left])
        XCTAssertEqual(bar.thicknessConstraint?.constant, 416)
    }

    func testHostedItemsOnCloseRemovesTheTab() {
        let controller = makeController()
        let delegate = NoOpDelegate()
        controller.delegate = delegate
        let item = HostedItem()
        let id = UUID()
        controller.addTab(.init(id: id, item: .viewController(item), viewController: makeContent()), on: .left)

        item.onClose?()

        XCTAssertFalse(controller.tabs(on: .left).contains { $0.id == id })
    }

    func testClickingAHostedItemSelectsItsTab() throws {
        let controller = makeController()
        // `.left` starts disabled, and `addTab`'s auto-select-the-first-tab
        // branch is gated on `isEdgeEnabled` — without this, `firstID` is
        // never activated and the assertion below fails before the click
        // under test even happens.
        controller.setEdgeEnabled(.left, true)
        let first = HostedItem()
        let second = HostedItem()
        let firstID = UUID()
        let secondID = UUID()
        controller.addTab(.init(id: firstID, item: .viewController(first), viewController: makeContent()), on: .left)
        controller.addTab(.init(id: secondID, item: .viewController(second), viewController: makeContent()), on: .left)
        XCTAssertEqual(controller.selectedTabID(on: .left), firstID)

        let hostView = try XCTUnwrap(second.view.superview)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        hostView.mouseDown(with: event)

        XCTAssertEqual(controller.selectedTabID(on: .left), secondID)
    }

    func testChangingAHostedItemsPayloadTearsDownTheOldController() throws {
        let host = NSViewController()
        host.view = NSView()
        let bar = TabBarView(edge: .left)
        bar.hostController = host
        let id = UUID()

        let first = HostedItem()
        bar.setItems([.init(id: id, item: .viewController(first))], selectedID: nil)
        XCTAssertTrue(first.parent === host)
        XCTAssertNotNil(first.view.superview)

        let second = HostedItem()
        bar.setItems([.init(id: id, item: .viewController(second))], selectedID: nil)

        XCTAssertNil(first.parent)
        XCTAssertNil(first.view.superview)
        XCTAssertTrue(second.parent === host)
    }
}
