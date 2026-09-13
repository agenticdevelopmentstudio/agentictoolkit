import AgenticToolkitCore
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// A tab bar published one address per tab — the close button — so the
/// accessibility tree offered a way to destroy a tab and no way to choose one.
/// Every driven check that turns on *switching* tabs was therefore unwritable,
/// including the one the Document pane exists to satisfy: clicking between two
/// tabs holding different numbers of editors must not change the pane's width.
///
/// These pin the address, the press, and the one thing the press has to leave
/// behind — the close button that was there before it.
@MainActor
final class TabBarAccessibilityTests: XCTestCase {

    private func makeController() -> MultiTabbedViewController {
        let controller = MultiTabbedViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        return controller
    }

    private func makeContent() -> NSViewController {
        let content = NSViewController()
        content.view = NSView()
        return content
    }

    @discardableResult
    private func addTitleTab(
        _ title: String,
        id: UUID = UUID(),
        to controller: MultiTabbedViewController
    ) -> UUID {
        controller.addTab(.init(id: id, item: .title(title), viewController: makeContent()), on: .top)
        return id
    }

    /// Every view in the bar carrying an accessibility identifier, found by
    /// walking rather than by index: the bar's internal view nesting is its own
    /// business and is not what these tests are about.
    private func identified(in controller: MultiTabbedViewController) -> [String: NSView] {
        guard let bar = controller.tabBars[.top] else { return [:] }
        var found: [String: NSView] = [:]
        func walk(_ view: NSView) {
            let id = view.accessibilityIdentifier()
            if !id.isEmpty {
                found[id] = view
            }
            view.subviews.forEach(walk)
        }
        walk(bar)
        return found
    }

    private func tabElement(
        _ id: UUID,
        in controller: MultiTabbedViewController
    ) throws -> NSView {
        try XCTUnwrap(identified(in: controller)["tab-bar.select.\(id.uuidString)"],
                      "no addressable tab for \(id)")
    }

    // MARK: - The address

    func testEachTabIsAddressableByItsOwnIdentifier() throws {
        let controller = makeController()
        let first = addTitleTab("One", to: controller)
        let second = addTitleTab("Two", to: controller)

        let ids = Set(identified(in: controller).keys)

        XCTAssertTrue(ids.contains("tab-bar.select.\(first.uuidString)"))
        XCTAssertTrue(ids.contains("tab-bar.select.\(second.uuidString)"))
        XCTAssertNotEqual(first, second, "two tabs, two addresses")
    }

    func testATabIsAButtonLabelledByItsTitle() throws {
        let controller = makeController()
        let id = addTitleTab("Readme.md", to: controller)

        let tab = try tabElement(id, in: controller)

        XCTAssertTrue(tab.isAccessibilityElement())
        XCTAssertEqual(tab.accessibilityRole(), .button)
        XCTAssertEqual(tab.accessibilityTitle(), "Readme.md")
    }

    func testRetitlingATabRelabelsIt() throws {
        let controller = makeController()
        let id = addTitleTab("Untitled", to: controller)

        controller.renameTab(id: id, title: "Notes.md")

        XCTAssertEqual(try tabElement(id, in: controller).accessibilityTitle(), "Notes.md")
    }

    // MARK: - The press

    /// The whole point: a press selects, exactly as a click does, so a driven
    /// check can switch tabs without synthesizing a click at a screen point.
    func testPressingATabSelectsIt() throws {
        let controller = makeController()
        let first = addTitleTab("One", to: controller)
        let second = addTitleTab("Two", to: controller)
        XCTAssertEqual(controller.selectedTabID(on: .top), first, "the first tab starts selected")

        _ = try tabElement(second, in: controller).accessibilityPerformPress()

        XCTAssertEqual(controller.selectedTabID(on: .top), second)
    }

    /// A press that returned successfully and selected nothing would be
    /// indistinguishable from one that worked, so the selected tab has to say
    /// so where the driver can read it.
    func testTheSelectedTabSaysSoAndTheOthersSayTheyAreNot() throws {
        let controller = makeController()
        let first = addTitleTab("One", to: controller)
        let second = addTitleTab("Two", to: controller)

        XCTAssertEqual(try tabElement(first, in: controller).accessibilityValue() as? Bool, true)
        XCTAssertEqual(try tabElement(second, in: controller).accessibilityValue() as? Bool, false)

        controller.selectTab(id: second, on: .top)

        XCTAssertEqual(try tabElement(first, in: controller).accessibilityValue() as? Bool, false)
        XCTAssertEqual(try tabElement(second, in: controller).accessibilityValue() as? Bool, true)
    }

    // MARK: - What becoming an element must not cost

    /// An accessibility element's subviews stop being published in its place, so
    /// the close button had to be republished deliberately. `tab-bar.close.<id>`
    /// is an address that already existed; gaining one must not lose one.
    func testTheCloseButtonIsStillPublishedUnderTheTab() throws {
        let controller = makeController()
        let id = addTitleTab("One", to: controller)

        let tab = try tabElement(id, in: controller)
        let children = (tab.accessibilityChildren() as? [NSView]) ?? []

        XCTAssertEqual(
            children.map { $0.accessibilityIdentifier() },
            ["tab-bar.close.\(id.uuidString)"])
    }

    /// A hosted tab's bar content is a view controller the host supplied, with
    /// identifiers of its own that callers already address. It is deliberately
    /// left as a container, so nothing inside it is hidden.
    func testAHostedTabIsNotTurnedIntoAnOpaqueButton() throws {
        let controller = makeController()
        let hosted = NSViewController()
        hosted.view = NSView().accessibilityID("hosted.content")
        let id = UUID()
        controller.addTab(
            .init(id: id, item: .viewController(hosted), viewController: makeContent()),
            on: .top)

        let views = identified(in: controller)

        XCTAssertNil(views["tab-bar.select.\(id.uuidString)"],
                     "a hosted tab is not republished as one opaque button")
        let content = try XCTUnwrap(views["hosted.content"], "the host's own identifier survives")
        // A container, so what the host put inside it still reaches the tree.
        // The wrapper's own `mouseDown` is what selects a hosted tab; there is
        // nothing for a press to land on, and that is the trade being pinned.
        XCTAssertFalse(try XCTUnwrap(content.superview).isAccessibilityElement())
    }
}
