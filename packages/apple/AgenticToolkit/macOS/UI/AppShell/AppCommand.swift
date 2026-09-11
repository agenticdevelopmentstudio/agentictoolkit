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

    /// What the command does, given whatever arguments the caller passed and
    /// answering with whatever the command wants to hand back.
    ///
    /// `([Any]) -> Any?`, not `() -> Void`: a menu item or a keyboard shortcut
    /// never has arguments and never wants a return value, but
    /// `vscode.commands.executeCommand(id, ...args)` both delivers them and
    /// resolves with whatever comes back, and a `() -> Void` stored here would
    /// discard both silently — the exact quiet failure `CommandRegistryError`
    /// exists to prevent one layer up. Every existing caller still writes
    /// `run: { ... }` with no arguments and no return; see the initializer
    /// below for how that stays true.
    public let run: ([Any]) -> Any?

    /// The menu-item / keyboard-shortcut / palette-row shape: a command that
    /// takes nothing and answers nothing. Kept byte-for-byte — same
    /// parameters, same defaults — so every existing call site compiles
    /// unchanged; `run` is wrapped as `{ _ in run(); return nil }`, discarding
    /// the arguments a caller of this initializer never had a way to supply
    /// in the first place and answering `nil`, which is the correct "nothing
    /// to resolve with" for a command nothing ever awaits.
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
        self.run = { _ in
            run()
            return nil
        }
    }

    /// The `vscode.commands.executeCommand` shape: a command that receives
    /// whatever arguments the caller passed and can answer with a value the
    /// caller resolves its `Thenable` with. Additive beside the initializer
    /// above rather than a replacement for it — every existing call site
    /// wants `() -> Void` and gains nothing from typing `_ in` and `return
    /// nil` at every one of them for a distinction only `MainThreadCommands`
    /// needs.
    public init(
        id: String,
        title: String,
        category: String = "",
        isEnabled: @escaping () -> Bool = { true },
        run: @escaping ([Any]) -> Any?
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

    /// Run the command registered under `id`, with no arguments.
    ///
    /// - Throws: `CommandRegistryError.unknownCommand` when nothing is
    ///   registered under `id`, and `CommandRegistryError.commandDisabled` when
    ///   the command's own `isEnabled` returns `false`. Both are programmer- or
    ///   configuration-level mistakes that must be seen, not swallowed
    ///   (`fail-fast`).
    ///
    /// A thin call-through to `execute(id:arguments:)` rather than a second
    /// copy of the two guards above: every menu item and keyboard shortcut in
    /// the app calls this exact signature, and duplicating the checks here
    /// would be a second place for them to drift apart.
    public func execute(id: String) throws {
        _ = try execute(id: id, arguments: [])
    }

    /// Run the command registered under `id`, delivering `arguments` and
    /// answering with whatever it returns.
    ///
    /// This is the `vscode.commands.executeCommand(id, ...args)` shape
    /// `execute(id:)`'s own doc comment used to promise: `MainThreadCommands`
    /// is the caller that actually has arguments to deliver and a `Thenable`
    /// to resolve with. `@discardableResult` because the app's own menu items
    /// and shortcuts — which route through `execute(id:)` above — never want
    /// the value back, and only an extension's `executeCommand` does.
    ///
    /// - Throws: the same two cases as `execute(id:)`, for the same reason.
    @discardableResult
    public func execute(id: String, arguments: [Any]) throws -> Any? {
        guard let command = commandsByID[id] else {
            throw CommandRegistryError.unknownCommand(id: id)
        }
        guard command.isEnabled() else {
            throw CommandRegistryError.commandDisabled(id: id)
        }
        return command.run(arguments)
    }

    /// Removes `id` and its entry in `registrationOrder`, so a torn-down
    /// extension's commands stop appearing in the palette rather than sitting
    /// there pointing at whatever the id used to mean.
    ///
    /// Additive beside `register`'s replace-and-warn behaviour, not a
    /// replacement for it: replacing a live id in place is still what a
    /// reloaded extension or a reloaded app feature needs, and nothing about
    /// wanting to remove an id outright changes that argument. Silent on an
    /// unknown id — `MainThreadCommands.dispose()` calls this for every id it
    /// ever owned, including one a duplicate registration already displaced,
    /// and that is not a mistake worth `fail-fast`ing over the way an
    /// unregistered `execute` is: nothing was supposed to run and nothing did.
    public func unregister(id: String) {
        guard commandsByID.removeValue(forKey: id) != nil else { return }
        registrationOrder.removeAll { $0 == id }
    }
}

extension CommandRegistry: Loggable {
    public static nonisolated let logger = makeLogger()
}
