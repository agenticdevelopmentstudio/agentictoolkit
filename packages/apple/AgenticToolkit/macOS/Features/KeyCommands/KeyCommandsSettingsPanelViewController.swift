import AppKit
import AgenticToolkitCore

/// The shared Key Commands panel: every command any part of the app declared,
/// grouped by the section that declared it, each rebindable in place.
///
/// The panel knows nothing about what the commands *do* — it reads
/// ``KeyCommandRegistry``, so an app that declares three commands and one that
/// declares thirty get the same panel without either of them writing a view.
/// That is what lets this live in the shared framework while the command list
/// stays the property of whoever can actually perform the commands.
@MainActor
public final class KeyCommandsSettingsPanelViewController: ComposableSettings.SettingsPanelViewController {

    private let registry: KeyCommandRegistry

    public init(registry: KeyCommandRegistry = .shared) {
        self.registry = registry
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: "Key Commands",
            icon: NSImage(systemSymbolName: "command", accessibilityDescription: nil)
        ))
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The rows carry the command titles, but none of them contain the words a
    /// user actually searches the sidebar with.
    public override var searchKeywords: [String] {
        ["key", "keys", "command", "commands", "shortcut", "shortcuts", "hotkey", "keyboard", "binding"]
    }

    public override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "Recording a key command",
                body: "Click the field beside a command and press the keys you want. "
                    + "Underneath, the combination reads available or unavailable — "
                    + "unavailable names what already has it, which is either another "
                    + "command in this list or a menu item. Click the checkmark to save "
                    + "it, or the ✗ (or Escape) to leave the command as it was. A "
                    + "combination needs at least one of ⌘, ⌃ or ⌥, so it can never "
                    + "swallow ordinary typing."
            ),
            .init(
                title: "Switching a command off",
                body: "The switch beside a command turns it off without forgetting what "
                    + "it was bound to, so turning it back on gives you your combination "
                    + "back. A command with no combination recorded has nothing to "
                    + "switch on, which is why its switch is dimmed."
            ),
            .init(
                title: "App and system-wide commands",
                body: "An app command works while this app is frontmost. A system-wide "
                    + "command works whatever you are doing — which also means it is "
                    + "taken away from whatever app you are in at the time. That is why "
                    + "the system-wide ones ship switched off: turn on the ones you want "
                    + "and leave the rest alone."
            )
        ])
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        guard !registry.sections.isEmpty else {
            settingsView.addGroup(makeEmptyGroup())
            return
        }

        for section in registry.sections {
            settingsView.addGroup(makeGroup(for: section))
        }
    }

    private func makeGroup(for section: KeyCommandSection) -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: section.title)

        if let caption = section.caption {
            group.addSettingSubview(ComposableSettings.ExplanationView(withText: caption))
        }

        for command in section.commands {
            group.addSettingSubview(KeyCommandRowView(command: command, registry: registry))
        }

        return group
    }

    /// A consuming app that declared no commands should be told that, rather
    /// than shown a panel that looks like it failed to load.
    private func makeEmptyGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Key Commands")
        group.addSettingSubview(ComposableSettings.ExplanationView(
            withText: "This app has not declared any bindable key commands."))
        return group
    }
}
