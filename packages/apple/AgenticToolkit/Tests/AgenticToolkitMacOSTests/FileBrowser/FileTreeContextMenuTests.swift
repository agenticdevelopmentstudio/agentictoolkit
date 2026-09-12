import XCTest
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// The context menu is the only way the three verbs — replace in place, a new
/// tab, a second editor beside the first — can travel: plain selection can
/// only say *what* was picked, never *where* it should land. These pin the
/// menu's contents and that each item sends its own `DocumentDestination`.
///
/// They also pin the half that has nothing to do with opening: a folder and a
/// repo root have no document, and the menu on them is the two path verbs
/// rather than nothing at all.
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

    func testTheMenuOffersTheThreeVerbsThenThePathVerbs() throws {
        let (controller, directory) = try makeOutlineController()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        controller.loadViewIfNeeded()

        let fileURL = directory.appendingPathComponent("a.swift")
        try "// hello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let menu = try XCTUnwrap(controller.makeContextMenu(for: fileURL))

        XCTAssertEqual(
            menu.items.map { $0.isSeparatorItem ? "—" : $0.title },
            ["Open", "Open in a New Tab", "Open to the Side", "—",
             "Reveal in Finder", "Copy Path"])
    }

    func testEachItemSendsItsOwnDestination() throws {
        let (controller, directory) = try makeOutlineController()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        controller.loadViewIfNeeded()

        let fileURL = directory.appendingPathComponent("a.swift")
        try "// hello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        var received: [(URL, DocumentDestination)] = []
        controller.onOpenRequest = { received.append(($0, $1)) }

        // The open verbs only. Performing the whole menu would also perform
        // "Reveal in Finder", and a test suite must not bring Finder forward.
        for item in try XCTUnwrap(controller.openMenuItems(for: fileURL)) {
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

        let items = try XCTUnwrap(controller.contextMenuItems(for: fileURL))
        XCTAssertTrue(items.allSatisfy { $0.menu == nil })

        let live = NSMenu()
        for item in items { live.addItem(item) }

        XCTAssertEqual(live.items.count, items.count)
    }

    /// A folder has no document, so the open verbs are absent — but a
    /// right-click on it used to produce no menu at all, which is the one thing
    /// a gesture must never do.
    func testAFolderGetsThePathVerbsAndNoOpenVerbs() throws {
        let (controller, directory) = try makeOutlineController()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        controller.loadViewIfNeeded()

        XCTAssertNil(controller.openMenuItems(for: directory))

        let menu = try XCTUnwrap(controller.makeContextMenu(for: directory))
        XCTAssertEqual(menu.items.map(\.title), ["Reveal in Finder", "Copy Path"])
    }

    /// A path nothing lives at is the one case that still gets nothing: revealing
    /// it selects nothing and copying it hands over a string that pastes nowhere.
    func testAMissingFileHasNoMenu() throws {
        let (controller, directory) = try makeOutlineController()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        controller.loadViewIfNeeded()

        let missing = directory.appendingPathComponent("nothing-here.swift")
        XCTAssertNil(controller.makeContextMenu(for: missing))
        XCTAssertNil(controller.pathMenuItems(for: missing))
    }

    /// The POSIX path, not the URL — what a terminal or an editor will accept.
    func testCopyPathPutsThePosixPathOnThePasteboard() throws {
        let (controller, directory) = try makeOutlineController()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        controller.loadViewIfNeeded()

        let fileURL = directory.appendingPathComponent("a.swift")
        try "// hello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let items = try XCTUnwrap(controller.pathMenuItems(for: fileURL))
        let copyItem = try XCTUnwrap(items.first { $0.title == "Copy Path" })
        _ = copyItem.target?.perform(copyItem.action, with: copyItem)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), fileURL.path)
    }
}
