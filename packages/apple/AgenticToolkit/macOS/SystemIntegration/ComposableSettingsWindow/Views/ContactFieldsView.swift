import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    /// The contact block a client record carries. Plain strings: none of these
    /// is validated, because a half-typed phone number is a normal state for a
    /// field someone is still typing into, and a client with no email at all is
    /// a normal client.
    public struct ContactDetails: Codable, Equatable, Sendable {
        public var contactName: String
        public var email: String
        public var phone: String
        public var url: String

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
        /// would write the record straight back to the daemon on every select.
        public var onChange: ((ContactDetails) -> Void)?

        public var details: ContactDetails {
            get { storedDetails }
            set {
                isLoading = true
                defer { isLoading = false }
                storedDetails = newValue
                applyToFields()
            }
        }

        public private(set) var contactNameField: TextEditView!
        public private(set) var emailField: TextEditView!
        public private(set) var phoneField: TextEditView!
        public private(set) var urlField: TextEditView!

        private var storedDetails = ContactDetails()
        private var isLoading = false

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

        private func applyToFields() {
            // Straight to the text fields: `ClosureSettingObserver` delivers its
            // change one main-queue hop later, and a record loaded into a field
            // that still shows the previous client for a frame is the kind of
            // flicker nobody can reproduce on demand.
            contactNameField.textField.stringValue = storedDetails.contactName
            emailField.textField.stringValue = storedDetails.email
            phoneField.textField.stringValue = storedDetails.phone
            urlField.textField.stringValue = storedDetails.url
        }
    }
}
