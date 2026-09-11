import Foundation
import OSLog
import AgenticToolkitCore

/// One named, dispatchable action — the thing a menu item, a command palette
/// row, a keyboard shortcut or (later) an extension all address by the *same*
/// string instead of each holding its own copy of the closure.
///
/// Deliberately **not** `AgenticDeveloperToolkit.Command`. That protocol is the
/// AI-chat / tool-invocation domain: it requires `argumentSchema`, `permission`
/// and `allowedInvokers`, none of which a File → New menu entry has an answer
/// for. Different actor, different reason to change (`single-responsibility`).
/// The name `AppCommand` also keeps `Command` — which
/// `AgenticToolkitCore` re-exports into this module — unambiguous.
public struct AppCommand {

    /// The stable identifier the command is addressed by. Convention here is
    /// VS Code's `<namespace>.action.<verbNoun>` (`terminal.action.newWindow`),
    /// because `contributes.menus` and `vscode.commands.executeCommand` speak
    /// exactly that shape. Ids are load-bearing and expensive to rename.
    public let id: String

    /// Human-readable, and what a command palette shows as the row's label.
    public let title: String

    /// The palette's grouping — VS Code's `contributes.commands.category`.
    /// Empty means ungrouped, which is a real answer rather than a missing one,
    /// so this is a `String` and not `String?`.
    public let category: String

    /// Whether running the command means anything right now. Default
    /// always-enabled, matching `MenuContribution.isEnabled`.
    public let isEnabled: () -> Bool

    /// What the command does.
    public let run: () -> Void

    public init(
        id: String,
        title: String,
        category: String = "",
        isEnabled: @escaping () -> Bool = { true },
        run: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.isEnabled = isEnabled
        self.run = run
    }
}

/// Why `CommandRegistry.execute(id:)` refused to run something.
///
/// A thrown error rather than a `Bool` return: a discarded `Bool` is a silent
/// no-op the compiler will not complain about, and "nothing happened" is the
/// exact failure this registry must never produce quietly (`fail-fast`).
public enum CommandRegistryError: Error, Equatable, CustomStringConvertible {

    /// No command is registered under this id — a typo, a stale
    /// `contributes.menus` entry, or an extension that failed to load.
    case unknownCommand(id: String)

    /// The command exists but its own `isEnabled` says running it now is
    /// meaningless (Delete Note with no notes view in front of the user).
    case commandDisabled(id: String)

    public var description: String {
        switch self {
        case .unknownCommand(let id):
            return "No command is registered with id '\(id)'"
        case .commandDisabled(let id):
            return "Command '\(id)' is registered but currently disabled"
        }
    }
}

/// The one place that knows how to turn a command id into work.
///
/// An **instance**, not a singleton, and not a namespace of statics: the demo
/// app, a real app and a test all need their own command set in the same
/// process, and with global registration the last registrant wins
/// (`dependency-injection`). The precedent is `ComposableTabsViewRegistry`, not
/// `AppFeatureRegistry.shared` in this same file's neighbour — a registry that
/// Stage 5 will reload extension commands into must be replaceable wholesale in
/// a test, which a process-wide singleton is not.
///
/// `@MainActor` because everything it dispatches is UI work and every consumer
/// — `MenuContribution`, `ClosureMenuItemTarget`, the command palette — is
/// already main-actor-isolated.
@MainActor
public final class CommandRegistry {

    private var commandsByID: [String: AppCommand] = [:]

    /// Registration order, so `allCommands` is stable. A `Dictionary`'s value
    /// order is seeded per process, and a command palette whose rows reshuffle
    /// between launches is a bug the user sees (the same trap
    /// `AppFeatureRegistry.orderedFeatures` exists to avoid).
    private var registrationOrder: [String] = []

    public init() {}

