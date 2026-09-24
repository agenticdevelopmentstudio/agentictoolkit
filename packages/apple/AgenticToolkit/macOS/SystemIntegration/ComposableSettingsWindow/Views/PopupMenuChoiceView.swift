import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    @MainActor
    public class PopupMenuChoiceView<Value: Codable & Sendable & Equatable>: NSView, SettingsViewProtocol {
        public let label: NSTextField
        public let popUpButton: NSPopUpButton

        private let viewModel: ChoiceViewModel<Value>

        public init(viewModel: ChoiceViewModel<Value>) {
            self.viewModel = viewModel
            self.label = Self.createLabel(title: viewModel.title)
            self.popUpButton = NSPopUpButton(frame: .zero)
            Self.populate(self.popUpButton, with: viewModel.choices)

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            // System Settings draws a popup inside a card without a bezel: the
            // current value in secondary text with the chevron pair after it.
            // The card is the surface, so a second one around the control just
            // boxes a box.
            self.popUpButton.isBordered = false
            self.popUpButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)

            let row = Self.makeRow([self.label, self.popUpButton])
            self.addSubview(row)
            Self.pinToEdges(row, of: self)

            self.popUpButton.target = self
            self.popUpButton.action = #selector(popupChanged(_:))

            // The visible title label sits beside the popup but AppKit doesn't
            // associate them, so VoiceOver would announce the popup with no name.
            // Tie the label to the control as its accessibility title element.
            self.popUpButton.setAccessibilityTitleUIElement(self.label)

            viewModel.onChange = { [weak self] _ in
                self?.syncSelection()
            }
            viewModel.onChoicesChange = { [weak self] in
                guard let self else { return }
                Self.populate(self.popUpButton, with: self.viewModel.choices)
                self.syncSelection()
            }

            self.syncSelection()
        }

        private func syncSelection() {
            self.label.stringValue = viewModel.title
            let current = viewModel.value
            if let index = viewModel.choices.firstIndex(where: { $0.value == current }) {
                self.popUpButton.selectItem(at: index)
            } else {
                self.popUpButton.selectItem(at: -1)
            }
        }

        private static func populate(_ button: NSPopUpButton, with choices: [ChoiceViewModel<Value>.Choice]) {
            button.removeAllItems()
            for choice in choices {
                button.addItem(withTitle: choice.label)
                button.lastItem?.representedObject = choice.value
                if let symbol = choice.imageSystemName {
                    button.lastItem?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                }
            }
        }

        @objc private func popupChanged(_ sender: NSPopUpButton) {
            guard let value = sender.selectedItem?.representedObject as? Value else { return }
            if viewModel.settingObserver.value != value {
                viewModel.settingObserver.value = value
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
