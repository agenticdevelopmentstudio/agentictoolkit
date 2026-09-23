import KeyboardShortcuts
import OSLog
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// Registers global keyboard-shortcut handlers for the window-context actions
/// and dispatches them to a ``SystemWindowContextsModel``.
///
/// Instantiate once at app launch and retain it for the app's lifetime. The
/// `KeyboardShortcuts` library installs the global event tap and persists user
/// customizations in `UserDefaults`. The default scheme uses Control+Option:
/// `^⌥1`–`^⌥9` switch by index, `^⌥A` / `^⌥X` add/remove the frontmost window,
/// `^⌥N` / `^⌥P` cycle contexts, and `^⌥Space` toggles the picker.
@MainActor
public final class SystemWindowShortcutManager {

    private let model: SystemWindowContextsModel

    public init(model: SystemWindowContextsModel) {
        self.model = model
        registerAllHandlers()
        logger.info("SystemWindowShortcutManager initialized, all handlers registered")
    }

    /// Registers key-down handlers for every window-context shortcut.
    ///
    /// The `KeyboardShortcuts` library manages the global event tap under the
    /// hood; this only needs to run once at startup.
    private func registerAllHandlers() {
        for (index, name) in KeyboardShortcuts.Name.contextSwitchByIndex.enumerated() {
            let capturedIndex = index
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                self?.switchToContext(at: capturedIndex)
            }
        }

        KeyboardShortcuts.onKeyDown(for: .addWindow) { [weak self] in
            self?.model.addFrontmostWindow()
        }

        KeyboardShortcuts.onKeyDown(for: .removeWindow) { [weak self] in
            self?.model.removeFrontmostWindow()
        }

        KeyboardShortcuts.onKeyDown(for: .nextContext) { [weak self] in
            self?.model.switchToNextContext()
        }

        KeyboardShortcuts.onKeyDown(for: .previousContext) { [weak self] in
            self?.model.switchToPreviousContext()
        }

        KeyboardShortcuts.onKeyDown(for: .contextPicker) { [weak self] in
            self?.model.toggleContextPicker()
        }

        // So Settings › Key Commands refuses these chords instead of letting a
        // second command fire on them too.
        KeyCommandRegistry.shared.reserveExternal(
            KeyboardShortcuts.Name.allWindowContextShortcuts, owner: "window contexts")
    }

    /// Switches to the context at the given zero-based index.
    ///
    /// Out-of-range indices (fewer contexts exist) are a no-op.
    private func switchToContext(at index: Int) {
        let contexts = model.contexts
        guard index < contexts.count else { return }
        model.switchContext(to: contexts[index].id)
    }
}

extension SystemWindowShortcutManager: Loggable {
    public static nonisolated let logger = makeLogger()
}
