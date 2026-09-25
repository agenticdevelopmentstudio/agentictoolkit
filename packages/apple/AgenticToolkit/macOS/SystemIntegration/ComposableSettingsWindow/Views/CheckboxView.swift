import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    /// A boolean setting, drawn as System Settings draws one: the label leads
    /// the row and an `NSSwitch` trails it.
    ///
    /// The switch replaced a checkbox-with-title button. A checkbox puts its
    /// control on the *left*, which is the one row shape that cannot line up
    /// with the popups, steppers and sliders beside it in the same card — and
    /// left every group looking like two different lists interleaved.
    @MainActor
    public class CheckboxView: NSView, SettingsViewProtocol {
        public let label: NSTextField
        /// The switch itself. Not `checkbox`: this has not been a checkbox
        /// since the row was restyled, and a name that lies about a control's
        /// class is the kind that gets `state = .on` written against the
        /// wrong API.
        public let toggle: NSSwitch

        private let viewModel: ViewModel<Bool>

        /// The view model's ``AbstractViewModel/explanation``, which the
        /// ``GroupView`` this is placed in draws under the row.
        public var settingExplanation: String? { viewModel.explanation }

        public init(with viewModel: ViewModel<Bool>) {
            self.viewModel = viewModel
            self.label = Self.createLabel(title: viewModel.title)
            self.toggle = NSSwitch()

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            let row = Self.makeRow([self.label, self.toggle])
            self.addSubview(row)
            Self.pinToEdges(row, of: self)

            self.toggle.target = self
            self.toggle.action = #selector(toggleChanged(_:))
            // AppKit gives a bare switch no name, so VoiceOver would announce it
            // as an unlabelled control; the visible label is its title element.
            self.toggle.setAccessibilityTitleUIElement(self.label)

            viewModel.onChange = { [weak self] _ in
                self?.update()
            }

            self.update()
        }

        @objc private func toggleChanged(_ sender: NSSwitch) {
            let newValue = (sender.state == .on)
            if viewModel.settingObserver.value != newValue {
                viewModel.settingObserver.value = newValue
            }
        }

        private func update() {
            self.label.stringValue = viewModel.title
            self.toggle.state = viewModel.value ? .on : .off
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

extension ComposableSettings.CheckboxView: ComposableSettings.ExplainedSettingsView {}
