//
//  MainThreadCommands.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore

/// The `vscode.commands` adaptor: `registerCommand`, `executeCommand` and
/// `getCommands`, each terminating in the app's own `CommandRegistry` rather
/// than a second, extension-private command table.
///
/// One instance per extension, mirroring `ExtensionHost` itself. That is what
/// makes Ruling 5's duplicate check ("an id *this adaptor* already owns")
/// answerable at all: two extensions are two `MainThreadCommands`, so one
/// extension registering `'x'` twice is a collision this type can see, and two
/// different extensions each registering `'x'` once is not — that second case
/// is the registry's replace-and-warn behaviour, unchanged, and deliberately
/// not this type's decision (see the doc on `handleRegisterCommand`).
///
/// Not `@convention(block)` itself — the three properties below are. This
/// class exists so those blocks have somewhere to keep the state a bare
/// closure cannot: the registry they dispatch through, and the ids-to-JSValue
/// ownership record `dispose()` and Ruling 5 both read.
///
/// `@MainActor` for the same reason `CommandRegistry` and `ExtensionHost` are:
/// `JSValue` is not `Sendable`, and every block below is called by
/// JavaScriptCore on the thread that made the call, which for this host is
/// always the main actor.
/// Carries a `JSValue?` out of `MainActor.assumeIsolated`, whose generic
/// return type must be `Sendable` even though nothing here actually crosses
/// an isolation domain: every block below runs synchronously, on the one
/// thread JavaScriptCore ever calls it from, which is why `assumeIsolated`
/// applies in the first place. `JSValue` itself has no `Sendable`
/// conformance to appeal to — it is a JavaScriptCore class, not a type this
/// module owns — so this box is the honest way to tell the compiler what the
/// surrounding design already guarantees, rather than reaching for
/// `@preconcurrency import JavaScriptCore` and quietly widening that escape
/// hatch to every use of the framework in this file.
private struct UncheckedJSValueBox: @unchecked Sendable {
    let value: JSValue?
}

@MainActor
public final class MainThreadCommands {

    /// Where a registered command actually runs. Shared with the app's own
    /// menus and command palette — an extension's command is a first-class
    /// row there, not a second table this adaptor keeps to itself.
    private let registry: CommandRegistry

    /// The ids this adaptor itself has registered, and the JS callback each one
    /// dispatches to.
    ///
    /// **Not a second command table.** Dispatch always goes through
    /// `registry`; this dictionary is purely the ownership record — the answer
    /// to "did *I* register this id" that Ruling 5's duplicate check needs, and
    /// the list `dispose()` walks to unregister everything this adaptor is
    /// responsible for. Losing this and reading the registry instead would
    /// answer a different question: whether the id is registered at all,
    /// which is true for the app's own commands too, and Ruling 5 is explicit
    /// that those may be shadowed.
    private var ownedCallbacks: [String: JSValue] = [:]

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
    /// Declared with no formal parameters and read through
    /// `JSContext.currentArguments()` inside `handleRegisterCommand()` instead
    /// of as `(String, JSValue, JSValue?) -> JSValue?`: JavaScriptCore fills a
    /// block's missing trailing parameters with `undefined`, which would make
    /// an omitted `thisArg` indistinguishable from one explicitly passed as
    /// `undefined` only by accident of how many parameters happened to be
    /// declared. Reading the actual argument list once, here and in the two
    /// members below, is one rule instead of three near-identical ones.
    public private(set) lazy var registerCommand: Any = {
        let block: @convention(block) () -> JSValue? = { [weak self] in
            MainActor.assumeIsolated { UncheckedJSValueBox(value: self?.handleRegisterCommand()) }.value
        }
        return block
    }()

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
        let arguments = (JSContext.currentArguments() as? [JSValue]) ?? []

        guard let commandValue = arguments.first, commandValue.isString,
              let command = commandValue.toString() else {
            context.exception = JSValue(
                newErrorFromMessage: "registerCommand requires a string command id.", in: context)
            return nil
        }

        guard arguments.count > 1 else {
            context.exception = JSValue(
                newErrorFromMessage: "registerCommand requires a callback function.", in: context)
            return nil
        }
        let callback = arguments[1]
        // `callback instanceof Function`, which is `typeof callback ===
        // 'function'` for anything reachable from this context — there is
        // only ever one realm here, so the cross-realm gap between the two
        // checks does not apply.
        guard let functionConstructor = context.objectForKeyedSubscript("Function"),
              callback.isInstance(of: functionConstructor) else {
            context.exception = JSValue(
                newErrorFromMessage: "registerCommand's callback must be a function.", in: context)
            return nil
        }

        guard ownedCallbacks[command] == nil else {
            context.exception = JSValue(
                newErrorFromMessage: "command '\(command)' already exists", in: context)
            return nil
        }

        // `undefined` and `null` both mean "no `thisArg`" (Ruling 7); anything
        // else, including a JS `false` or `0`, is a real value an extension
        // deliberately bound and must be honoured.
        let rawThisArg: JSValue? = arguments.count > 2 ? arguments[2] : nil
        let boundThisArg: JSValue? = {
            guard let rawThisArg, !rawThisArg.isUndefined, !rawThisArg.isNull else { return nil }
            return rawThisArg
        }()

