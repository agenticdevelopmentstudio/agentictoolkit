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

/// Which registration of an id a caller is talking about.
///
/// Ids are not unique over time. `CommandRegistry.register` replaces a live id
/// in place (see its doc comment for why), so "the command registered as
/// `notes.action.newNote`" names one thing today and can name a different one
/// a moment later — and a caller holding a `Disposable`, or tearing down an
/// extension, means *the registration it made*, not whatever now answers to
/// that id. Without this, `unregister(id:)` was the only tool either caller
/// had, and an extension that shadowed an app command could delete the app's
/// command outright on the way out.
///
/// Opaque on purpose: a `UUID` nobody outside this file can mint or read. The
/// only way to hold one is to have performed the registration it names, which
/// is exactly the claim `unregister(id:token:)` checks.
public struct CommandRegistration: Hashable, Sendable {

    private let rawValue: UUID

    fileprivate init() {
        self.rawValue = UUID()
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

    /// One command and the token that names *this* registration of its id.
    ///
    /// Kept together in one dictionary rather than as a second `[String:
    /// CommandRegistration]` beside `commandsByID`, because two dictionaries
    /// keyed the same way are two places for one fact to drift — and the fact
    /// here is precisely that a command and its token are the same
    /// registration.
    private struct Registration {
        let command: AppCommand
        let token: CommandRegistration
    }

    private var registrationsByID: [String: Registration] = [:]

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
    ///
    /// - Returns: A token naming *this* registration, for a caller that will
    ///   later want to remove what it registered and nothing else — see
    ///   `unregister(id:token:)`. `@discardableResult` because the app's own
    ///   commands live as long as the app does and have nothing to do with the
    ///   token; only a registrant that can be torn down independently, which
    ///   today means an extension, has a use for it.
    @discardableResult
    public func register(_ command: AppCommand) -> CommandRegistration {
        if registrationsByID[command.id] != nil {
            Self.logger.warning(
                "Command id already registered, replacing: \(command.id, privacy: .public)"
            )
        } else {
            registrationOrder.append(command.id)
        }
        let token = CommandRegistration()
        registrationsByID[command.id] = Registration(command: command, token: token)
        return token
    }

    /// Every registered command, in registration order — what a command palette
    /// lists.
    public var allCommands: [AppCommand] {
        registrationOrder.compactMap { registrationsByID[$0]?.command }
    }

    /// The command registered under `id`, or `nil`.
    public func command(id: String) -> AppCommand? {
        registrationsByID[id]?.command
    }

    /// Whether `id` names a command that is registered *and* says it applies
    /// right now. An unregistered id answers `false` rather than `true`: a menu
    /// item pointing at a command nobody registered must not look available.
    public func isEnabled(id: String) -> Bool {
        registrationsByID[id]?.command.isEnabled() ?? false
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
    /// `arguments` and the returned value are deliberately untyped and
    /// **unconverted**. An extension-originated call carries the caller's own
    /// `JSValue`s straight through, so an object stays the same object, a class
    /// instance keeps its prototype, and a returned `Promise` is still a
    /// `Promise` when it reaches the `await` that asked for it; an app-side
    /// caller passes native Swift values and JavaScriptCore bridges them itself
    /// at `JSValue.call(withArguments:)`. Nothing in this registry should
    /// "helpfully" convert either direction — a round trip through `toObject()`
    /// is what loses all three of those.
    ///
    /// - Throws: the same two cases as `execute(id:)`, for the same reason.
    @discardableResult
    public func execute(id: String, arguments: [Any]) throws -> Any? {
        guard let command = registrationsByID[id]?.command else {
            throw CommandRegistryError.unknownCommand(id: id)
        }
        guard command.isEnabled() else {
            throw CommandRegistryError.commandDisabled(id: id)
        }
        return command.run(arguments)
    }

    /// Removes whatever is currently registered under `id`, and its entry in
    /// `registrationOrder`.
    ///
    /// **"Whatever is currently registered" is the literal contract**, and a
    /// caller that means "remove the registration *I* made" wants
    /// `unregister(id:token:)` below instead. The distinction is real because
    /// `register` replaces in place: an id can be registered, displaced by a
    /// second registrant, and unregistered by the first, and only the token
    /// form can tell those apart.
    ///
    /// **A displaced command is not restored, and is not restorable.** There is
    /// no stack of registrations here — `register`'s replace-and-warn destroys
    /// the previous command at the moment of replacement, so from that moment
    /// the app's own command is gone whatever happens next. Unregistering the
    /// displacer therefore leaves the id unregistered rather than reverting to
    /// what used to be there. That is deliberate for now: stacking
    /// registrations would be a statement about how far an extension is
    /// trusted to shadow the app, and that policy belongs with
    /// `ExtensionRegistry` and the permissions work, not with a registry whose
    /// whole job is turning an id into work.
    ///
    /// Silent on an unknown id, which is not a mistake worth `fail-fast`ing
    /// over the way an unregistered `execute` is: nothing was supposed to run
    /// and nothing did.
    public func unregister(id: String) {
        guard registrationsByID.removeValue(forKey: id) != nil else { return }
        registrationOrder.removeAll { $0 == id }
    }

    /// Removes `id` **only** if the registration currently under it is the one
    /// `token` names.
    ///
    /// This is what a registrant with a lifetime shorter than the app's — an
    /// extension, today — should call, and the failure it prevents is concrete:
    /// an extension registers an id the app already owned (Ruling 5 permits
    /// it), the app or another extension later re-registers that id, and the
    /// first extension's `Disposable` fires. By id alone that deletes a command
    /// it never registered, for the rest of the process, with only
    /// `register`'s collision warning anywhere in the log. By token it is a
    /// no-op, which is the honest answer: the thing the caller registered is
    /// already gone.
    ///
    /// Silent when the token does not match, for the same reason
    /// `unregister(id:)` is silent on an unknown id — and a stale `Disposable`
    /// firing is the *expected* case here, not an anomaly.
    public func unregister(id: String, token: CommandRegistration) {
        guard registrationsByID[id]?.token == token else { return }
        unregister(id: id)
    }
}

extension CommandRegistry: Loggable {
    public static nonisolated let logger = makeLogger()
}
