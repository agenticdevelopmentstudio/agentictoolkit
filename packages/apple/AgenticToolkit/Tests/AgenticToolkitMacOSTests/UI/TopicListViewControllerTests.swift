import XCTest
import AppKit
import AgenticToolkitMacOS

/// `preferredWidth` drives the content-sized settings sidebar: it must reflect
/// the widest row so every topic title is fully disclosed and the width is
/// deterministic (never a remembered drag).
@MainActor
final class TopicListViewControllerTests: XCTestCase {

    private func makeLoaded() -> TopicListViewController {
        let controller = TopicListViewController()
        _ = controller.view // force loadView so the outline exists
        return controller
    }

    func testPreferredWidthGrowsWithTheLongestTitle() {
        let controller = makeLoaded()

        controller.setItems([TopicListItem(id: "1", title: "Hi")])
        let narrow = controller.preferredWidth()

        controller.setItems([TopicListItem(id: "1", title: "A considerably longer topic title")])
        let wide = controller.preferredWidth()

        XCTAssertGreaterThan(wide, narrow,
            "the sidebar width must expand to fit the longest row")
    }

    func testPreferredWidthUsesTheWidestRowNotTheFirst() {
        let controller = makeLoaded()
        controller.setItems([
            TopicListItem(id: "1", title: "A"),
            TopicListItem(id: "2", title: "The widest row of them all"),
            TopicListItem(id: "3", title: "B")
        ])
        let widest = controller.preferredWidth()

        controller.setItems([TopicListItem(id: "1", title: "The widest row of them all")])
        let single = controller.preferredWidth()

        XCTAssertEqual(widest, single, accuracy: 0.5,
            "width must be driven by the widest row regardless of its position")
    }

    func testPreferredWidthIsPositiveWhenEmpty() {
        let controller = makeLoaded()
        controller.setItems([])
        XCTAssertGreaterThan(controller.preferredWidth(), 0,
            "even an empty list reserves its chrome padding")
    }

    /// Review V13-c: a selection made before the view loads is not lost.
    func testASelectionMadeBeforeTheViewLoadsIsApplied() {
        let controller = TopicListViewController()
        var reported = 0
        controller.onSelect = { _ in reported += 1 }
        controller.setItems([TopicListItem(id: "1", title: "A"), TopicListItem(id: "2", title: "B")])
        controller.selectItem(withId: "2")
        controller.setItems([TopicListItem(id: "1", title: "A"), TopicListItem(id: "2", title: "Bee")])

        _ = controller.view

        XCTAssertEqual(controller.selectedItem?.id, "2")
        XCTAssertEqual(reported, 0, "a programmatic selection fires no callback")
    }
}
