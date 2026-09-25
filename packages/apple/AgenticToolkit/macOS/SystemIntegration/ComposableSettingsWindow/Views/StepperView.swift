import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    /// Integer stepper bound to a `RangeViewModel<Int>`. Use for small
    /// bounded counts (recents, retry limits, etc.) where a slider's
    /// resolution is wrong but a free text field is too unbounded.
    @MainActor
    public class StepperView: NSView, SettingsViewProtocol {
        public let label: NSTextField
        public let stepper: NSStepper
        public let valueLabel: NSTextField

        private let viewModel: RangeViewModel<Int>

        /// The view model's ``AbstractViewModel/explanation``, which the
        /// ``GroupView`` this is placed in draws under the row.
        public var settingExplanation: String? { viewModel.explanation }

        public init(viewModel: RangeViewModel<Int>) {
            self.viewModel = viewModel
            self.label = Self.createLabel(title: viewModel.title)
            self.stepper = NSStepper()
            self.valueLabel = Self.createValueLabel()

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            self.stepper.minValue = Double(viewModel.minValue)
            self.stepper.maxValue = Double(viewModel.maxValue)
            self.stepper.increment = 1
            self.stepper.valueWraps = false
            self.stepper.integerValue = viewModel.value
            self.stepper.target = self
            self.stepper.action = #selector(stepperChanged(_:))

            self.valueLabel.stringValue = "\(viewModel.value)"

            let row = Self.makeRow([self.label, self.valueLabel, self.stepper])
            self.addSubview(row)
            Self.pinToEdges(row, of: self)

            viewModel.onChange = { [weak self] _ in self?.sync() }
            self.sync()
        }

        private func sync() {
            self.label.stringValue = viewModel.title
            self.stepper.minValue = Double(viewModel.minValue)
            self.stepper.maxValue = Double(viewModel.maxValue)
            self.stepper.integerValue = viewModel.value
            self.valueLabel.stringValue = "\(viewModel.value)"
        }

        @objc private func stepperChanged(_ sender: NSStepper) {
            let newValue = sender.integerValue
            self.valueLabel.stringValue = "\(newValue)"
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

        static func createValueLabel() -> NSTextField {
            let label = ComposableSettings.makeValueLabel(monospacedDigits: true)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            return label
        }
    }
}

extension ComposableSettings.StepperView: ComposableSettings.ExplainedSettingsView {}
