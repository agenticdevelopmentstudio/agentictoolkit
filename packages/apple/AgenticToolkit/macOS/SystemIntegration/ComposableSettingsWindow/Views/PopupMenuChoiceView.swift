import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    @MainActor
    public class PopupMenuChoiceView<Value: Codable & Sendable & Equatable>: NSView, SettingsViewProtocol {
        public let label: NSTextField
        public let popUpButton: NSPopUpButton

        private let viewModel: ChoiceViewModel<Value>

        /// The view model's ``AbstractViewModel/explanation``, which the
        /// ``GroupView`` this is placed in draws under the row.
        public var settingExplanation: String? { viewModel.explanation }

        /// Greys out the whole row — the popup and its title — the way
        /// `FontPickerView.isEnabled` does. Disabling only `popUpButton`
        /// leaves the title at full strength beside a dead control.
        public var isEnabled: Bool = true {
            didSet {
                popUpButton.isEnabled = isEnabled
                label.alphaValue = isEnabled ? 1 : 0.4
            }
        }

        public init(viewModel: ChoiceViewModel<Value>) {
            self.viewModel = viewModel
            self.label = Self.createLabel(title: viewModel.title)
            self.popUpButton = NSPopUpButton(frame: .zero)
            Self.populate(self.popUpButton, with: viewModel.choices, commands: viewModel.commands)

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
            viewModel.refreshHandler = { [weak self] _ in
                self?.syncSelection()
            }
            viewModel.onChoicesChange = { [weak self] in
                guard let self else { return }
                Self.populate(self.popUpButton, with: self.viewModel.choices, commands: self.viewModel.commands)
                self.syncSelection()
            }

            self.syncSelection()
        }

        /// Selects the item that *carries* the current value, found through its
        /// `representedObject` — never by position in `choices`, which is only
        /// the same as the item's position while every item made it in.
        private func syncSelection() {
            self.label.stringValue = viewModel.title
            let current = viewModel.value
            if let item = popUpButton.itemArray.first(where: { ($0.representedObject as? Value) == current }) {
                self.popUpButton.select(item)
            } else {
                self.popUpButton.selectItem(at: -1)
            }
        }

        /// One menu item per choice, built directly. `addItem(withTitle:)`
        /// silently drops an earlier item with the same title, and two records
        /// can share a name — two projects both called "Acme" are two choices.
        private static func populate(
            _ button: NSPopUpButton,
            with choices: [ChoiceViewModel<Value>.Choice],
            commands: [ChoiceViewModel<Value>.Command]
        ) {
            button.removeAllItems()
            guard let menu = button.menu else { return }
            for choice in choices {
                let item = NSMenuItem(title: choice.label, action: nil, keyEquivalent: "")
                item.representedObject = choice.value
                if let symbol = choice.imageSystemName {
                    item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                }
                menu.addItem(item)
            }
            if !commands.isEmpty, !choices.isEmpty { menu.addItem(.separator()) }
            for (index, command) in commands.enumerated() {
                let item = NSMenuItem(title: command.title, action: nil, keyEquivalent: "")
                // A marker no `Value` can be, so a command never reads as a choice.
                item.representedObject = CommandMarker(index: index)
                menu.addItem(item)
            }
        }

        /// What a command's menu item carries instead of a value.
        private final class CommandMarker: NSObject {
            let index: Int
            init(index: Int) { self.index = index }
        }

        /// The command menu items, in order — so a test can pick one.
        public var commandItems: [NSMenuItem] {
            popUpButton.itemArray.filter { $0.representedObject is CommandMarker }
        }

        @objc private func popupChanged(_ sender: NSPopUpButton) {
            if let marker = sender.selectedItem?.representedObject as? CommandMarker {
                // The popup now shows the command's title; put the value back
                // before the action runs, since the action may open a window.
                syncSelection()
                let commands = viewModel.commands
                if commands.indices.contains(marker.index) { commands[marker.index].action() }
                return
            }
            guard let value = sender.selectedItem?.representedObject as? Value else { return }
            if viewModel.settingObserver.value != value {
                viewModel.settingObserver.value = value
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        static func createLabel(title: String) -> NSTextField {
            ComposableSettings.makeRowLabel(title)
        }
    }
}

extension ComposableSettings.PopupMenuChoiceView: ComposableSettings.ExplainedSettingsView {}
