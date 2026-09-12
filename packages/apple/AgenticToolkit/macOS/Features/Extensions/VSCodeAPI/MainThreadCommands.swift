//
//  MainThreadCommands.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore
import OSLog
import AgenticToolkitCore

/// The `vscode.commands` adaptor: `registerCommand`, `executeCommand` and
/// `getCommands`, each terminating in the app's own `CommandRegistry` rather
/// than a second, extension-private command table.
///
/// **One instance per extension**, mirroring `ExtensionHost` itself. Nothing
/// enforces it — `defineVSCodeMember` will install these blocks on any number
/// of hosts — but every ownership question below is answered as if it holds.
/// That is what makes Ruling 5's duplicate check ("an id *this adaptor*
/// already owns") answerable at all: two extensions are two
/// `MainThreadCommands`, so one extension registering `'x'` twice is a
/// collision this type can see, and two different extensions each registering
/// `'x'` once is not — that second case is the registry's replace-and-warn
/// behaviour, unchanged, and deliberately not this type's decision (see the
/// doc on `handleRegisterCommand`). Install one instance on two hosts and the
/// two extensions' namespaces are conflated; `ownedCallbacks` is keyed by id
/// alone and has no way to notice.
///
/// Not `@convention(block)` itself — the three properties below are. This
/// class exists so those blocks have somewhere to keep the state a bare
/// closure cannot: the registry they dispatch through, and the ownership
/// record `dispose()` and Ruling 5 both read. The ceremony of *making* those
/// blocks lives in `VSCodeAPI`, which tasks 5.4–5.7 share, so that what is
/// left here reads as the `commands` adaptor rather than as four copies of an
/// incantation.
///
/// **Whoever owns this adaptor must call `dispose()` when it tears the
/// extension host down.** There is deliberately no `deinit` net, and nothing
/// in this framework calls `dispose()` today, because nothing instantiates
/// `ExtensionHost` in production yet — inventing an owner here would be a
/// guess at a wiring design that the `ExtensionsCoordinator` task owns. Until
/// that task wires it, the requirement lives in this paragraph, and what it
/// costs to miss is concrete: every command this adaptor registered stays in
/// `CommandRegistry`, so the app's command palette keeps rows that dispatch
/// into a dead extension, and each of those rows holds the callback `JSValue`
/// — and through it the whole `JSContext`, the extension's module graph and
/// everything the extension captured — alive for the rest of the process.
/// `ExtensionHost.dispose()` cannot do it for you: it does not know this
/// adaptor exists.
///
/// `@MainActor` for the same reason `CommandRegistry` and `ExtensionHost` are:
/// `JSValue` is not `Sendable`, and every block below is called by
/// JavaScriptCore on the thread that made the call, which for this host is
/// always the main actor.
@MainActor
public final class MainThreadCommands {

    /// Where a registered command actually runs. Shared with the app's own
    /// menus and command palette — an extension's command is a first-class
    /// row there, not a second table this adaptor keeps to itself.
    private let registry: CommandRegistry

    /// One id this adaptor registered: the JS callback it dispatches to, and
    /// the token naming *that* registration in the registry.
    ///
    /// The token is the difference between "unregister this id" and
    /// "unregister what I registered". Ruling 5 lets an extension register an
    /// id the app already owned, and `register` replaces in place, so the two
    /// routinely name different things a moment later; by id alone a stale
    /// `Disposable` deletes whatever now answers to the id, including one of
    /// the app's own commands.
    private struct OwnedCommand {
        let callback: JSValue
        let token: CommandRegistration
    }

    /// The ids this adaptor itself has registered.
    ///
    /// **Not a second command table.** Dispatch always goes through
    /// `registry`; this dictionary is purely the ownership record — the answer
    /// to "did *I* register this id" that Ruling 5's duplicate check needs, and
    /// the list `dispose()` walks to unregister everything this adaptor is
    /// responsible for. Losing this and reading the registry instead would
    /// answer a different question: whether the id is registered at all,
    /// which is true for the app's own commands too, and Ruling 5 is explicit
    /// that those may be shadowed.
    private var ownedCallbacks: [String: OwnedCommand] = [:]

    /// - Parameter registry: The registry extension commands dispatch through.
    ///   Not defaulted: a caller that forgot to pass its app's real registry
    ///   would otherwise get a private one silently, and every extension
    ///   command would vanish from the app's own command palette.
    public init(registry: CommandRegistry) {
        self.registry = registry
    }

