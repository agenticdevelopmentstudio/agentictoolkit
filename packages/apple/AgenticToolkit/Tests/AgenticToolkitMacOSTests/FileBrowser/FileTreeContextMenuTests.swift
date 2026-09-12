import XCTest
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// The context menu is the only way the three verbs — replace in place, a new
/// tab, a second editor beside the first — can travel: plain selection can
/// only say *what* was picked, never *where* it should land. These pin the
/// menu's contents and that each item sends its own `DocumentDestination`,
/// plus that a directory (nothing to open) gets no menu at all.
@MainActor
final class FileTreeContextMenuTests: XCTestCase {

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileTreeContextMenuTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeOutlineController() throws -> (FileTreeOutlineViewController, URL) {
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

    func testTheMenuOffersTheThreeVerbs() throws {
        let (controller, directory) = try makeOutlineController()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        controller.loadViewIfNeeded()

        let fileURL = directory.appendingPathComponent("a.swift")
        try "// hello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let menu = try XCTUnwrap(controller.makeContextMenu(for: fileURL))

        XCTAssertEqual(menu.items.map(\.title), ["Open", "Open in a New Tab", "Open to the Side"])
    }

    func testEachItemSendsItsOwnDestination() throws {
        let (controller, directory) = try makeOutlineController()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        controller.loadViewIfNeeded()

        let fileURL = directory.appendingPathComponent("a.swift")
        try "// hello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        var received: [(URL, DocumentDestination)] = []
        controller.onOpenRequest = { received.append(($0, $1)) }

        let menu = try XCTUnwrap(controller.makeContextMenu(for: fileURL))
        for item in menu.items {
            _ = item.target?.perform(item.action, with: item)
        }

        XCTAssertEqual(received.map(\.1), [.current, .newTab, .toTheSide])
        XCTAssertEqual(Set(received.map(\.0)), [fileURL])
    }

    /// AppKit hands `menuNeedsUpdate` a live menu of its own and the items have
    /// to go into *that* menu, so the builder must hand back items no other menu
    /// owns — an item still belonging to a menu raises "Item to be inserted into
    /// menu already is in another menu" and the context menu never appears.
    func testTheItemsBelongToNoMenuUntilTheyAreInstalled() throws {
        let (controller, directory) = try makeOutlineController()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        controller.loadViewIfNeeded()

        let fileURL = directory.appendingPathComponent("a.swift")
        try "// hello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let items = try XCTUnwrap(controller.openMenuItems(for: fileURL))
        XCTAssertTrue(items.allSatisfy { $0.menu == nil })

        let live = NSMenu()
        for item in items { live.addItem(item) }

        XCTAssertEqual(live.items.map(\.title), ["Open", "Open in a New Tab", "Open to the Side"])
    }

    func testADirectoryHasNoOpenMenu() throws {
        let (controller, directory) = try makeOutlineController()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        controller.loadViewIfNeeded()

        XCTAssertNil(controller.makeContextMenu(for: directory))
    }

    func testAMissingFileHasNoOpenMenu() throws {
        let (controller, directory) = try makeOutlineController()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        controller.loadViewIfNeeded()

        XCTAssertNil(controller.makeContextMenu(for: directory.appendingPathComponent("nothing-here.swift")))
    }
}
