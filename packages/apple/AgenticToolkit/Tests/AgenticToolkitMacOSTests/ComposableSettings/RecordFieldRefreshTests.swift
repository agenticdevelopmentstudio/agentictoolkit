import AppKit
import Testing
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// How a record pane puts stored values back into its fields: `FieldSync`,
/// the `refresh()`/`revert()` pair on every view model, and the record pane
/// base class that reports an edit only when it changes something.
@Suite(.serialized)
@MainActor
struct RecordFieldRefreshTests {

    /// A window holding `view`, so a field in it can take a field editor.
    private func host(_ view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        return window
    }

    // MARK: - FieldSync

    @Test func loadReplacesAFieldNobodyIsTypingIn() {
        let field = NSTextField(string: "old")
        ComposableSettings.FieldSync.load(field, "new")
        #expect(field.stringValue == "new")
    }

    @Test func loadLeavesAFieldBeingTypedInAlone() {
        let field = NSTextField(string: "typing")
        let window = host(field)
        #expect(window.makeFirstResponder(field))
        #expect(field.currentEditor() != nil)

        ComposableSettings.FieldSync.load(field, "stored")

        #expect(field.stringValue == "typing", "a poll mid-word never replaces what is typed")
    }

    @Test func forceDiscardsTheEditInProgress() {
        let field = NSTextField(string: "refused")
        let window = host(field)
        #expect(window.makeFirstResponder(field))

        ComposableSettings.FieldSync.force(field, "stored")

        #expect(field.stringValue == "stored")
        #expect(field.currentEditor() == nil, "ending the edit later can't send the refused text again")
    }

    @Test func selectPicksByRepresentedValueNotTitle() {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for (title, value) in [("Acme", "c1"), ("Acme", "c2")] {
            // `addItem(withTitle:)` drops an item with the same title; the menu keeps both.
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = value
            popup.menu?.addItem(item)
        }
        ComposableSettings.FieldSync.select("c2", in: popup)
        #expect(popup.indexOfSelectedItem == 1)
        ComposableSettings.FieldSync.select("gone", in: popup)
        #expect(popup.indexOfSelectedItem == -1)
    }

    // MARK: - ViewModel refresh / revert

    @Test func refreshShowsAStoredValueThatChangedUnderTheRow() {
        var stored = "Acme"
        let model = ComposableSettings.ViewModel<String>(title: "Name", get: { stored }, set: { stored = $0 })
        let row = ComposableSettings.TextEditView(with: model)
        #expect(row.textField.stringValue == "Acme")

        stored = "Acme Corp"
        model.refresh()

        #expect(row.textField.stringValue == "Acme Corp")
    }

    @Test func refreshLeavesAnEditAloneButRevertDiscardsIt() {
        var stored = "Acme"
        let model = ComposableSettings.ViewModel<String>(title: "Name", get: { stored }, set: { stored = $0 })
        let row = ComposableSettings.TextEditView(with: model)
        let window = host(row)
        #expect(window.makeFirstResponder(row.textField))
        row.textField.stringValue = "Refused name"

        model.refresh()
        #expect(row.textField.stringValue == "Refused name")

        model.revert()
        #expect(row.textField.stringValue == "Acme")
        #expect(row.textField.currentEditor() == nil)
    }

    // MARK: - Choice commands

    @Test func updateChoicesReplacesOnlyARealChange() {
        var stored = "a"
        let model = ComposableSettings.ChoiceViewModel<String>(
            title: "Client", choices: [.init(label: "A", value: "a")], get: { stored }, set: { stored = $0 })
        #expect(model.updateChoices([.init(label: "A", value: "a")]) == false)
        #expect(model.updateChoices([.init(label: "A", value: "a"), .init(label: "B", value: "b")]))
        #expect(model.choices.map(\.value) == ["a", "b"])
    }

    @Test func aCommandRunsWithoutChangingTheValue() throws {
        var stored = "a"
        var added = 0
        let model = ComposableSettings.ChoiceViewModel<String>(
            title: "Client",
            choices: [.init(label: "A", value: "a"), .init(label: "B", value: "b")],
            get: { stored }, set: { stored = $0 })
        model.commands = [.init(title: "Add Client…") { added += 1 }]
        let view = ComposableSettings.PopupMenuChoiceView(viewModel: model)
        let popup = view.popUpButton

        #expect(view.commandItems.map(\.title) == ["Add Client…"])
        let command = try #require(view.commandItems.first)
        popup.select(command)
        popup.sendAction(popup.action, to: popup.target)

        #expect(added == 1)
        #expect(stored == "a", "a command is never a value")
        #expect(popup.selectedItem?.representedObject as? String == "a", "the selection goes back to the value")
    }

    // MARK: - RecordDetailPanel

    private struct Note: RecordDetailItem, Equatable {
        var id: String
        var recordTitle: String
    }

    @Test func commitReportsOnlyAnEditThatChangesTheRecord() {
        let panel = ComposableSettings.RecordDetailPanel<Note>(
            record: Note(id: "n1", recordTitle: "Draft"), icon: nil)
        var saved: [Note] = []
        panel.onSave = { saved.append($0) }

        panel.commit(Note(id: "n1", recordTitle: "Draft"))
        #expect(saved.isEmpty, "ending an edit on the value it began with writes nothing")

        panel.commit(Note(id: "n1", recordTitle: "Final"))
        #expect(saved.map(\.recordTitle) == ["Final"])
        #expect(panel.record.recordTitle == "Final")
        #expect(panel.descriptor.title == "Final", "the sidebar row follows the record")
    }

    @Test func adoptRetitlesWithoutSaving() {
        let panel = ComposableSettings.RecordDetailPanel<Note>(
            record: Note(id: "n1", recordTitle: "Draft"), icon: nil)
        var saved = 0
        panel.onSave = { _ in saved += 1 }

        panel.adopt(Note(id: "n1", recordTitle: "Renamed elsewhere"))

        #expect(saved == 0)
        #expect(panel.descriptor.title == "Renamed elsewhere")
    }

    // MARK: - ContactFieldsView revert

    @Test func revertDiscardsTheRefusedFieldsEditButKeepsAnother() {
        let view = ComposableSettings.ContactFieldsView(title: "Contact", accessibilityPrefix: "tests.contact")
        let stored = ComposableSettings.ContactDetails(contactName: "Dana", email: "dana@example.com")
        view.details = stored
        let window = host(view)
        let attempted = ComposableSettings.ContactDetails(contactName: "Dana", email: "not an email")

        // The refused field, still being edited: its text is what failed.
        #expect(window.makeFirstResponder(view.emailField.textField))
        view.emailField.textField.stringValue = "not an email"
        view.revert(attempted: attempted, stored: stored)
        #expect(view.details == stored)
        #expect(view.emailField.textField.stringValue == "dana@example.com")
        #expect(view.emailField.textField.currentEditor() == nil)

        // A field tabbed into since, whose value was not part of the refused write.
        #expect(window.makeFirstResponder(view.phoneField.textField))
        view.phoneField.textField.stringValue = "555"
        view.revert(attempted: attempted, stored: stored)
        #expect(view.phoneField.textField.stringValue == "555", "what is being typed there is kept")
    }
}