    // MARK: - vscode.commands.registerCommand

    /// `implementation` for `vscode.commands.registerCommand`, handed to
    /// `ExtensionHost.defineVSCodeMember(namespacePath:name:implementation:)`
    /// as-is.
    ///
    /// Raises rather than rejects on a torn-down adaptor, because this member
    /// returns a `Disposable` and not a `Thenable`: answering `undefined`
    /// would let the extension push nothing onto `context.subscriptions` and
    /// believe it had registered a command.
    public private(set) lazy var registerCommand: Any = VSCodeAPI.member(
        "vscode.commands.registerCommand", of: self, whenTornDown: .raisedException
    ) { $0.handleRegisterCommand() }

    /// Ruling 6: `registerCommand` raises rather than rejects, because it
    /// returns a `Disposable`, not a `Thenable` — there is nothing for a
    /// synchronous failure here to reject.
    ///
    /// Three ways this refuses, in order: a missing or non-string command id,
    /// a callback that is not callable (Ruling 6, test 10), and Ruling 5's
    /// duplicate — an id *this* adaptor already owns. A duplicate the app or a
    /// different extension owns is not this type's call: VS Code itself lets
    /// extensions override some built-in ids, and refusing that here would be
    /// a trust decision that belongs with `ExtensionRegistry` and the
    /// permissions work, not with an API adaptor.
    private func handleRegisterCommand() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()

        guard let commandValue = arguments.first, commandValue.isString,
              let command = commandValue.toString() else {
            return VSCodeAPI.raise("registerCommand requires a string command id.", in: context)
        }

        guard arguments.count > 1 else {
            return VSCodeAPI.raise("registerCommand requires a callback function.", in: context)
        }
        let callback = arguments[1]
        // `callback instanceof Function`, which is `typeof callback ===
        // 'function'` for anything reachable from this context — there is
        // only ever one realm here, so the cross-realm gap between the two
        // checks does not apply.
        guard let functionConstructor = context.objectForKeyedSubscript("Function"),
              callback.isInstance(of: functionConstructor) else {
            return VSCodeAPI.raise("registerCommand's callback must be a function.", in: context)
        }

        guard ownedCallbacks[command] == nil else {
            return VSCodeAPI.raise("command '\(command)' already exists", in: context)
        }

        // Refused here rather than discovered at the first dispatch. This
        // member's whole product is a `Disposable` the extension pushes onto
        // `context.subscriptions` and then trusts; handing one back for a
        // command that provably cannot be invoked is the same silent lie
        // `CallOutcome.unavailable` exists to stop, one step earlier and with
        // a `try` in the extension that can still see it. Raises for Ruling
        // 6's reason, the same as every other refusal above.
        guard VSCodeAPI.canDispatch(in: context) else {
            return VSCodeAPI.raise(VSCodeAPI.dispatchUnavailableMessage(for: context), in: context)
        }

        // `undefined` and `null` both mean "no `thisArg`" (Ruling 7); anything
        // else, including a JS `false` or `0`, is a real value an extension
        // deliberately bound and must be honoured.
        let rawThisArg: JSValue? = arguments.count > 2 ? arguments[2] : nil
        let boundThisArg: JSValue? = {
            guard let rawThisArg, !rawThisArg.isUndefined, !rawThisArg.isNull else { return nil }
            return rawThisArg
        }()

        // `title` is the raw id, so this row reads `myext.doTheThing` in the
        // command palette and has no category. Constraint F puts
        // `contributes.commands` — where VS Code keeps the human-readable
        // title and category — out of this task's reach entirely, and
        // inventing a title from the id here would be a second, worse answer
        // that the real one would then have to displace. The `contributes`
        // wiring task is the one that fixes it.
        let token = registry.register(AppCommand(id: command, title: command, run: { rawArguments in
            MainThreadCommands.invoke(
                callback, thisArg: boundThisArg, arguments: rawArguments, commandID: command)
        }))
        ownedCallbacks[command] = OwnedCommand(callback: callback, token: token)

