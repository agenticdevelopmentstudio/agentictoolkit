import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// One client's pane in the Clients window. It has three cards: who the client
/// is, how to reach them, and how they are billed.
///
/// The record, the sidebar title and `onSave` are `RecordDetailPanel`'s. It
/// never talks to the daemon itself, so a failed save is handled in one
/// place, `ClientsWindowController`, rather than once per field.
@MainActor
public final class ClientDetailPanel: ComposableSettings.RecordDetailPanel<BillingClientDTO> {

    /// The client as last stored or shown.
    public var client: BillingClientDTO { record }

    public private(set) var nameField: ComposableSettings.TextEditView!
    public private(set) var contactFields: ComposableSettings.ContactFieldsView!
    public private(set) var currencyField: ComposableSettings.TextEditView!
    public private(set) var archivedToggle: ComposableSettings.CheckboxView!
    public private(set) var notesField: ComposableSettings.TextAreaEditView!

    private var nameModel: ComposableSettings.ViewModel<String>!
    private var currencyModel: ComposableSettings.ViewModel<String>!
    private var archivedModel: ComposableSettings.ViewModel<Bool>!
    private var notesModel: ComposableSettings.ViewModel<String>!

    public init(client: BillingClientDTO) {
        super.init(
            record: client,
            icon: NSImage(systemSymbolName: "person.crop.square", accessibilityDescription: nil)
        )
    }

    public override var nameTextField: NSTextField? { nameField?.textField }

    public override var searchKeywords: [String] {
        [client.name, client.contactName, client.email, "client", "contact", "currency"]
            .filter { !$0.isEmpty }
    }

    public override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "Clients",
                body: "A client is who a project bills. Projects choose their client in the "
                    + "Projects window; a project with no client is your own work."
            ),
            .init(
                title: "Currency",
                body: "The client's currency is copied onto each billable when it is "
                    + "written, so changing it later never rewrites what is recorded."
            ),
            .init(
                title: "Archiving and Deleting",
                body: "Archiving keeps a client on file but takes it out of the project "
                    + "chooser. Deleting a client keeps its projects and tracked time; the "
                    + "projects become your own work."
            )
        ])
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        let identity = ComposableSettings.GroupView(withTitle: "Client")
        nameModel = ComposableSettings.ViewModel<String>(
            title: "Name",
            get: { [weak self] in self?.client.name ?? "" },
            set: { [weak self] text in
                guard let self else { return }
                let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                // A client with no name is a row no one can find again. It is
                // refused by not saving it: the field re-reads `get` after every
                // set and shows the stored name again.
                guard !name.isEmpty else { return }
                self.commit(self.client.replacing(name: name))
            }
        )
        nameField = ComposableSettings.TextEditView(with: nameModel)
        _ = nameField.textField.accessibilityID("billing.client.name")
        identity.addSettingSubview(nameField)
        addGroup(identity)

        contactFields = ComposableSettings.ContactFieldsView(
            title: "Contact", accessibilityPrefix: "billing.client.contact")
        contactFields.details = Self.contactDetails(of: client)
        contactFields.onChange = { [weak self] details in
            guard let self else { return }
            self.commit(self.client.replacing(
                contactName: details.contactName, email: details.email,
                phone: details.phone, url: details.url))
        }
        addGroup(contactFields)

        let billing = ComposableSettings.GroupView(withTitle: "Billing")
        currencyModel = ComposableSettings.ViewModel<String>(
            title: "Currency",
            get: { [weak self] in self?.client.currency ?? "" },
            set: { [weak self] text in
                guard let self else { return }
                // Refused or not, the field re-reads `get` after the set.
                guard let code = CurrencyCode.normalized(text) else { return }
                self.commit(self.client.replacing(currency: code))
            },
            explanation: "Three-letter code, e.g. USD, GBP, EUR."
        )
        currencyField = ComposableSettings.TextEditView(with: currencyModel)
        _ = currencyField.textField.accessibilityID("billing.client.currency")
        billing.addSettingSubview(currencyField)

        archivedModel = ComposableSettings.ViewModel<Bool>(
            title: "Archived",
            get: { [weak self] in self?.client.archived ?? false },
            set: { [weak self] archived in
                guard let self else { return }
                self.commit(self.client.replacing(archived: archived))
            },
            explanation: "Kept on file, but no longer offered when choosing a project's client."
        )
        archivedToggle = ComposableSettings.CheckboxView(with: archivedModel)
        _ = archivedToggle.toggle.accessibilityID("billing.client.archived")
        billing.addSettingSubview(archivedToggle)

        notesModel = ComposableSettings.ViewModel<String>(
            title: "Notes",
            get: { [weak self] in self?.client.notes ?? "" },
            set: { [weak self] notes in
                guard let self else { return }
                self.commit(self.client.replacing(notes: notes))
            }
        )
        notesField = ComposableSettings.TextAreaEditView(with: notesModel, visibleLines: 5)
        _ = notesField.textView.accessibilityID("billing.client.notes")
        billing.addSettingSubview(notesField)
        addGroup(billing)
    }

    // MARK: - Model → fields

    /// Hands the pane the record's current stored values. `ClientsWindowController`
    /// calls this on every reload, whether or not the record changed; a field
    /// being typed in keeps what is typed.
    public func apply(_ fresh: BillingClientDTO) {
        adopt(fresh)
        guard isViewLoaded else { return }
        nameModel.refresh()
        currencyModel.refresh()
        archivedModel.refresh()
        let details = Self.contactDetails(of: fresh)
        // `details =` writes all four fields at once. It only runs when a value
        // actually moved, so an unchanged tick never touches a half-typed email.
        if contactFields.details != details {
            contactFields.details = details
        }
        notesModel.refresh()
    }

    /// After a save the daemon refused: the stored values, and every field
    /// whose attempted value was refused shows the stored one again — even
    /// the one still being edited, whose text is exactly what failed.
    public func revert(attempted: BillingClientDTO, stored: BillingClientDTO) {
        apply(stored)
        guard isViewLoaded else { return }
        if attempted.name != stored.name { nameModel.revert() }
        if attempted.currency != stored.currency { currencyModel.revert() }
        contactFields.revert(
            attempted: Self.contactDetails(of: attempted), stored: Self.contactDetails(of: stored))
        if attempted.notes != stored.notes { notesModel.revert() }
    }

    private static func contactDetails(of client: BillingClientDTO) -> ComposableSettings.ContactDetails {
        ComposableSettings.ContactDetails(
            contactName: client.contactName, email: client.email,
            phone: client.phone, url: client.url)
    }
}
