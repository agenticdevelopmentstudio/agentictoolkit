import AppKit
import KeyboardShortcuts

/// The Conversations window's bindable key commands.
///
/// Declared by the window rather than by the settings panel, because the panel
/// is shared and knows nothing about conversations, and because only the window
/// can actually perform these.
///
/// The controller is resolved **when the command runs**, not when the section is
/// installed, so the host can declare these at launch — before any Conversations
/// window exists, and whether or not one is ever opened. Binding them to a live
/// instance instead would mean the Settings panel listed them only for someone
/// who had already opened that window, which is the wrong way round: the panel
/// is where you go to find out what the app *can* do.
@MainActor
public enum ConversationsKeyCommands {

    public static let moveSelectionUpID = "conversations.moveSelectionUp"
    public static let moveSelectionDownID = "conversations.moveSelectionDown"
    public static let toggleShelfID = "conversations.toggleShelf"

    public static let sectionTitle = "App"

    /// The section. `resolve` answers with the live split controller, or `nil`
    /// when the window is not up — in which case the commands do nothing, which
    /// is what they should do.
    public static func section(
        resolve: @escaping @MainActor () -> ConversationsSplitViewController?
    ) -> KeyCommandSection {
        KeyCommandSection(
            title: sectionTitle,
            caption: "These work while this app is frontmost.",
            commands: [
                KeyCommandDescriptor(
                    id: moveSelectionUpID,
                    title: "Previous Conversation",
                    scope: .app,
                    defaultShortcut: KeyboardShortcuts.Shortcut(.upArrow, modifiers: .command),
                    run: { resolve()?.moveSelection(by: -1) }
                ),
                KeyCommandDescriptor(
                    id: moveSelectionDownID,
                    title: "Next Conversation",
                    scope: .app,
                    defaultShortcut: KeyboardShortcuts.Shortcut(.downArrow, modifiers: .command),
                    run: { resolve()?.moveSelection(by: 1) }
                ),
                KeyCommandDescriptor(
                    id: toggleShelfID,
                    title: "Show Conversation List",
                    scope: .app,
                    defaultShortcut: KeyboardShortcuts.Shortcut(.zero, modifiers: .command),
                    run: { resolve()?.toggleShelf() }
                )
            ])
    }
}