        ownedCallbacks[command] = callback
        registry.register(AppCommand(id: command, title: command, run: { rawArguments in
            let result: JSValue?
            if let boundThisArg {
                result = callback.invokeMethod("call", withArguments: [boundThisArg] + rawArguments)
            } else {
                result = callback.call(withArguments: rawArguments)
            }
            return result?.toObject()
        }))

        return makeDisposable(id: command, in: context)
    }

    /// A JS object whose `dispose()` unregisters `id` — and only `id` — from
    /// this adaptor, and does nothing the second time it is called.
    ///
    /// VS Code's `Disposable` contract is exactly that idempotence, so
    /// `disposed` is captured by the block rather than re-derived from
    /// `ownedCallbacks` each call: re-deriving it would make a *second*
    /// extension's later reuse of the same id (after this one unregistered
    /// it) look, to a stale `Disposable` from the first registration, like
    /// something still worth disposing.
    private func makeDisposable(id: String, in context: JSContext) -> JSValue? {
        guard let disposable = JSValue(newObjectIn: context) else { return nil }
        var disposed = false
        let dispose: @convention(block) () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard !disposed else { return }
                disposed = true
                self?.unregisterOwned(id: id)
            }
        }
        disposable.setObject(dispose, forKeyedSubscript: "dispose" as NSString)
        return disposable
    }

    /// Removes `id` from both the ownership record and the registry — the
    /// half of teardown a single `Disposable` needs — but only if this adaptor
    /// still owns it. Called from a `Disposable.dispose()` that already fired
    /// once, or from `dispose()` below tearing down everything at once, this
    /// guard is what makes either caller's second attempt at the same id a
    /// no-op instead of unregistering whatever now happens to sit under that
    /// id.
    private func unregisterOwned(id: String) {
        guard ownedCallbacks.removeValue(forKey: id) != nil else { return }
        registry.unregister(id: id)
    }

    // MARK: - vscode.commands.executeCommand

    /// `implementation` for `vscode.commands.executeCommand`.
    public private(set) lazy var executeCommand: Any = {
        let block: @convention(block) () -> JSValue? = { [weak self] in
            MainActor.assumeIsolated { UncheckedJSValueBox(value: self?.handleExecuteCommand()) }.value
        }
        return block
    }()

    /// Ruling 6: always a settled promise, never a synchronous throw. VS Code
    /// extensions write `await vscode.commands.executeCommand(...)` inside
    /// `try`, and a synchronous throw from underneath an `await` reaches a
    /// `catch` other than the one they wrote.
    ///
    /// Dispatch is genuinely synchronous — this host runs one extension's
    /// JavaScript and the app's own command dispatch on the same actor, so the
    /// promise below is already resolved or rejected by the time it is handed
    /// back, and `Thenable` is honoured rather than actually deferring
    /// anything.
    private func handleExecuteCommand() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = (JSContext.currentArguments() as? [JSValue]) ?? []

        guard let commandValue = arguments.first, commandValue.isString,
              let command = commandValue.toString() else {
            let reason = JSValue(
                newErrorFromMessage: "executeCommand requires a string command id.", in: context)
            return JSValue(newPromiseRejectedWithReason: reason as Any, in: context)
        }
        let rest = arguments.dropFirst().map { $0.toObject() as Any }

        do {
            let result = try registry.execute(id: command, arguments: Array(rest))
            return JSValue(newPromiseResolvedWithResult: result as Any, in: context)
        } catch let error as CommandRegistryError {
            // The registry's own wording — "no command with id 'x'" versus
            // "registered but currently disabled" — is exactly what test 5
            // needs to tell the two rejections apart, so it is passed through
            // rather than paraphrased.
            let reason = JSValue(newErrorFromMessage: error.description, in: context)
            return JSValue(newPromiseRejectedWithReason: reason as Any, in: context)
        } catch {
            let reason = JSValue(newErrorFromMessage: "\(error)", in: context)
            return JSValue(newPromiseRejectedWithReason: reason as Any, in: context)
        }
    }

    // MARK: - vscode.commands.getCommands

    /// `implementation` for `vscode.commands.getCommands`.
    public private(set) lazy var getCommands: Any = {
        let block: @convention(block) () -> JSValue? = { [weak self] in
            MainActor.assumeIsolated { UncheckedJSValueBox(value: self?.handleGetCommands()) }.value
        }
        return block
    }()

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
        let arguments = (JSContext.currentArguments() as? [JSValue]) ?? []
        let filterInternal = arguments.first?.toBool() ?? false

        let ids = registry.allCommands.map(\.id)
        let filtered = filterInternal ? ids.filter { !$0.hasPrefix("_") } : ids
        return JSValue(newPromiseResolvedWithResult: filtered as Any, in: context)
    }

    // MARK: - Teardown

    /// Unregisters every command this adaptor registered, and drops its
    /// callback references.
    ///
    /// Not a call to `deinit`-time cleanup: a torn-down `ExtensionHost` must
    /// not leave rows in the command palette that invoke a `JSValue` on a
    /// `JSContext` that no longer exists, and that has to happen at the known
    /// moment the host is disposed, not whenever ARC gets around to it.
    public func dispose() {
        for id in ownedCallbacks.keys {
            registry.unregister(id: id)
        }
        ownedCallbacks.removeAll()
    }
}
