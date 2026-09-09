import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// `activeTabDidChange` is the hook a host implements when all it needs is
/// *which tab is in front now*. Its whole value is being exhaustive, so the
/// interesting cases are the ones where the answer is "none".
@MainActor
final class MultiTabbedActiveTabTests: XCTestCase {

    private final class SpyDelegate: MultiTabbedViewControllerDelegate {
        /// Every report, in order, `nil` entries included — the point of the
        /// suite is that the empty transitions are reported at all.
        private(set) var reports: [(id: UUID?, edge: Edge?)] = []

        func multiTabbedViewController(
            _ controller: MultiTabbedViewController,
            activeTabDidChange id: UUID?,
            on edge: Edge?
        ) {
            reports.append((id, edge))
        }
    }

    private func makeTab(_ title: String) -> MultiTabbedViewController.Tab {
        let content = NSViewController()
        content.view = NSView()
        return .init(title: title, viewController: content)
    }

    /// The controller is loaded so the bars and the centre exist; nothing here
    /// asserts on layout, but `setEdgeEnabled` and `refreshCenterContent` both
    /// take their `isViewLoaded` early exits otherwise, which would make the
    /// suite pass on a controller that never did the work.
    private func makeController() -> (MultiTabbedViewController, SpyDelegate) {
        let controller = MultiTabbedViewController()
        controller.loadViewIfNeeded()
        let delegate = SpyDelegate()
        controller.delegate = delegate
        return (controller, delegate)
    }

    func testActivationNamesTheTabAndItsEdge() {
        let (controller, delegate) = makeController()
        let first = makeTab("One")
        let second = makeTab("Two")

        controller.addTab(first, on: .top)
        controller.addTab(second, on: .top)
        controller.selectTab(id: second.id, on: .top)

        XCTAssertEqual(delegate.reports.map(\.id), [first.id, second.id],
                       "the first tab onto an empty edge activates itself")
        XCTAssertEqual(delegate.reports.map(\.edge), [.top, .top])
    }

    /// Disabling the edge that held the active tab, with nowhere for the
    /// fallback to go. Without the `nil` report a host is left rendering a tab
    /// that is no longer showing — the one case where stale chrome is visibly
    /// wrong.
    func testDisablingTheLastEnabledEdgeReportsNoActiveTab() {
        let (controller, delegate) = makeController()
        let tab = makeTab("One")
        controller.addTab(tab, on: .top)

        controller.setEdgeEnabled(.top, false)

        XCTAssertNil(controller.activeTabID)
        XCTAssertEqual(delegate.reports.count, 2)
        XCTAssertNil(delegate.reports.last?.id)
        XCTAssertNil(delegate.reports.last?.edge)
    }

    /// The same clearing by the other route: the last tab leaves, and there is
    /// no neighbour and no other enabled edge to fall back to.
    func testRemovingTheLastTabReportsNoActiveTab() {
        let (controller, delegate) = makeController()
        let tab = makeTab("One")
        controller.addTab(tab, on: .top)

        controller.removeTab(id: tab.id)

        XCTAssertNil(controller.activeTabID)
        XCTAssertEqual(delegate.reports.map(\.id), [tab.id, nil])
    }

    /// Disabling an edge that is *not* the last one moves the selection rather
    /// than clearing it — the report names where it landed, not `nil`.
    func testDisablingAnEdgeWithSomewhereToFallBackToNamesWhereItLanded() {
        let (controller, delegate) = makeController()
        let top = makeTab("Top")
        let bottom = makeTab("Bottom")
        controller.setEdgeEnabled(.bottom, true)
        controller.addTab(top, on: .top)
        controller.addTab(bottom, on: .bottom)
        XCTAssertEqual(controller.activeTabID, top.id)

        controller.setEdgeEnabled(.top, false)

        XCTAssertEqual(controller.activeTabID, bottom.id)
        XCTAssertEqual(delegate.reports.last?.id, bottom.id)
        XCTAssertEqual(delegate.reports.last?.edge, .bottom)
    }
}
