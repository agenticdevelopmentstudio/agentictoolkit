import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    @MainActor
    public class ColorPickerView: NSView, SettingsViewProtocol {
        public let label: NSTextField
        public let colorWell: NSColorWell

        private let viewModel: ColorViewModel

        /// The view model's ``AbstractViewModel/explanation``, which the
        /// ``GroupView`` this is placed in draws under the row.
        public var settingExplanation: String? { viewModel.explanation }

        public init(viewModel: ColorViewModel) {
            self.viewModel = viewModel
            self.label = Self.createLabel(title: viewModel.title)
            self.colorWell = NSColorWell()
            self.colorWell.color = viewModel.color

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            let row = Self.makeRow([self.label, self.colorWell])
            self.addSubview(row)
            Self.pinToEdges(row, of: self)

            self.colorWell.target = self
            self.colorWell.action = #selector(colorChanged(_:))

            viewModel.onChange = { [weak self] _ in
                guard let self else { return }
                self.label.stringValue = viewModel.title
                self.colorWell.color = viewModel.color
            }
        }

        @objc private func colorChanged(_ sender: NSColorWell) {
            viewModel.color = sender.color
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

extension ComposableSettings.ColorPickerView: ComposableSettings.ExplainedSettingsView {}
