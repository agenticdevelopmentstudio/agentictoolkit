import Testing
import AppKit
import Foundation
import AgenticDeveloperToolkitUI
@testable import AgenticToolkitMacOS

@MainActor
@Suite("NoteEditorViewController")
struct NoteEditorViewControllerTests {

    private func loaded() -> NoteEditorViewController {
        let controller = NoteEditorViewController()
        _ = controller.view
        controller.viewDidLoad()
        return controller
    }

    private func note(title: String = "Groceries", content: String = "# Groceries\n\nMilk") -> Note {
        Note(id: UUID(), title: title, content: content,
             createdDate: Date(), modifiedDate: Date(), isPinned: false)
    }

    @Test("showing a note loads its markdown into the editor")
    func showLoadsContent() {
        let controller = loaded()
        controller.show(note: note())
        #expect(controller.editorController.content == "# Groceries\n\nMilk")
    }

    @Test("all three modes are offered in the full notes window")
    func fullEditorOffersPreview() {
        #expect(loaded().editorController.isPreviewAvailable)
    }

    @Test("loading a note programmatically does not report an edit")
    func programmaticLoadIsNotAnEdit() {
        let controller = loaded()
        let recorder = ChangeRecorder()
        controller.delegate = recorder
        controller.show(note: note())
        #expect(recorder.contentChanges.isEmpty)
    }

    @Test("a typed edit reaches the delegate with the note's id")
    func typedEditNotifiesTheDelegate() {
        let controller = loaded()
        let recorder = ChangeRecorder()
        controller.delegate = recorder
        let note = note()
        controller.show(note: note)
        controller.editorController.simulateUserEdit("# Groceries\n\nMilk\nBread")
        #expect(recorder.contentChanges == [note.id])
    }

    @Test("showing no note clears the editor")
    func showingNilClears() {
        let controller = loaded()
        controller.show(note: note())
        controller.show(note: nil)
        #expect(controller.editorController.content.isEmpty)
    }

    @Test("quick note is edit-only — no room for a mode switcher")
    func quickNoteIsEditOnly() {
        let controller = QuickNoteWindowController(onSave: { _, _ in })
        _ = controller.window
        #expect(controller.editorController.isPreviewAvailable == false)
        #expect(controller.editorController.mode == .edit)
    }
}

private final class ChangeRecorder: NoteEditorViewControllerDelegate {
    var contentChanges: [UUID] = []
    func noteEditorDidChangeTitle(_ title: String, for id: UUID) {}
    func noteEditorDidChangeContent(_ content: String, for id: UUID) { contentChanges.append(id) }
    func noteEditorDidRequestPin(for id: UUID) {}
    func noteEditorDidRequestDelete(for id: UUID) {}
}
