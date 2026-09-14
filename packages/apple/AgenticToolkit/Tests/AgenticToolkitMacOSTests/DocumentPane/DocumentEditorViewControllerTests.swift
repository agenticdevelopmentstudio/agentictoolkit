import AppKit
import XCTest
import AgenticToolkitCore
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

@MainActor
final class DocumentEditorViewControllerTests: XCTestCase {

    private func makeController(store: PaneStateStore = EphemeralPaneStateStore())
        -> DocumentEditorViewController {
        DocumentEditorViewController(
            store: store,
            documentStore: TextDocumentStore(),
            saveScheduler: TextDocumentSaveScheduler(write: { _ in }),
            languageServices: nil,
            rootURL: URL(fileURLWithPath: "/tmp")
        )
    }

    func testAnEmptyEditorIsTitledUntitled() {
        XCTAssertEqual(makeController().paneTitle, "Untitled")
    }

    func testTheTitleIsTheFileName() {
        let controller = makeController()
        controller.fileURL = URL(fileURLWithPath: "/tmp/example/Readme.md")
        XCTAssertEqual(controller.paneTitle, "Readme.md")
    }

    func testSettingAFilePersistsIt() {
        let store = EphemeralPaneStateStore()
        let controller = makeController(store: store)

        controller.fileURL = URL(fileURLWithPath: "/tmp/example/Readme.md")

        XCTAssertEqual(
            store.paneStateValue(forKey: DocumentEditorViewController.fileURLKey),
            "/tmp/example/Readme.md"
        )
    }

    func testClearingTheDocumentDeletesTheStoredPathAndKeepsThePane() {
        let store = EphemeralPaneStateStore()
        let controller = makeController(store: store)
        controller.fileURL = URL(fileURLWithPath: "/tmp/example/Readme.md")

        controller.clearDocument()

        XCTAssertNil(controller.fileURL)
        XCTAssertNil(store.paneStateValue(forKey: DocumentEditorViewController.fileURLKey))
        XCTAssertEqual(controller.paneTitle, "Untitled")
    }

    func testAStoredPathIsRestoredOnConstruction() {
        // Unlike every other test here, restoring on construction checks the
        // file is still there (see `testAStoredPathThatNoLongerExistsRestoresAnEmptyEditor`
        // below), so this is the one test in the file that needs a real file on disk.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DocumentEditorViewControllerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Readme.md")
        try? "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = EphemeralPaneStateStore()
        store.setPaneStateValue(fileURL.path, forKey: DocumentEditorViewController.fileURLKey)

        let controller = makeController(store: store)

        XCTAssertEqual(controller.fileURL?.path, fileURL.path)
    }

    func testAStoredPathThatNoLongerExistsRestoresAnEmptyEditor() {
        let store = EphemeralPaneStateStore()
        store.setPaneStateValue("/tmp/definitely/not/here-\(UUID().uuidString).swift",
                                forKey: DocumentEditorViewController.fileURLKey)

        let controller = makeController(store: store)

        XCTAssertNil(controller.fileURL, "a missing file restores as an empty editor, not a missing pane")
        XCTAssertEqual(controller.paneTitle, "Untitled")
    }

    func testTheGearOffersThreeTogglesAndAReset() {
        let rows = makeController().makePaneOptionRows()
        XCTAssertEqual(rows.filter { $0 is WindowOptionsToggle }.count, 3)
        XCTAssertEqual(rows.filter { ($0 as? NSButton)?.title == "Reset to Defaults" }.count, 1)
    }

    /// Two editors side by side, each with its own gear: flipping one pane's
    /// "Show line numbers" leaves the other following the app-wide setting.
    /// The gear is a *pane* control — that is the whole reason an editor holds
    /// an `EditorOptionsOverride` of its own rather than writing the global.
    ///
    /// Driven through the row the gear actually shows, by clicking its
    /// checkbox, because the claim is about the control and not about the model
    /// underneath it. `performClick` flips the state and sends the action, which
    /// is exactly what a mouse does.
    func testOnePanesGearDoesNotTouchAnotherPanes() throws {
        let first = makeController()
        let second = makeController()
        let global = UserSettings.editorShowLineNumbers.value

        try click(lineNumbersRowOf: first)

        XCTAssertEqual(first.options.showLineNumbers, !global, "the pane that was asked changed")
        XCTAssertTrue(first.options.isOverridden)
        XCTAssertEqual(second.options.showLineNumbers, global, "and only that pane")
        XCTAssertFalse(second.options.isOverridden)
    }

    /// Reset is the same control with the same reach: it hands *this* pane back
    /// to the app-wide setting and says nothing about any other pane — nor
    /// about the global itself, which a pane must never write.
    func testOnePanesResetDoesNotTouchAnotherPanesOrTheGlobal() throws {
        let first = makeController()
        let second = makeController()
        let global = UserSettings.editorShowLineNumbers.value
        try click(lineNumbersRowOf: first)
        try click(lineNumbersRowOf: second)
        XCTAssertTrue(second.options.isOverridden)

        let reset = try XCTUnwrap(first.makePaneOptionRows().compactMap { $0 as? NSButton }.first)
        reset.performClick(nil)

        XCTAssertFalse(first.options.isOverridden, "the pane that was asked follows the app again")
        XCTAssertTrue(second.options.isOverridden, "and only that pane")
        XCTAssertEqual(second.options.showLineNumbers, !global)
        XCTAssertEqual(UserSettings.editorShowLineNumbers.value, global,
                       "a pane control never writes the app-wide setting")
    }

    /// The first toggle the gear shows is "Show line numbers"; clicking its
    /// checkbox is what a mouse in that dialog does.
    private func click(lineNumbersRowOf controller: DocumentEditorViewController) throws {
        let row = try XCTUnwrap(
            controller.makePaneOptionRows().compactMap { $0 as? WindowOptionsToggle }.first)
        let checkbox = try XCTUnwrap(row.subviews.compactMap { $0 as? NSButton }.first)
        checkbox.performClick(nil)
    }

    func testTheResetButtonIsDisabledUntilSomethingIsOverridden() throws {
        let controller = makeController()
        let disabled = try XCTUnwrap(
            controller.makePaneOptionRows().compactMap { $0 as? NSButton }.first)
        XCTAssertFalse(disabled.isEnabled)

        controller.options.setShowOverview(false)

        let enabled = try XCTUnwrap(
            controller.makePaneOptionRows().compactMap { $0 as? NSButton }.first)
        XCTAssertTrue(enabled.isEnabled)
    }
}
