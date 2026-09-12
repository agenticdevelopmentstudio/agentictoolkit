import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class BreadcrumbPopoverViewControllerTests: XCTestCase {

    /// A directory with a few files in it, removed when the test ends. Built
    /// per test rather than in `setUp`, which is nonisolated and so cannot
    /// touch main-actor state.
    private func makeController() throws -> BreadcrumbPopoverViewController {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("breadcrumb-popover-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        for name in ["Alpha.swift", "Beta.swift", "Gamma.md"] {
            try Data().write(to: directory.appendingPathComponent(name))
        }
        return BreadcrumbPopoverViewController(directoryURL: directory) { _ in }
    }

    /// The popover has to name the size it wants, because `NSPopover` sizes an
    /// auto-layout content view to that view's fitting size and ignores its own
    /// `contentSize`. Without this the crumb's list arrives as a sliver a few
    /// points wide.
    func testTheControllerAsksForTheListsSize() throws {
        XCTAssertEqual(try makeController().preferredContentSize, NSSize(width: 280, height: 320))
    }

    func testTheContentViewDoesNotCollapseToItsSubviews() throws {
        let controller = try makeController()
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(controller.view.fittingSize.width, 280, accuracy: 1)
        XCTAssertEqual(controller.view.fittingSize.height, 320, accuracy: 1)
    }
}