    /// Register `command`, or replace the one already filed under its id.
    ///
    /// **Duplicate ids replace, in place, and log a warning.** The three
    /// candidate behaviours were replace, ignore and trap:
    ///
    /// - *Trap* is wrong because Stage 5 registers commands from extensions
    ///   that can be reloaded, and a reload re-registers every id it owns.
    ///   Crashing the app when a developer saves an extension is not a
    ///   defensible failure mode.
    /// - *Ignore* is wrong for the same reload: the reloaded extension's fixed
    ///   command would never take effect, and nothing would say why. That is
    ///   the silent-wrong-behaviour this type exists to avoid.
    /// - *Replace* is what reload needs, and it matches the precedent one file
    ///   over — `AppFeatureRegistry.register(_:)` replaces a same-named feature
    ///   in place, keeping its original position.
    ///
    /// Replacement's own risk is that two unrelated features colliding on an id
    /// silently lose one of them, so the collision is logged at `warning`:
    /// visible to whoever is looking, without breaking reload for whoever is
    /// not.
    public func register(_ command: AppCommand) {
        if commandsByID[command.id] != nil {
            Self.logger.warning(
                "Command id already registered, replacing: \(command.id, privacy: .public)"
            )
        } else {
            registrationOrder.append(command.id)
        }
        commandsByID[command.id] = command
    }

    /// Take back the command registered under `id`.
    ///
    /// The counterpart `register(_:)` needed from the moment commands stopped
    /// being process-lifetime app features and started being per-object: a
    /// branch controller registers three commands namespaced by its checkout,
    /// and when that checkout goes away — `git worktree remove`, or the whole
    /// project window closing — the commands must go with it. Left behind they
    /// are worse than clutter: they act on a directory that no longer exists,
    /// under a palette row the user has every reason to trust.
    ///
    /// An unknown id is a no-op rather than an error. Teardown is exactly where
    /// "was this ever registered?" is least worth tracking, and making the
    /// caller answer it would only invite it to guess (`idempotency`).
    ///
    /// Both structures are cleaned. Removing from `commandsByID` alone already
    /// fixes `allCommands`, `command(id:)`, `isEnabled(id:)` and `execute(id:)`
    /// — but it leaves the id in `registrationOrder`, where it makes the next
    /// `register` of that id look new, append a second entry, and list one
    /// command twice.
    public func unregister(id: String) {
        guard commandsByID.removeValue(forKey: id) != nil else { return }
        registrationOrder.removeAll { $0 == id }
    }

    /// Every registered command, in registration order — what a command palette
    /// lists.
    public var allCommands: [AppCommand] {
        registrationOrder.compactMap { commandsByID[$0] }
    }

    /// The command registered under `id`, or `nil`.
    public func command(id: String) -> AppCommand? {
        commandsByID[id]
    }

    /// Whether `id` names a command that is registered *and* says it applies
    /// right now. An unregistered id answers `false` rather than `true`: a menu
    /// item pointing at a command nobody registered must not look available.
    public func isEnabled(id: String) -> Bool {
        commandsByID[id]?.isEnabled() ?? false
    }

    /// Run the command registered under `id`.
    ///
    /// - Throws: `CommandRegistryError.unknownCommand` when nothing is
    ///   registered under `id`, and `CommandRegistryError.commandDisabled` when
    ///   the command's own `isEnabled` returns `false`. Both are programmer- or
    ///   configuration-level mistakes that must be seen, not swallowed
    ///   (`fail-fast`).
    ///
    /// There is no `arguments:` parameter, deliberately: `AppCommand.run` takes
    /// none, so an `arguments` parameter would have nowhere to deliver them and
    /// would silently discard whatever a caller passed. Stage 5's
    /// `executeCommand` shim adds an overload beside this one, additively, once
    /// the argument type is decided by a caller that actually has arguments.
    public func execute(id: String) throws {
        guard let command = commandsByID[id] else {
            throw CommandRegistryError.unknownCommand(id: id)
        }
        guard command.isEnabled() else {
            throw CommandRegistryError.commandDisabled(id: id)
        }
        command.run()
    }
}

extension CommandRegistry: Loggable {
    public static nonisolated let logger = makeLogger()
}
