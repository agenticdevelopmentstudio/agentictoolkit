import XCTest
@testable import AgenticToolkitMacOS

/// An arranger is installed once and governs the whole tree, not one split
/// node — a nested split has to pick it up the same way `host` and
/// `layoutParent` already propagate. This task's proof is that a host which
/// never touches `arranger` keeps today's behaviour exactly.
@MainActor
final class PaneArrangerInstallationTests: XCTestCase {

    private func makeProject() -> ProjectWorkspace {
        ProjectWindowTestSupport.makeProject(label: "PaneArrangerInstallationTests")
    }

    func testTheDefaultArrangerIsInheritedSlot() throws {
        let project = makeProject()
        let controller = ComposableTabsViewController.make(
            from: .leaf(contentType: .placeholder),
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )
        XCTAssertTrue(controller.arranger is InheritedSlotArranger)
    }

    func testAnInstalledArrangerIsInheritedByNestedSplits() throws {
        let project = makeProject()
        let controller = ComposableTabsViewController.make(
            from: .split(
                orientation: .horizontal,
                first: .leaf(contentType: .placeholder),
                second: .leaf(contentType: .placeholder)
            ),
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )
        controller.arranger = ProportionalArranger()

        let nested = controller.layoutChildren.compactMap { $0 as? ComposableTabsViewController }
        for child in nested {
            XCTAssertTrue(child.arranger is ProportionalArranger, "an arranger governs the whole tree")
        }
    }

    func testApplyArrangementSetsProportionalFractions() throws {
        let project = makeProject()
        let controller = ComposableTabsViewController.make(
            from: .split(
                orientation: .horizontal,
                first: .leaf(contentType: .placeholder),
                second: .leaf(contentType: .placeholder)
            ),
            project: project,
            workingDirectory: project.directoryURL,
            isRoot: true
        )
        controller.arranger = ProportionalArranger()

        controller.applyArrangement()

        let fractions = controller.layoutChildren.map { $0.thicknessFraction }
        XCTAssertEqual(fractions.count, 2)
        XCTAssertEqual(try XCTUnwrap(fractions[0]), 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(fractions[1]), 0.5, accuracy: 0.0001)
    }
}
