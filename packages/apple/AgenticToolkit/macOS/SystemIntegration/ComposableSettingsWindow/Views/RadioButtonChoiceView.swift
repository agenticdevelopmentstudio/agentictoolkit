import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    @MainActor
    public class RadioButtonChoiceView<Value: Codable & Sendable & Equatable>: NSView, SettingsViewProtocol {
        public let label: NSTextField
        public private(set) var radioButtons: [NSButton] = []

        private let viewModel: ChoiceViewModel<Value>

        /// The view model's ``AbstractViewModel/explanation``, which the
        /// ``GroupView`` this is placed in draws under the row.
        public var settingExplanation: String? { viewModel.explanation }

        private var buttonValues: [(button: NSButton, value: Value)] = []

        public init(
            viewModel: ChoiceViewModel<Value>,
            axis: NSUserInterfaceLayoutOrientation = .vertical
        ) {
            self.viewModel = viewModel
            self.label = Self.createLabel(title: viewModel.title)

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            for choice in viewModel.choices {
                let button = NSButton(
                    radioButtonWithTitle: choice.label,
                    target: self,
                    action: #selector(radioChanged(_:))
                )
                self.radioButtons.append(button)
                self.buttonValues.append((button, choice.value))
            }

            let controlsStack = NSStackView(views: self.radioButtons)
            controlsStack.orientation = axis
            controlsStack.spacing = SettingsLayout.default[.rowSpacing]
            controlsStack.alignment = (axis == .vertical) ? .leading : .firstBaseline
            controlsStack.translatesAutoresizingMaskIntoConstraints = false

            let outer = NSStackView(views: [self.label, controlsStack])
            outer.orientation = .vertical
            outer.spacing = SettingsLayout.default[.rowSpacing]
            outer.alignment = .leading
            outer.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(outer)
            Self.pinToEdges(outer, of: self)

            viewModel.onChange = { [weak self] _ in
                self?.syncSelection()
            }

            self.syncSelection()
        }

        private func syncSelection() {
            self.label.stringValue = viewModel.title
            let current = viewModel.value
            for (button, value) in self.buttonValues {
                button.state = (value == current) ? .on : .off
            }
        }

        @objc private func radioChanged(_ sender: NSButton) {
            guard let entry = self.buttonValues.first(where: { $0.button === sender }) else { return }
            if viewModel.settingObserver.value != entry.value {
                viewModel.settingObserver.value = entry.value
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
    }
}

extension ComposableSettings.RadioButtonChoiceView: ComposableSettings.ExplainedSettingsView {}
