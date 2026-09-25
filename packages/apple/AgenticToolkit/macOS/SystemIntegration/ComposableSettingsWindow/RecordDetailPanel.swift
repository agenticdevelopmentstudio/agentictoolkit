import AppKit

extension ComposableSettings {

    /// The pane for one record in a ``RecordDetailWindowController``: it holds
    /// the record, keeps the sidebar title in step with it, and reports every
    /// accepted edit through `onSave`. It never writes the record anywhere
    /// itself, so a refused save is handled once, by the window's owner,
    /// rather than once per field.
    ///
    /// A subclass builds its cards in `viewDidLoad`, calls `commit(_:)` from
    /// each field's setter, and names the field `focusName()` puts the cursor
    /// in by overriding `nameTextField`.
    @MainActor
    open class RecordDetailPanel<Record: RecordDetailItem & Equatable>: SettingsPanelViewController {

        /// The record as this pane last stored or showed it.
        public private(set) var record: Record

        /// Every accepted edit, already applied to `record`.
        public var onSave: ((Record) -> Void)?

        /// - Parameter icon: the sidebar row's image.
        public init(record: Record, icon: NSImage?) {
            self.record = record
            super.init(with: SettingsPanelDescriptor(title: record.recordTitle, icon: icon))
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        /// The field a newly added record's pane puts the cursor in. Nil by default.
        open var nameTextField: NSTextField? { nil }

        /// Takes the record's current stored values without saving them, and
        /// retitles the sidebar row. A subclass's `apply` calls this first,
        /// then refreshes its fields.
        public func adopt(_ fresh: Record) {
            record = fresh
            if descriptor.title != fresh.recordTitle { descriptor.title = fresh.recordTitle }
        }

        /// Stores an edit and reports it — unless it changes nothing, so a
        /// field that ends editing on the value it began with sends no write.
        public func commit(_ edited: Record) {
            guard edited != record else { return }
            adopt(edited)
            onSave?(edited)
        }

        /// Puts the cursor in `nameTextField`, its text selected, as a newly
        /// added row expects.
        public func focusName() {
            guard isViewLoaded, let field = nameTextField else { return }
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
    }
}
