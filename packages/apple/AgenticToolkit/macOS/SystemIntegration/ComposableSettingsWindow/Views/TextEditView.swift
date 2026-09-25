import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    @MainActor
    public class TextEditView: NSView, SettingsViewProtocol {
        public let label: NSTextField
        public let textField: NSTextField

        private let viewModel: ViewModel<String>

        /// The view model's ``AbstractViewModel/explanation``, which the
        /// ``GroupView`` this is placed in draws under the row.
        public var settingExplanation: String? { viewModel.explanation }

        public init(with viewModel: ViewModel<String>) {
            self.viewModel = viewModel
            self.label = Self.createLabel(title: viewModel.title)
            self.textField = Self.makeTextField(initialValue: viewModel.value)

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            // Below the row spacer's hugging, so the field — not the gap — takes
            // the width left over after the label. An empty field sized to its
            // own content is a few points wide and unclickable.
            self.textField.setContentHuggingPriority(.init(1), for: .horizontal)

            let row = Self.makeRow([self.label, self.textField])
            self.addSubview(row)
            Self.pinToEdges(row, of: self)

            self.textField.target = self
            self.textField.action = #selector(textFieldChanged(_:))
            // Subclasses substitute their own field (`SecureTextEditView` returns
            // an `NSSecureTextField`), so the theme is attached here rather than
            // by returning a `ThemedTextField` from the factory.
            self.textField.observeTheme { field, palette in
                field.font = palette.font(.body)
                field.textColor = palette.primaryTextColor
                if let placeholder = field.placeholderString {
                    field.placeholderAttributedString = NSAttributedString(
                        string: placeholder,
                        attributes: [
                            .foregroundColor: palette.placeholderTextColor,
                            .font: palette.font(.body)
                        ]
                    )
                }
            }

            viewModel.onChange = { [weak self] _ in
                guard let self else { return }
                self.label.stringValue = viewModel.title
                self.textField.stringValue = viewModel.value
            }
        }

        @objc private func textFieldChanged(_ sender: NSTextField) {
            let newValue = sender.stringValue
            if viewModel.settingObserver.value != newValue {
                viewModel.settingObserver.value = newValue
            }
        }

        public override init(frame frameRect: NSRect) {
            fatalError("init(frame frameRect: NSRect")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        static func createLabel(title: String) -> NSTextField {
            ComposableSettings.makeRowLabel(title)
        }

        /// Override to substitute a different `NSTextField` subclass — e.g.
        /// `SecureTextEditView` returns an `NSSecureTextField`.
        open class func makeTextField(initialValue: String) -> NSTextField {
            NSTextField(string: initialValue)
        }
    }
}

extension ComposableSettings.TextEditView: ComposableSettings.ExplainedSettingsView {}
