import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// Task 10 (spec §8): the Notes File-menu items — New Folder, Import Markdown
/// File…, Delete Note, Delete Folder. All four live in the `.file` slot, use
/// `isEnabled` rather than `isHidden` (task-10-grounding G1 — a merely
/// unavailable item stays visible and disables itself), and are enabled only
/// while the Notes window is key.
@MainActor
final class NotesCoordinatorMenuTests: XCTestCase {

    private struct EmptyNoteStorage: NoteStorage {
        func fetchAllNotes() throws -> [Note] { [] }
        func insertNote(_ note: Note) throws {}
        func updateNote(_ note: Note) throws {}
        func deleteNote(id: UUID) throws {}
    }

    private func makeCoordinator() -> NotesCoordinator {
        let coordinator = NotesCoordinator(
            storage: EmptyNoteStorage(),
            commandRegistry: CommandRegistry()
        )
        addTeardownBlock { @MainActor in
            coordinator.notesWindowController.window?.close()
            coordinator.unregister()
        }
        return coordinator
    }

    private func fileMenuItems(_ coordinator: NotesCoordinator) -> [MenuContribution] {
        coordinator.menuContributions.filter {
            if case .file = $0.slot { return true }
            return false
        }
    }

    // MARK: - The four contributions exist, in the spec's order

    func testFileMenuHasFourItemsInTheSpecOrder() {
        let coordinator = makeCoordinator()
        let items = fileMenuItems(coordinator)

        XCTAssertEqual(items.map(\.title), [
            "New Folder", "Import Markdown File…", "Delete Note", "Delete Folder"
        ])
        XCTAssertEqual(
            items.map(\.order), items.map(\.order).sorted(),
            "orders must already sequence as the spec table, not dictionary order")
    }

    func testNoneOfTheFourUseIsHidden() {
        let coordinator = makeCoordinator()

        for item in fileMenuItems(coordinator) {
            XCTAssertNil(item.isHidden, "\(item.title) must disable itself, not disappear")
        }
    }

    // MARK: - Key equivalents

    func testNewFolderIsShiftCommandN() {
        let coordinator = makeCoordinator()
        let newFolder = fileMenuItems(coordinator).first { $0.title == "New Folder" }

        XCTAssertEqual(newFolder?.key, "n")
        XCTAssertEqual(newFolder?.modifiers, [.command, .shift])
    }

    func testTheOtherThreeItemsHaveNoKeyEquivalent() {
        let coordinator = makeCoordinator()
        let others = fileMenuItems(coordinator).filter { $0.title != "New Folder" }

        XCTAssertEqual(others.map(\.key), Array(repeating: "", count: others.count))
    }

    // MARK: - Enabled only while the Notes window is key

    func testAllFourAreDisabledWhenTheNotesWindowIsNotKey() {
        let coordinator = makeCoordinator()
        XCTAssertNil(coordinator.notesWindowController.window)

        for item in fileMenuItems(coordinator) {
            XCTAssertFalse(item.isEnabled(), "\(item.title) must be disabled with no Notes window")
        }
    }

    /// `AgenticToolkitMacOSTests` is a non-hosted unit-test bundle (no
    /// `NSApplication` main-run-loop process backs it), so `NSWindow.isKeyWindow`
    /// never flips true here even after `makeKeyAndOrderFront(nil)` — there is no
    /// reliable way in this bundle to assert the enabled side of the check.
    /// Showing the window (still not key) must not accidentally flip it either.
    func testAllFourStayDisabledWhenTheWindowIsShownButNotKey() {
        let coordinator = makeCoordinator()
        coordinator.notesWindowController.showWindow()
        XCTAssertNotNil(coordinator.notesWindowController.window)

        for item in fileMenuItems(coordinator) {
            XCTAssertFalse(item.isEnabled(), "\(item.title) must stay disabled while the window is not key")
        }
    }
}
