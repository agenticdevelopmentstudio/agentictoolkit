import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    /// The contact block a client record carries. Plain strings: none of these
    /// is validated, because a half-typed phone number is a normal state for a
    /// field someone is still typing into, and a client with no email at all is
    /// a normal client.
    public struct ContactDetails: Codable, Equatable, Sendable {
        /// The person to write to.
        public var contactName: String
        /// An email address, as typed.
        public var email: String
        /// A phone number, as typed.
        public var phone: String
        /// A website, as typed.
        public var url: String

        /// A contact block; every field defaults to empty.
        public init(
            contactName: String = "",
            email: String = "",
            phone: String = "",
            url: String = ""
        ) {
            self.contactName = contactName
            self.email = email
            self.phone = phone
            self.url = url
        }
    }

    /// Name / email / phone / URL as one themed card.
    ///
    /// The four rows are ordinary `TextEditView`s bound to closures rather than
    /// to `UserDefaults` — see `SettingObserving`. The card owns the record;
    /// every edit rewrites it and reports the whole thing, so a caller stores
    /// one value instead of reassembling four.
    @MainActor
    public final class ContactFieldsView: GroupView {

        /// Fired only for edits made in the UI. Assigning `details` is how a
        /// caller loads a record, and a load is not a change — reporting it
        /// would write the record straight back to its store on every select.
        public var onChange: ((ContactDetails) -> Void)?

        /// The record shown. Assigning it refreshes every field except one
        /// being edited, which keeps what has been typed.
        public var details: ContactDetails {
            get { storedDetails }
            set {
                isLoading = true
                defer { isLoading = false }
                storedDetails = newValue
                applyToFields()
            }
        }

        /// The four rows, exposed for layout and UI tests.
        public private(set) var contactNameField: TextEditView!
        public private(set) var emailField: TextEditView!
        public private(set) var phoneField: TextEditView!
        public private(set) var urlField: TextEditView!

        private var storedDetails = ContactDetails()
        private var isLoading = false

        /// - Parameters:
        ///   - title: the group's header.
        ///   - accessibilityPrefix: prepended to `.name`, `.email`, `.phone`
        ///     and `.url` to form each field's accessibility identifier.
        public init(title: String = "Contact", accessibilityPrefix: String) {
            // `GroupView.init(withTitle:)` is a convenience initializer, and a
            // subclass cannot chain to one — the designated init takes the
            // header view the convenience would have built.
            super.init(withHeaderView: HeaderView(title: title))

            self.contactNameField = makeField(
                title: "Name", identifier: "\(accessibilityPrefix).name",
                get: { [weak self] in self?.storedDetails.contactName ?? "" },
                set: { [weak self] value in self?.write { $0.contactName = value } })

            self.emailField = makeField(
                title: "Email", identifier: "\(accessibilityPrefix).email",
                get: { [weak self] in self?.storedDetails.email ?? "" },
                set: { [weak self] value in self?.write { $0.email = value } })

            self.phoneField = makeField(
                title: "Phone", identifier: "\(accessibilityPrefix).phone",
                get: { [weak self] in self?.storedDetails.phone ?? "" },
                set: { [weak self] value in self?.write { $0.phone = value } })

            self.urlField = makeField(
                title: "Website", identifier: "\(accessibilityPrefix).url",
                get: { [weak self] in self?.storedDetails.url ?? "" },
                set: { [weak self] value in self?.write { $0.url = value } })

            addSettingSubview(contactNameField)
            addSettingSubview(emailField)
            addSettingSubview(phoneField)
            addSettingSubview(urlField)
        }

        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func makeField(
            title: String,
            identifier: String,
            get: @escaping () -> String,
            set: @escaping (String) -> Void
        ) -> TextEditView {
            let field = TextEditView(with: ViewModel(title: title, get: get, set: set))
            _ = field.textField.accessibilityID(identifier)
            return field
        }

        /// One place where an edit lands: mutate the record, then report it.
        /// `isLoading` is what keeps `details = …` from looking like typing.
        private func write(_ mutate: (inout ContactDetails) -> Void) {
            guard !isLoading else { return }
            mutate(&storedDetails)
            onChange?(storedDetails)
        }

        /// Loads `stored` after a save of `attempted` was refused. Each field
        /// whose attempted value was refused shows the stored one again, even
        /// while it is being edited — its text is exactly what failed, so the
        /// edit is discarded rather than sent again when it ends. The others
        /// load as `details = stored` would, so a field the user has since
        /// tabbed into keeps what is being typed.
        public func revert(attempted: ContactDetails, stored: ContactDetails) {
            details = stored
            let fields: [(String, String, TextEditView)] = [
                (attempted.contactName, stored.contactName, contactNameField),
                (attempted.email, stored.email, emailField),
                (attempted.phone, stored.phone, phoneField),
                (attempted.url, stored.url, urlField)
            ]
            for (tried, kept, field) in fields where tried != kept {
                FieldSync.force(field.textField, kept)
            }
        }

        private func applyToFields() {
            // Straight to the text fields: `ClosureSettingObserver` delivers its
            // change one main-queue hop later, and a record loaded into a field
            // that still shows the previous client for a frame is the kind of
            // flicker nobody can reproduce on demand.
            //
            // A field someone is typing in is left alone: a caller reloads the
            // record on a timer or after any save, and replacing the text under
            // the cursor throws the half-typed value away. The typed value is
            // written back into the record when the edit ends. A caller that
            // loads a *different* record must end editing first
            // (`window.makeFirstResponder(nil)`), or that edit lands in it.
            show(storedDetails.contactName, in: contactNameField)
            show(storedDetails.email, in: emailField)
            show(storedDetails.phone, in: phoneField)
            show(storedDetails.url, in: urlField)
        }

        private func show(_ text: String, in field: TextEditView) {
            guard field.textField.currentEditor() == nil else { return }
            field.textField.stringValue = text
        }
    }
}
