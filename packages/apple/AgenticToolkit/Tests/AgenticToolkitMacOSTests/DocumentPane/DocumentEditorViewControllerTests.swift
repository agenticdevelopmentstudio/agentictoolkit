import AppKit
import XCTest
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
            languageServices: nil
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
        XCTAssertEqual(rows.filter { $0 is WindowConfigToggle }.count, 3)
        XCTAssertEqual(rows.filter { ($0 as? NSButton)?.title == "Reset to Defaults" }.count, 1)
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
