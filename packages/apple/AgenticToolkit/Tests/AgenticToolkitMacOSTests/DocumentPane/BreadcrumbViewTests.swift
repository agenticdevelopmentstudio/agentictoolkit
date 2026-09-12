import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class BreadcrumbViewTests: XCTestCase {

    private let root = URL(fileURLWithPath: "/tmp/project")

    func testAnEmptyEditorShowsNoCrumbs() {
        let view = BreadcrumbView(rootURL: root)
        view.fileURL = nil
        XCTAssertEqual(view.crumbTitles, [])
    }

    func testCrumbsAreThePathRelativeToTheRoot() {
        let view = BreadcrumbView(rootURL: root)
        view.fileURL = URL(fileURLWithPath: "/tmp/project/Sources/App/Main.swift")
        XCTAssertEqual(view.crumbTitles, ["Sources", "App", "Main.swift"])
    }

    func testAFileOutsideTheRootFallsBackToItsOwnPath() {
        let view = BreadcrumbView(rootURL: root)
        view.fileURL = URL(fileURLWithPath: "/etc/hosts")
        XCTAssertEqual(view.crumbTitles.last, "hosts")
    }

    func testSelectingACrumbReportsItsDirectory() throws {
        let view = BreadcrumbView(rootURL: root)
        view.fileURL = URL(fileURLWithPath: "/tmp/project/Sources/App/Main.swift")
        var selected: URL?
        view.onSelect = { selected = $0 }

        view.selectCrumb(at: 1)

        XCTAssertEqual(selected?.path, "/tmp/project/Sources/App")
    }
}