        return makeDisposable(id: command, token: token, in: context)
    }

    /// Calls the extension's callback and answers with something the registry
    /// can carry: the callback's own `JSValue`, a `CallbackFailure` if it
    /// threw, or a `DispatchUnavailable` if it was never invoked at all.
    ///
    /// **The adaptor owns its callbacks' exceptions.** Left to JavaScriptCore,
    /// a throw here reaches `ExtensionHost`'s `exceptionHandler` and lands in
    /// its `pendingException`, which the host reads after `callActivate` — so
    /// a command that throws while an `async activate()` is still in flight
    /// fails the *extension's activation*, naming a cause that came from
    /// somewhere else entirely. `VSCodeAPI.call` keeps it out of there;
    /// everything after that is about telling somebody.
    ///
    /// Both callers are told as well as they can be. `executeCommand` rejects
    /// its promise with the raw exception (see `handleExecuteCommand`), which
    /// is what a VS Code extension's `await … catch` expects. A dispatch from
    /// a menu item or the palette arrives through
    /// `CommandRegistry.execute(id:)`, which returns `Void` and has no caller
    /// to tell, so for that path the log line *is* the report — which is why
    /// the logging happens here, on the one path both share, rather than in
    /// `handleExecuteCommand`.
    ///
    /// **One rule decides whether it is logged: is anyone waiting on it.** An
    /// extension that writes
    /// `try { await vscode.commands.executeCommand('x') } catch { … }` has
    /// handled its own failure correctly and completely, so logging it at
    /// `error` in the host's subsystem would report an extension behaving
    /// properly as an app fault, and at volume. The round-1 ruling this
    /// descends from said a palette dispatch is logged and swallowed *because
    /// there is no caller to tell* — so where there is a caller, the caller is
    /// told and the log stays quiet. `dispatchHasCaller` is that bit, and both
    /// failure shapes below read it: one rule rather than two, which is also
    /// the cheaper thing to keep true as tasks 5.4–5.7 copy this ceremony.
    /// Note what this does *not* touch: the exception still never reaches
    /// `ExtensionHost.pendingException` on either path. F3/F4 were about where
    /// it goes, not about who writes it down.
    ///
    /// **An `async` callback does not throw — it rejects**, and a rejection is
    /// not a return value either path can notice: the call itself succeeded,
    /// and the failure arrives on a later microtask. So on the caller-less
    /// path a thenable return value gets a rejection handler attached here
    /// (`VSCodeAPI.observeRejection`), which is what makes a palette dispatch
    /// of `async () => { throw new Error('disk full') }` produce a log line
    /// instead of complete silence. Attaching it does not consume the
    /// rejection: the value handed back is still the extension's own promise,
    /// still rejecting. On the caller's path nothing is attached at all —
    /// the extension's own `await` is the observer.
    ///
    /// The one report that is *not* conditional is `.unavailable`. That is a
    /// host fault rather than an extension's, the extension is told as well
    /// (its promise rejects), and an operator who has to know the host could
    /// not dispatch at all should not need an extension to have been written
    /// without an `await` before it reaches the log.
    ///
    /// Deliberately **not** made to throw. `AppCommand.run` is `([Any]) ->
    /// Any?` and staying that way keeps the registry free of any knowledge
    /// that JavaScript exists; `CallbackFailure` and `DispatchUnavailable` are
    /// private to this file and unwrapped by the one member that can do
    /// something with them.
    private static func invoke(
        _ callback: JSValue,
        thisArg: JSValue?,
        arguments: [Any],
        commandID: String
    ) -> Any? {
        switch VSCodeAPI.call(callback, thisArg: thisArg, arguments: arguments) {
        case .returned(let value):
            if !dispatchHasCaller, let value, let context = value.context {
                VSCodeAPI.observeRejection(of: value, in: context) { reason in
                    MainThreadCommands.logger.error(
                        """
                        Extension command '\(commandID, privacy: .public)' rejected: \
                        \(reason.toString() ?? "<unprintable>", privacy: .public)
                        """)
                }
            }
            return value
        case .threw(let exception):
            // Same rule as the rejection above, and deliberately one rule
            // rather than two: an extension awaiting `executeCommand` receives
            // this as a rejection and owns it. What F3/F4 were about is where
            // the exception *goes* — never into
            // `ExtensionHost.pendingException` — and `VSCodeAPI.call` still
            // guarantees that on both paths. Whether the adaptor also logs is
            // a separate question, answered here by who is listening.
            if !dispatchHasCaller {
                logger.error(
                    """
                    Extension command '\(commandID, privacy: .public)' threw: \
                    \(exception.toString() ?? "<unprintable>", privacy: .public)
                    """)
            }
            return CallbackFailure(reason: exception)
        case .unavailable:
            // The callback was never invoked. `VSCodeAPI` has already logged
            // why; what matters here is that this must not leave as a value —
            // `nil` would resolve the extension's promise with `undefined`,
            // which is precisely what a `void` command that ran successfully
            // answers.
            logger.error(
                """
                Extension command '\(commandID, privacy: .public)' could not be dispatched: \
                its context has no usable command dispatch trampoline
                """)
            return DispatchUnavailable()
        }
    }

    /// Whether the dispatch currently running has a caller that will be handed
    /// its result — an extension's `await vscode.commands.executeCommand(…)` —
    /// as opposed to a palette or menu-item dispatch through
    /// `CommandRegistry.execute(id:)`, which returns `Void` and has nobody to
    /// tell.
    ///
    /// **`static` because the bit belongs to the dispatch, not to the
    /// adaptor** — this is the reason, and it is not a compromise. When
    /// extension A awaits a command extension B registered, B's callback is
    /// running on a path that genuinely has a caller, and B's adaptor is not
    /// the one that knows it. A per-adaptor flag would read `false` there and
    /// log B's rejection as though nobody were waiting on it, which is the
    /// exact noise this exists to remove. **Do not "fix" this into an instance
    /// property.** A second reason points the same way: the closure
    /// `handleRegisterCommand` hands to `CommandRegistry` captures no `self`,
    /// which is what keeps the adaptor out of the registry's retain graph and
    /// what the class doc's teardown paragraph rests on — reaching an instance
    /// flag from `invoke` would have to reintroduce exactly that edge, or read
    /// a weak reference that is `nil` after teardown and answer wrongly.
    ///
    /// **Yes, this is save-and-restore around a call, which is the shape
    /// `absorbingExceptions` was withdrawn for two rounds ago.** The
    /// distinction matters enough to write down, because the next reader will
    /// have that ruling in mind. That one mutated `JSContext.exceptionHandler`
    /// — *context-wide JavaScriptCore state*, shared with `ExtensionHost` and
    /// with every other adaptor installed on the context, across a window in
    /// which arbitrary JavaScript and re-entrant host operations could run, so
    /// restoring it could undo a `dispose()` and a re-entered host operation
    /// could lose its own exception into it. This is one `Bool` in this file,
    /// on the main actor, saved and restored around a *synchronous* call
    /// (`dispatchingForACaller`), observable by nothing outside this type, and
    /// owning no resource anyone else depends on. Nesting is correct by
    /// construction: a command that dispatches another command restores the
    /// outer value on the way out.
    private static var dispatchHasCaller = false

    /// Runs `body` with `dispatchHasCaller` set, restoring whatever it was
    /// before. The save-and-restore is a nested dispatch's correctness, not
    /// tidiness: `executeCommand` from inside a command callback is ordinary
    /// VS Code practice.
    private static func dispatchingForACaller<Value>(_ body: () throws -> Value) rethrows -> Value {
        let previous = dispatchHasCaller
        dispatchHasCaller = true
        defer { dispatchHasCaller = previous }
        return try body()
    }

    /// What `invoke` hands back when the extension's callback threw.
    ///
    /// A private type travelling through `AppCommand.run`'s `Any?`, which is
    /// the point: the registry stays a registry, and only the one member that
    /// has a promise to reject ever looks for this.
    private struct CallbackFailure {
        let reason: JSValue
    }

    /// What `invoke` hands back when the callback was never invoked at all —
    /// its context is gone, or the context has no usable dispatch trampoline.
    ///
    /// Distinct from `CallbackFailure` because there is no `JSValue` reason to
    /// carry: the failure happened outside JavaScript, and deliberately holds
    /// no context of its own so that `handleExecuteCommand` builds the
    /// rejection in *its own* live `JSContext.current()` rather than in the
    /// one that just proved unusable.
    ///
    /// It must not be `nil`. A `nil` here resolves the extension's promise
    /// with `undefined`, which is precisely what a successful `void` command
    /// answers — the silent lie this whole path exists to prevent.
    private struct DispatchUnavailable {}

    /// A JS object whose `dispose()` unregisters exactly the registration
    /// `token` names, and does nothing the second time it is called.
    ///
    /// VS Code's `Disposable` contract is exactly that idempotence, so
    /// `disposed` is captured by the block rather than re-derived from
    /// `ownedCallbacks` each call: re-deriving it would make a *second*
    /// extension's later reuse of the same id (after this one unregistered
    /// it) look, to a stale `Disposable` from the first registration, like
    /// something still worth disposing.
    ///
    /// **`token` is captured for the same reason, and it is not the same
    /// guard.** `disposed` only knows whether *this* `Disposable` already
    /// fired; it says nothing about what `id` names now. Reading the token
    /// out of `ownedCallbacks` at fire time reads whatever registration is
    /// current, so a `Disposable` minted before a `dispose()` — never fired,
    /// so still `disposed == false` — would unregister the adaptor's *own*
    /// fresh registration of the same id made after that teardown. Captured
    /// here, the token is the one this `Disposable` was minted for, and the
    /// mismatch is the no-op it should be.
    private func makeDisposable(id: String, token: CommandRegistration, in context: JSContext) -> JSValue? {
        guard let disposable = JSValue(newObjectIn: context) else { return nil }
        var disposed = false
        let dispose: @convention(block) () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard !disposed else { return }
                disposed = true
                self?.unregisterOwned(id: id, token: token)
            }
        }
        disposable.setObject(dispose, forKeyedSubscript: "dispose" as NSString)
        return disposable
    }

    /// Removes the registration `token` names from both the ownership record
    /// and the registry — the half of teardown a single `Disposable` needs.
    ///
    /// Three guards, answering three different questions. The dictionary
    /// lookup asks whether this adaptor still claims the id at all, which
    /// makes a second `dispose()` a no-op. Comparing the stored token with
    /// `token` asks whether the registration the *caller* is talking about is
    /// still the one this adaptor holds — the stale-`Disposable`-after-a-
    /// `dispose()`-and-re-register case. And the token handed to
    /// `CommandRegistry.unregister(id:token:)` asks whether that registration
    /// is still the one under the id in the registry at all — because
    /// `register` replaces in place, an extension that shadowed an app
    /// command and was then shadowed back would otherwise delete somebody
    /// else's command on the way out.
    private func unregisterOwned(id: String, token: CommandRegistration) {
        guard let owned = ownedCallbacks[id], owned.token == token else { return }
        ownedCallbacks.removeValue(forKey: id)
        registry.unregister(id: id, token: token)
    }

    // MARK: - vscode.commands.executeCommand

    /// `implementation` for `vscode.commands.executeCommand`.
    ///
    /// Rejects rather than raises on a torn-down adaptor: this member returns a
    /// `Thenable`, and Ruling 6's whole argument is that a synchronous failure
    /// from underneath an `await` reaches a `catch` the extension did not
    /// write. Answering `undefined` would be the worst version of that — the
    /// extension's own `.then` would be the thing that threw.
    public private(set) lazy var executeCommand: Any = VSCodeAPI.member(
        "vscode.commands.executeCommand", of: self, whenTornDown: .rejectedPromise
    ) { $0.handleExecuteCommand() }

    /// Ruling 6: always a settled promise, never a synchronous throw. VS Code
    /// extensions write `await vscode.commands.executeCommand(...)` inside
    /// `try`, and a synchronous throw from underneath an `await` reaches a
    /// `catch` other than the one they wrote.
    ///
    /// Dispatch is genuinely synchronous — this host runs one extension's
    /// JavaScript and the app's own command dispatch on the same actor, so the
    /// promise below is already resolved or rejected by the time it is handed
    /// back, and `Thenable` is honoured rather than actually deferring
    /// anything. The one exception is a command whose callback is itself
    /// `async`: its promise is handed straight back (see
    /// `VSCodeAPI.settledPromise`), so it settles when the extension's own work
    /// does.
    ///
    /// **Arguments and results cross untouched.** The `JSValue`s the caller
    /// passed go into `CommandRegistry.execute(id:arguments:)` as themselves,
    /// and the callback's return `JSValue` comes back the same way. Converting
    /// either through `toObject()` would be the obvious-looking mistake: it
    /// copies objects (so a callback's mutations become invisible to its
    /// caller), flattens class instances to plain dictionaries (so
    /// `vscode.Uri` and friends lose `fsPath` and every other method the
    /// moment 5.4–5.7 introduce them), turns functions into `{}`, and turns a
    /// returned `Promise` into an empty object. An app-side caller that passes
    /// native Swift values is unaffected —
    /// `JSValue.call(withArguments:)` bridges those itself.
    private func handleExecuteCommand() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()

        guard let commandValue = arguments.first, commandValue.isString,
              let command = commandValue.toString() else {
            return VSCodeAPI.rejectedPromise(
                message: "executeCommand requires a string command id.", in: context)
        }
        let rest = Array(arguments.dropFirst()) as [Any]

        do {
            // The one place a dispatch provably has a caller: this member is
            // the extension's own `executeCommand`, and whatever the registry
            // answers is handed straight back to it as a promise. `invoke`
            // reads the flag to decide whether a rejection has an owner other
            // than the log. Synchronous, so the `defer` inside restores the
            // previous value before anything else can observe it.
            let result = try Self.dispatchingForACaller {
                try registry.execute(id: command, arguments: rest)
            }
            if result is DispatchUnavailable {
                // The callback never ran. Rejecting — rather than resolving
                // with `undefined` — is the whole of ruling 4.
                return VSCodeAPI.rejectedPromise(
                    message: VSCodeAPI.dispatchUnavailableMessage(for: context), in: context)
            }
            if let failure = result as? CallbackFailure {
                // The extension's own exception, handed back to the extension
                // unchanged — same `Error` subclass, same `stack`. A
                // paraphrase would be the app inventing a cause.
                return VSCodeAPI.rejectedPromise(reason: failure.reason, in: context)
            }
            if let jsResult = result as? JSValue {
                return VSCodeAPI.settledPromise(for: jsResult, in: context)
            }
            // An app-registered command answering with a native Swift value:
            // JavaScriptCore bridges it on the way into the promise. A `nil`
            // here — which is what every `AppCommand` built with the legacy
            // `() -> Void` initializer returns — resolves with `undefined`
            // rather than `null`; `VSCodeAPI.resolvedPromise` owns that rule,
            // because getting it wrong sends an extension's
            // `result === undefined` down the wrong branch.
            return VSCodeAPI.resolvedPromise(with: result, in: context)
        } catch let error as CommandRegistryError {
            // The registry's own wording — "no command with id 'x'" versus
            // "registered but currently disabled" — is exactly what test 5
            // needs to tell the two rejections apart, so it is passed through
            // rather than paraphrased.
            return VSCodeAPI.rejectedPromise(message: error.description, in: context)
        } catch {
            return VSCodeAPI.rejectedPromise(message: "\(error)", in: context)
        }
    }

    // MARK: - vscode.commands.getCommands

    /// `implementation` for `vscode.commands.getCommands`. Rejects on a
    /// torn-down adaptor, for the reason `executeCommand` does.
    public private(set) lazy var getCommands: Any = VSCodeAPI.member(
        "vscode.commands.getCommands", of: self, whenTornDown: .rejectedPromise
    ) { $0.handleGetCommands() }

    /// Ruling 8: an absent, `undefined` or `false` argument answers with every
    /// id; `true` drops the ones VS Code treats as internal, a leading `_`.
    /// `toBool()` is JavaScript's own `ToBoolean`, so a caller that passes
    /// something other than a literal boolean gets the same answer a VS Code
    /// extension host would.
    ///
    /// This member has no failure mode of its own — reading
    /// `CommandRegistry.allCommands` cannot throw — so unlike
    /// `executeCommand` it only ever resolves, never rejects.
    private func handleGetCommands() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        let filterInternal = arguments.first?.toBool() ?? false

        let ids = registry.allCommands.map(\.id)
        let filtered = filterInternal ? ids.filter { !$0.hasPrefix("_") } : ids
        return VSCodeAPI.resolvedPromise(with: filtered, in: context)
    }

    // MARK: - Teardown

    /// Unregisters every command this adaptor registered, and drops its
    /// callback references.
    ///
    /// Not a call to `deinit`-time cleanup: a torn-down `ExtensionHost` must
    /// not leave rows in the command palette that invoke a `JSValue` on a
    /// `JSContext` that no longer exists, and that has to happen at the known
    /// moment the host is disposed, not whenever ARC gets around to it.
    ///
    /// Routed through `unregisterOwned` rather than unregistering ids
    /// directly, so a full teardown is token-guarded exactly as a single
    /// `Disposable` is: an id some other registrant has since taken over is
    /// theirs, and a wholesale teardown is not a licence to take it.
    public func dispose() {
        for (id, owned) in Array(ownedCallbacks) {
            unregisterOwned(id: id, token: owned.token)
        }
        ownedCallbacks.removeAll()
    }
}

extension MainThreadCommands: Loggable {

    /// The adaptor's own log destination — the same `Loggable` shape
    /// `CommandRegistry` and `ExtensionHost` use, so an extension command that
    /// threw shows up beside the registry's own collision warnings rather than
    /// in a subsystem of its own.
    public static nonisolated let logger = makeLogger()
}
