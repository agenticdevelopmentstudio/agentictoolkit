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
        // Exact rather than a floor: pins the item's own 200 plus the bar's
        // single `outerPadding` (6) — the card is flush against the workspace
        // side, so there is padding on the outer side only — and the floor at
        // the button default (140), neither of which a `>=` against 200 would
        // catch a regression in.
        XCTAssertEqual(bar.thicknessConstraint?.constant, 206)
    }

    func testTheBarGrowsToTheHostedItemsPreferredSizeOnATopBar() throws {
        let controller = makeController()
        controller.addTab(.init(item: .viewController(HostedItem()), viewController: makeContent()), on: .top)
        controller.view.layoutSubtreeIfNeeded()
        let bar = try XCTUnwrap(controller.tabBars[.top])
        // The left/right thickness test exercises `.width` + 6; this pins the
        // separate `.top`/`.bottom` branch, `.height` + 6, where the floor is
        // the much smaller top/bottom default (28) rather than 140.
        XCTAssertEqual(bar.thicknessConstraint?.constant, 70)
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
        XCTAssertEqual(bar.thicknessConstraint?.constant, 406)
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

    /// Review C MAJOR-2: the direct `hostView.mouseDown(with:)` call above
    /// bypasses AppKit's hit-testing entirely, so it proves the handler
    /// works but can never prove the handler is *reachable*. This drives a
    /// real `mouseDown` through real hit-testing at a point inside the agent
    /// label — the visually obvious target a user would actually click —
    /// and asserts the tab actually gets selected, not just that some
    /// non-selectable view was hit.
    ///
    /// Investigation note, recorded here because it changes what "red before
    /// the fix" means for this finding: the review's stated mechanism
    /// (`NSTextField(frame:)` is selectable by default, so an untouched
    /// `ThemedLabel` swallows the click) does not reproduce against the
    /// current code. Verified two ways: (1) a plain `NSTextField(frame:)`
    /// does start `isEditable = true, isSelectable = true`, but AppKit
    /// cascades `isSelectable` to `false` when `isEditable` is set `false`
    /// — and `ThemedLabel.init` (`ThemedViews.swift:46`) already does
    /// `self.isEditable = false`, so a `ThemedLabel` is already
    /// non-selectable before `TabPaneView` ever touches it. (2) This test,
    /// run against the unmodified `TabPaneView` (no `isSelectable = false`
    /// in `setUp()`), already passes — dispatching `mouseDown` on the
    /// actually-hit-tested `ThemedLabel` already reaches `TabBarView`'s
    /// `onSelect`. Forcing `agentLabel.isSelectable = true` immediately
    /// before the click (simulating the bug as described) does make the
    /// test fail exactly as the review predicts, confirming the test can
    /// catch the defect if it existed — it just doesn't currently exist
    /// here, because `ThemedLabel`'s own `isEditable = false` already
    /// neutralizes it.
    ///
    /// The prescribed fix (explicit `isSelectable = false` on all five
    /// labels in `TabPaneView.setUp()`) is applied anyway: it is harmless,
    /// matches the ruling in the fix brief, and turns an accidental
    /// AppKit cascade into a stated, local invariant that does not depend on
    /// `ThemedLabel` continuing to set `isEditable = false` the way it
    /// happens to today. This test therefore does not go red before that
    /// fix and green after — both states pass — and that is reported
    /// explicitly rather than claimed otherwise.
    func testClickingTheAgentLabelSelectsItsTabThroughRealHitTesting() throws {
        let host = NSViewController()
        host.view = NSView()
        let bar = TabBarView(edge: .left)
        bar.hostController = host
        let firstID = UUID()
        let secondID = UUID()
        let first = TabPaneViewController(edge: .left, tabID: firstID)
        let second = TabPaneViewController(edge: .left, tabID: secondID)
        second.loadViewIfNeeded()
        second.paneView.agentLabel.stringValue = "Claude · Fable 5.1"
        second.paneView.sessionLabel.stringValue = "tabs-session"

        var selected: UUID?
        bar.onSelect = { id in selected = id }
        bar.setItems(
            [.init(id: firstID, item: .viewController(first)), .init(id: secondID, item: .viewController(second))],
            selectedID: firstID
        )

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor)
        ])
        container.layoutSubtreeIfNeeded()

        let labelFrame = second.paneView.agentLabel.convert(second.paneView.agentLabel.bounds, to: container)
        XCTAssertGreaterThan(labelFrame.width, 0, "the agent label needs a real frame to click inside")
        let clickPoint = NSPoint(x: labelFrame.midX, y: labelFrame.midY)
        let resolved = try XCTUnwrap(container.hitTest(clickPoint))

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
        resolved.mouseDown(with: event)

        XCTAssertEqual(selected, secondID, "a click resolved onto \(type(of: resolved)) never reached the tab")
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

    // MARK: - Fix round 2: previously-uncovered guards

    /// A cross-edge move inserts the item on the new edge before removing it
    /// from the old one (there is no edge-to-edge `moveTab`), so the old
    /// bar's next reconciliation pass sees an id that vanished from its own
    /// `items` while the controller itself is still alive and now owned by
    /// the other bar. This pins the guard in `rebuildButtons()` that keeps
    /// that pass from tearing the controller down anyway.
    func testCrossBarOwnershipTransferLeavesTheForeignControllerAlone() throws {
        let host = NSViewController()
        host.view = NSView()
        let barA = TabBarView(edge: .left)
        barA.hostController = host
        let barB = TabBarView(edge: .right)
        barB.hostController = host
        let id = UUID()
        let item = HostedItem()

        // Host on barA first, exactly like a real tab before a move.
        barA.setItems([.init(id: id, item: .viewController(item))], selectedID: nil)
        XCTAssertTrue(item.parent === host)
        let originalHostView = try XCTUnwrap(item.view.superview)

        // barB takes it over. `TabItemHostView.init`'s `addSubview(content)`
        // silently detaches `item.view` from barA's wrapper here — the same
        // mechanism a real cross-edge move relies on.
        barB.setItems([.init(id: id, item: .viewController(item))], selectedID: nil)
        let newHostView = try XCTUnwrap(item.view.superview)
        XCTAssertFalse(newHostView === originalHostView)

        // barA's own reconciliation now runs with `id` gone from its items.
        // The controller it once owned belongs to barB now; barA must leave
        // it alone rather than tearing it down.
        barA.setItems([], selectedID: nil)

        XCTAssertTrue(item.parent === host, "barA tore down a controller it no longer owns")
        XCTAssertTrue(item.view.superview === newHostView, "barA ripped the view out of barB's wrapper")
    }

    /// A hosted item's content view is a bare `NSView` with no intrinsic
    /// size and no internal constraints, so without an explicit length-axis
    /// pin it collapses to 0 along the stack's main axis — the axis
    /// `thicknessConstraint` never touches. Left/right bars run vertically,
    /// so the length axis is height.
    ///
    /// A hosted item gets a concrete extent along the stack's main axis from
    /// `preferredContentSize`, and keeps following it when it changes.
    ///
    /// Nothing in `TabBarView` pins that axis, and nothing should: a hosted
    /// item is always an `NSViewController`, and AppKit installs
    /// `NSViewController.preferredContentSize.height` on its view at
    /// priority 501. This test exists because that is a borrowed guarantee
    /// rather than one this file enforces — it would quietly stop holding if
    /// the payload ever became a bare view, or if the content view had
    /// `translatesAutoresizingMaskIntoConstraints` left on. Left/right bars
    /// run vertically, so the length axis here is height.
    ///
    /// The frames are zeroed before layout on purpose. Removing a constraint
    /// from this axis does not make it measure zero — it makes it
    /// *ambiguous*, and an ambiguous axis is answered by whatever the views
    /// already carry, so an assertion on an un-zeroed frame reads back the
    /// size the view arrived with and passes either way.
    func testHostedBareViewGetsANonZeroLengthOnALeftRightBar() throws {
        let host = NSViewController()
        host.view = NSView()
        let bar = TabBarView(edge: .left)
        bar.hostController = host

        let content = NSViewController()
        content.view = NSView()
        content.preferredContentSize = NSSize(width: 120, height: 90)
        bar.setItems([.init(id: UUID(), item: .viewController(content))], selectedID: nil)

        let hostedView = try XCTUnwrap(content.view.superview)
        hostedView.frame = .zero
        content.view.frame = .zero

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor)
        ])
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(hostedView.frame.height, 90, accuracy: 0.5)

        // The second half of the contract: the length tracks a later change,
        // with no `updateThickness()` call in between. Nothing in this file
        // re-pins it, so if this ever regresses the cause is the borrowed
        // guarantee above going away, not a stale constant here.
        content.preferredContentSize = NSSize(width: 120, height: 150)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(hostedView.frame.height, 150, accuracy: 0.5)
    }

    /// The same contract on the swapped axis: top/bottom bars run
    /// horizontally, so the length axis is width.
    func testHostedBareViewGetsANonZeroLengthOnATopBottomBar() throws {
        let host = NSViewController()
        host.view = NSView()
        let bar = TabBarView(edge: .top)
        bar.hostController = host

        let content = NSViewController()
        content.view = NSView()
        content.preferredContentSize = NSSize(width: 250, height: 40)
        bar.setItems([.init(id: UUID(), item: .viewController(content))], selectedID: nil)

        let hostedView = try XCTUnwrap(content.view.superview)
        hostedView.frame = .zero
        content.view.frame = .zero

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 60))
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor)
        ])
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(hostedView.frame.width, 250, accuracy: 0.5)

        content.preferredContentSize = NSSize(width: 300, height: 40)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(hostedView.frame.width, 300, accuracy: 0.5)
    }

    // MARK: - Task 11 fix round 2: the cross-axis relationship the +17/+1 constants promise

    /// Pins `TabBarView.updateThickness()`'s `+ 17` constant by measuring the
    /// relationship it exists to guarantee, not by reading back a hardcoded
    /// thickness number: a hosted item's content view, once laid out, must
    /// receive *exactly* its own `preferredContentSize.width` on the bar's
    /// cross axis (17 = the host's 8+8pt leading/trailing pins in
    /// `rebuildButtons()` plus the 1pt `edgeDivider`, both of which sit
    /// between the bar's outer edge and the content view). Too little and
    /// the constant under-allocates (content gets clipped); too much and it
    /// over-allocates (content floats in slack) — either would fail this.
    ///
    /// The frame is zeroed before layout for the same reason as
    /// `testHostedBareViewGetsANonZeroLengthOnALeftRightBar`: an axis with
    /// its constraint removed goes ambiguous, not zero, and an unzeroed
    /// frame would read back whatever size the view already carried.
    func testHostedItemReceivesExactlyItsPreferredWidthOnALeftRightBar() throws {
        let host = NSViewController()
        host.view = NSView()
        let bar = TabBarView(edge: .left)
        bar.hostController = host

        let content = NSViewController()
        content.view = NSView()
        content.preferredContentSize = NSSize(width: 200, height: 64)
        bar.setItems([.init(id: UUID(), item: .viewController(content))], selectedID: nil)

        let hostedView = try XCTUnwrap(content.view.superview)
        hostedView.frame = .zero
        content.view.frame = .zero

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor)
        ])
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(content.view.frame.width, 200, accuracy: 0.5)
    }

    /// The same relationship on the swapped axis, pinning `+ 1`: a
    /// top/bottom bar's hosted content view must receive exactly its
    /// `preferredContentSize.height` (there is no left/right-style
    /// cross-axis inset on this axis, so the only consumer between the bar's
    /// edge and the content view is the 1pt `edgeDivider`).
    func testHostedItemReceivesExactlyItsPreferredHeightOnATopBottomBar() throws {
        let host = NSViewController()
        host.view = NSView()
        let bar = TabBarView(edge: .top)
        bar.hostController = host

        let content = NSViewController()
        content.view = NSView()
        content.preferredContentSize = NSSize(width: 120, height: 40)
        bar.setItems([.init(id: UUID(), item: .viewController(content))], selectedID: nil)

        let hostedView = try XCTUnwrap(content.view.superview)
        hostedView.frame = .zero
        content.view.frame = .zero

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 100))
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor)
        ])
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(content.view.frame.height, 40, accuracy: 0.5)
    }
}
