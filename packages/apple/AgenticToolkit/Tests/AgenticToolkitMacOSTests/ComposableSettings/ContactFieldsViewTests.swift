import AppKit
import Testing
@testable import AgenticToolkitMacOS

@Suite(.serialized)
@MainActor
struct ContactFieldsViewTests {

    private func makeView() -> ComposableSettings.ContactFieldsView {
        ComposableSettings.ContactFieldsView(title: "Contact", accessibilityPrefix: "client.contact")
    }

    @Test func startsEmpty() {
        let view = makeView()
        #expect(view.details == ComposableSettings.ContactDetails())
        #expect(view.contactNameField.textField.stringValue == "")
    }

    @Test func settingDetailsFillsEveryField() {
        let view = makeView()
        view.details = ComposableSettings.ContactDetails(
            contactName: "Dana Ito", email: "dana@example.com",
            phone: "+1 555 0100", url: "https://example.com")

        #expect(view.contactNameField.textField.stringValue == "Dana Ito")
        #expect(view.emailField.textField.stringValue == "dana@example.com")
        #expect(view.phoneField.textField.stringValue == "+1 555 0100")
        #expect(view.urlField.textField.stringValue == "https://example.com")
    }

    @Test func settingDetailsDoesNotReportAChange() {
        let view = makeView()
        var reported: [ComposableSettings.ContactDetails] = []
        view.onChange = { reported.append($0) }

        view.details = ComposableSettings.ContactDetails(contactName: "Dana Ito")

        #expect(reported.isEmpty)
    }

    @Test func editingAFieldReportsTheWholeRecord() {
        let view = makeView()
        view.details = ComposableSettings.ContactDetails(contactName: "Dana Ito")
        var reported: [ComposableSettings.ContactDetails] = []
        view.onChange = { reported.append($0) }

        view.emailField.textField.stringValue = "dana@example.com"
        view.emailField.textField.sendAction(
            view.emailField.textField.action, to: view.emailField.textField.target)

        #expect(reported.count == 1)
        #expect(reported.first?.email == "dana@example.com")
        #expect(reported.first?.contactName == "Dana Ito")
        #expect(view.details.email == "dana@example.com")
    }

    @Test func fieldsCarryAccessibilityIdentifiers() {
        let view = makeView()
        #expect(view.contactNameField.textField.accessibilityIdentifier() == "client.contact.name")
        #expect(view.emailField.textField.accessibilityIdentifier() == "client.contact.email")
        #expect(view.phoneField.textField.accessibilityIdentifier() == "client.contact.phone")
        #expect(view.urlField.textField.accessibilityIdentifier() == "client.contact.url")
    }

    @Test func detailsSurviveARoundTrip() {
        let view = makeView()
        let details = ComposableSettings.ContactDetails(
            contactName: "Dana Ito", email: "dana@example.com",
            phone: "+1 555 0100", url: "https://example.com")
        view.details = details
        #expect(view.details == details)
    }

    /// Review V23-f: a reload while someone types in a field keeps what they
    /// typed, still refreshes the other fields, and the edit is saved when it ends.
    @Test func reloadingKeepsTheFieldBeingEdited() {
        let view = makeView()
        view.details = ComposableSettings.ContactDetails(contactName: "Dana Ito", email: "old@example.com")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        #expect(window.makeFirstResponder(view.emailField.textField))
        view.emailField.textField.currentEditor()?.string = "typed@exam"
        var reported: [ComposableSettings.ContactDetails] = []
        view.onChange = { reported.append($0) }

        view.details = ComposableSettings.ContactDetails(contactName: "Dana Ito-Park", email: "old@example.com")

        #expect(view.emailField.textField.currentEditor()?.string == "typed@exam")
        #expect(view.contactNameField.textField.stringValue == "Dana Ito-Park")

        window.makeFirstResponder(nil)
        #expect(view.emailField.textField.stringValue == "typed@exam")
        window.close()
    }
}
