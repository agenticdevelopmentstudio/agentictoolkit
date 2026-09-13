import XCTest
@testable import AgenticToolkitHTDV

@MainActor
final class PlainTextMarkdownEditingTests: XCTestCase {
    func testEditorShowsInitialTextAndReportsChanges() {
        var received: [String] = []
        let editing = PlainTextMarkdownEditing()
        let controller = editing.makeEditor(initialText: "# Hello") { received.append($0) }
        guard let editor = controller as? PlainTextEditorViewController else {
            return XCTFail("expected PlainTextEditorViewController")
        }
        editor.loadViewIfNeeded()
        XCTAssertEqual(editor.text, "# Hello")
        editor.replaceText(with: "# Hello world")
        XCTAssertEqual(received, ["# Hello world"])
        XCTAssertEqual(editor.text, "# Hello world")
    }

    func testViewerIsReadOnlyAndShowsText() {
        let editing = PlainTextMarkdownEditing()
        let controller = editing.makeViewer(text: "plain")
        guard let viewer = controller as? PlainTextViewerViewController else {
            return XCTFail("expected PlainTextViewerViewController")
        }
        viewer.loadViewIfNeeded()
        XCTAssertEqual(viewer.text, "plain")
        XCTAssertFalse(viewer.textView.isEditable)
    }

    /// Exercises the real delegate/notification path a keystroke would take: it edits the text view through
    /// `insertText(_:replacementRange:)` (the same entry point AppKit's key-event handling uses) instead of
    /// calling `onChange` directly, proving the delegate wiring — not just the closure — actually fires.
    func testEditorNotifiesOnChangeWhenTextViewIsEditedLikeAKeystroke() {
        var received: [String] = []
        let editing = PlainTextMarkdownEditing()
        let controller = editing.makeEditor(initialText: "start") { received.append($0) }
        guard let editor = controller as? PlainTextEditorViewController else {
            return XCTFail("expected PlainTextEditorViewController")
        }
        editor.loadViewIfNeeded()
        let endOfText = NSRange(location: (editor.textView.string as NSString).length, length: 0)
        editor.textView.insertText("!", replacementRange: endOfText)
        XCTAssertEqual(received, ["start!"])
        XCTAssertEqual(editor.text, "start!")
    }
}
