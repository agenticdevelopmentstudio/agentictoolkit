import AppKit
import OSLog
import KeyboardShortcuts
import AgenticToolkitCore

/// Owns the command palette: the global shortcut that opens it, the panel it
/// opens, and the command and menu item that name it.
///
/// The palette is the one feature whose subject is the other features, so it
/// takes the same `CommandRegistry` they were handed and reads it — there is no
/// singleton here and must not be one, or a second app embedding this framework
/// would inherit this app's commands.
@MainActor
public final class CommandPaletteCoordinator: AppFeature {

    // MARK: - Public API

    /// The ids this feature's actions answer to.
    ///
    /// `workbench.action.showCommands` is VS Code's own id, kept verbatim: a
    /// JavaScript extension calling `vscode.commands.executeCommand` with it,
    /// or a `contributes.menus` entry naming it, must land here without a
    /// translation table (`principle-of-least-astonishment`).
    public enum CommandID {
        public static let showCommands = "workbench.action.showCommands"
    }

    // MARK: - Dependencies

    private let registry: CommandRegistry

    /// Built on first `showPalette()`, not in `init`. A menu-bar app launches
    /// on every login and most launches never open the palette, so its panel,
    /// table and search field are work worth not doing until they are asked
    /// for. Retained afterwards: reopening reuses the one panel.
    private var windowController: CommandPaletteWindowController?

    // MARK: - Lifecycle

    /// - Parameter commandRegistry: The registry to list and to dispatch
    ///   through — the same instance every other coordinator registered into.
    public init(commandRegistry registry: CommandRegistry) {
        self.registry = registry
        super.init()

        registry.register(AppCommand(
            id: CommandID.showCommands,
            title: "Show All Commands",
            category: "View",
            run: { [weak self] in self?.showPalette() }
        ))

        self.menuContributions = [
            MenuContribution(
                slot: .view, title: "Command Palette…",
                commandID: CommandID.showCommands, registry: registry,
                order: 0, key: "p", modifiers: [.command, .shift]
            )
        ]
        // ⇧⌘P is safe as a menu key equivalent where it could not be as the
        // global shortcut below: a key equivalent only fires while this app is
        // frontmost, so VS Code's own binding is not taken away from anything.
    }

    // MARK: - AppFeature

    /// Claim the system-global shortcut.
    ///
    /// Here and not in `init` because `KeyboardShortcuts.onKeyDown` registers a
    /// real, machine-wide Carbon hotkey: constructing a coordinator must not
    /// take ⌃⌥C away from every other app, which is exactly what a test bundle
    /// that builds one would otherwise do for the length of its run. `start()`
    /// is the lifecycle hook for a long-running service, and the host calls it
    /// once per launch on every registered feature.
    public override func start() {
        KeyboardShortcuts.onKeyDown(for: .showCommandPalette) { [weak self] in
            self?.showPalette()
        }
    }

    /// Give the shortcut back. `removeHandler` drops the stored handler *and*
    /// unregisters the Carbon hotkey, which is what makes `start()` reversible.
    public override func stop() {
        KeyboardShortcuts.removeHandler(for: .showCommandPalette)
    }

    /// Whether the global shortcut is claimed right now.
    ///
    /// Internal, and the tests are the reason: the property worth asserting
    /// about this feature is that *constructing* it claims no machine-wide
    /// hotkey, and there is no other way to see that from outside.
    var isGlobalShortcutInstalled: Bool {
        KeyboardShortcuts.isEnabled(for: .showCommandPalette)
    }

    // MARK: - Showing

    /// Bring the palette up, building it the first time.
    ///
    /// Idempotent: a second call while it is open re-positions and re-focuses
    /// the same panel rather than stacking another.
    public func showPalette() {
        let controller = windowController ?? makeWindowController()
        windowController = controller
        controller.show()
    }

    private func makeWindowController() -> CommandPaletteWindowController {
        logger.debug("Building the command palette panel")
        return CommandPaletteWindowController(model: CommandPaletteModel(registry: registry))
    }
}

extension CommandPaletteCoordinator: Loggable {
    public static nonisolated let logger = makeLogger()
}

/// The user-rebindable shortcut that opens the palette.
///
/// The default is ⌃⌥C rather than VS Code's ⇧⌘P because `KeyboardShortcuts`
/// installs a *system-global* hotkey: ⇧⌘P taken globally would be stolen from
/// every other app on the machine, VS Code included. ⌃⌥ is this toolkit's
/// established global family (see `SystemWindowShortcutNames`) and `.c` is the
/// one letter in reach that family has not already spent.
extension KeyboardShortcuts.Name {

    /// The raw value is a persisted `UserDefaults` key holding the user's own
    /// rebinding — renaming it silently discards their customisation.
    public static let showCommandPalette = Self(
        "showCommandPalette",
        default: .init(.c, modifiers: [.control, .option]))
}
