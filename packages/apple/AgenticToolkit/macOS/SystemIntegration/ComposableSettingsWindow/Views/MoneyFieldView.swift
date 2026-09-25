import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    /// A labelled text row for an amount of money, stored as integer cents.
    ///
    /// Typed and shown through a `MoneyFormatter` the caller supplies — asked
    /// for afresh on every read, so a currency that changes while the pane is
    /// open re-renders the amount in the new format. Text that doesn't parse,
    /// or parses outside `range`, is refused by not writing it; the row then
    /// re-reads the stored amount and shows it again. With `allowsBlank`, an
    /// empty field writes nil ("use the fallback"), and `placeholderCents`
    /// shows what that fallback is.
    @MainActor
    public final class MoneyFieldView: NSView, SettingsViewProtocol {

        /// The row's title.
        public var label: NSTextField { row.label }
        /// The field the amount is typed into.
        public var textField: NSTextField { row.textField }

        /// The explanation drawn under the row by its ``GroupView``.
        public var settingExplanation: String? { viewModel.explanation }

        /// What a blank field stands for, drawn as the placeholder. Nil draws none.
        public var placeholderCents: Int? {
            didSet { updatePlaceholder() }
        }

        private let viewModel: ViewModel<String>
        private let row: TextEditView
        private let formatter: @MainActor () -> MoneyFormatter

        /// - Parameters:
        ///   - range: the amounts accepted, in cents.
        ///   - allowsBlank: whether an empty field writes nil.
        ///   - formatter: the formatter amounts are typed and shown in.
        ///   - get: the stored amount; nil shows an empty field.
        ///   - set: called with an accepted amount, or nil for a blank field.
        public init(
            title: String,
            range: ClosedRange<Int>,
            allowsBlank: Bool = false,
            formatter: @escaping @MainActor () -> MoneyFormatter,
            get: @escaping @MainActor () -> Int?,
            set: @escaping @MainActor (Int?) -> Void,
            explanation: String? = nil
        ) {
            self.formatter = formatter
            self.viewModel = ViewModel<String>(
                title: title,
                get: { get().map { formatter().editableString(cents: $0) } ?? "" },
                set: { text in
                    guard let parsed = Self.parse(
                        text, formatter: formatter(), range: range, allowsBlank: allowsBlank
                    ) else { return }
                    set(parsed)
                },
                explanation: explanation
            )
            self.row = TextEditView(with: viewModel)
            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false
            addSubview(row)
            Self.pinToEdges(row, of: self)
        }

        public override init(frame frameRect: NSRect) {
            fatalError("init(frame:) has not been implemented")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// Re-reads the stored amount and the placeholder, leaving a field
        /// being typed in alone. See `ViewModel.refresh()`.
        public func refresh() {
            viewModel.refresh()
            updatePlaceholder()
        }

        /// Re-reads the stored amount, discarding an edit in progress. See
        /// `ViewModel.revert()`.
        public func revert() {
            viewModel.revert()
            updatePlaceholder()
        }

        /// What `text` writes: `.some(cents)`, `.some(nil)` for an accepted
        /// blank, or nil when it is refused.
        public static func parse(
            _ text: String,
            formatter: MoneyFormatter,
            range: ClosedRange<Int>,
            allowsBlank: Bool
        ) -> Int?? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return allowsBlank ? .some(nil) : nil }
            guard let cents = formatter.cents(parsing: trimmed), range.contains(cents) else { return nil }
            return .some(cents)
        }

        private func updatePlaceholder() {
            let hint = placeholderCents.map { formatter().editableString(cents: $0) }
            if textField.placeholderString != hint { textField.placeholderString = hint }
        }
    }
}

extension ComposableSettings.MoneyFieldView: ComposableSettings.ExplainedSettingsView {}
