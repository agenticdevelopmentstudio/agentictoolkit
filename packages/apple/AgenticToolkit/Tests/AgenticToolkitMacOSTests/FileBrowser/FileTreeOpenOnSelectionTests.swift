import XCTest
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// Before this, selecting a file in the tree only moved
/// `FileBrowserSelection.selectedNode` — nothing routed that pick to the
/// Document pane, and a double-click on a leaf handed the file to whatever
/// app claimed its extension (Xcode, for source files) instead of showing it
/// in the app at all. `openIfFile` is the one place both a plain click
/// (`outlineViewSelectionDidChange`) and a double-click's leaf case
/// (`rowDoubleClicked`) now go through, so these pin its routing directly.
@MainActor
final class FileTreeOpenOnSelectionTests: XCTestCase {

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileTreeOpenOnSelectionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeController() throws -> (FileTreeOutlineViewController, URL) {
        let directory = try makeDirectory()
        let controller = FileTreeOutlineViewController(
            roots: FileBrowserRootsModel(),
            directories: FileBrowserDirectories(primary: directory),
            selection: FileBrowserSelection(),
            restoration: FileBrowserRestorationState(),
            documentStore: TextDocumentStore()
        )
        return (controller, directory)
    }

    func testSelectingAFileRequestsItOpenedInPlace() throws {
        let (controller, directory) = try makeController()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        controller.loadViewIfNeeded()

        let fileURL = directory.appendingPathComponent("a.swift")
        var received: [(URL, DocumentDestination)] = []
        controller.onOpenRequest = { received.append(($0, $1)) }

        controller.openIfFile(FileTreeNode(url: fileURL, isDirectory: false))

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.0, fileURL)
        XCTAssertEqual(received.first?.1, .current)
    }

    func testSelectingADirectoryRequestsNothing() throws {
        let (controller, directory) = try makeController()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        controller.loadViewIfNeeded()

        var received: [(URL, DocumentDestination)] = []
        controller.onOpenRequest = { received.append(($0, $1)) }

        // `loadChildren: false` is what every directory in the live tree
        // starts as — an unread directory, not a leaf.
        controller.openIfFile(FileTreeNode(url: directory, isDirectory: true))

        XCTAssertTrue(received.isEmpty)
    }

    func testSelectingNothingRequestsNothing() throws {
        let (controller, directory) = try makeController()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        controller.loadViewIfNeeded()

        var received: [(URL, DocumentDestination)] = []
        controller.onOpenRequest = { received.append(($0, $1)) }

        controller.openIfFile(nil)

        XCTAssertTrue(received.isEmpty)
    }

    /// `rowDoubleClicked`'s leaf branch and a plain click's selection handler
    /// both call `openIfFile` — this is the seam that used to end in
    /// `NSWorkspace.shared.open(node.url)`, handing the file to another app.
    /// Pinning that the leaf case is `openIfFile`'s case (not `toggle`'s) is
    /// what keeps a future edit from quietly restoring that hand-off.
    func testAChildlessPackageIsTreatedAsOpenableNotExpandable() throws {
        let (controller, directory) = try makeController()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        controller.loadViewIfNeeded()

        let packageURL = directory.appendingPathComponent("Bundle.custompkg")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        // A package extension is what makes `FileTreeNode` leave `children`
        // `nil` for a directory — the same shape as an ordinary file.
        let node = FileTreeNode(url: packageURL, isDirectory: true, packageExtensions: ["custompkg"])
        XCTAssertNil(node.children, "a package must read as a leaf for this test to mean anything")

        var received: [(URL, DocumentDestination)] = []
        controller.onOpenRequest = { received.append(($0, $1)) }

        controller.openIfFile(node)

        XCTAssertEqual(received.map(\.0), [packageURL])
    }
}
