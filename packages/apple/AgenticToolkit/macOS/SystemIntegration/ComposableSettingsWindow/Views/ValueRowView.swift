import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    /// A read-only row: the setting's name on the left, a figure on the right,
    /// laid out like every other settings row (System Settings' "About" pane).
    ///
    /// Every other row view edits something, and showing a total in a disabled
    /// text field would suggest it could be edited. This row is a label and a
    /// value. The value is selectable, because a total is the kind of figure
    /// that gets copied into an invoice.
    @MainActor
    public final class ValueRowView: NSView, SettingsViewProtocol {

        /// The setting's name, on the left.
        public let label: ThemedLabel
        /// The figure, on the right. Selectable, so it can be copied.
        public let valueLabel: ThemedLabel

        /// The figure's text.
        public var value: String {
            get { valueLabel.stringValue }
            set { valueLabel.stringValue = newValue }
        }

        /// - Parameters:
        ///   - title: the row's name, also the value's accessibility label.
        ///   - value: the figure shown on the right.
        public init(title: String, value: String = "") {
            label = ComposableSettings.makeRowLabel(title)
            // Monospaced digits: totals that tick over must not reflow the row.
            valueLabel = ComposableSettings.makeValueLabel(value, monospacedDigits: true)
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false

            valueLabel.isSelectable = true
            valueLabel.alignment = .right
            // The value reads as the row's value, under the row's name.
            valueLabel.setAccessibilityLabel(title)

            let row = Self.makeRow([label, valueLabel])
            addSubview(row)
            Self.pinToEdges(row, of: self)
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { nil }
    }
}
