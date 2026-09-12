//
//  VSCodeAPI.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore

/// The ceremony every `vscode.*` namespace adaptor needs, written once.
///
/// `MainThreadCommands` is the first of five adaptors (tasks 5.3–5.7); the
/// other four — `workspace`, `window`, `languages`, `lm` — install their
/// members through the same seam, answer a torn-down host the same way, invoke
/// extension callbacks the same way, and settle the same promises. Three
/// things in the original `commands` adaptor were about none of that and all
/// of this: the `@convention(block)` + `MainActor.assumeIsolated` + `[weak
/// self]` incantation, the `JSContext.currentArguments()` dance, and the
/// settled-promise constructors. They live here so the fifth copy never gets
/// written, and so a change of policy — what a dead adaptor answers, how a
/// thrown callback is reported — is one edit rather than five that drift.
///
/// A caseless `enum`, not a class: there is no state worth keeping. Everything
/// a member needs is either handed in or read from `JSContext.current()`, which
/// JavaScriptCore fills in for the duration of a block call.
///
/// `@MainActor` for the reason every type in this directory is: `JSValue` is
/// not `Sendable`, and JavaScriptCore calls these blocks on the thread that
/// made the call, which for an `ExtensionHost` is always the main actor.
@MainActor
public enum VSCodeAPI {

    // MARK: - Installing a member

    /// Wraps `body` as the `Any` that
    /// `ExtensionHost.defineVSCodeMember(namespacePath:name:implementation:)`
    /// hands to JavaScriptCore.
    ///
    /// Declared with no formal parameters and read through `currentArguments()`
    /// instead: JavaScriptCore pads a block's missing trailing parameters with
    /// `undefined`, which would make an omitted optional argument
    /// indistinguishable from one explicitly passed as `undefined` — by
    /// accident of how many parameters the block happened to declare. Reading
    /// the actual argument list is one rule instead of one per member.
    ///
    /// `owner` is captured **weakly**, which is the whole reason this takes an
    /// owner rather than a bare closure: JavaScript holds the installed
    /// function for as long as the extension's context lives, and an adaptor
    /// the app has already dropped must not be resurrected by it. What happens
    /// then is `response`'s job, and it is deliberately not "return `nil`" —
    /// `nil` reaches JavaScript as `undefined`, so a member that should answer
    /// a `Thenable` would instead make the extension's own `.then` throw
    /// synchronously, inside whatever `try` it wrote around its `await`.
    ///
    /// - Parameters:
    ///   - path: The member's full path, `vscode.commands.executeCommand`
    ///     shaped. Only ever read back out in the torn-down message, which is
    ///     the one error an extension can hit with nothing else naming the
    ///     member.
    ///   - owner: The adaptor the member belongs to.
    ///   - response: What the member answers once `owner` is gone.
    ///   - body: The member's actual implementation, run on the main actor with
    ///     the still-live owner.
    /// - Returns: A `@convention(block)` closure, boxed as `Any`.
    public static func member<Owner: AnyObject>(
        _ path: String,
        of owner: Owner,
        whenTornDown response: TeardownResponse,
        body: @escaping @MainActor (Owner) -> JSValue?
    ) -> Any {
        let block: @convention(block) () -> JSValue? = { [weak owner] in
            MainActor.assumeIsolated {
                guard let owner else {
                    return UncheckedJSValueBox(value: tornDown(path: path, response: response))
                }
                return UncheckedJSValueBox(value: body(owner))
            }.value
        }
        return block
    }

    /// How a member answers a call that arrives after its adaptor has been
    /// deallocated.
    ///
    /// The two cases are the two shapes a `vscode` member has: one that returns
    /// a `Thenable`, whose every failure must be a rejection, and one that
    /// returns a value synchronously, whose failures are raised exceptions.
    /// Choosing between them is the member's own decision and never this
    /// type's, which is why it is a parameter.
    public enum TeardownResponse: Sendable {

        /// For a member that returns a `Thenable` — `executeCommand`,
        /// `getCommands`. The extension's `catch` sees the teardown.
        case rejectedPromise

        /// For a member that returns a value — `registerCommand`. The
        /// extension's `try` sees the teardown, rather than silently pushing
        /// `undefined` onto `context.subscriptions`.
        case raisedException
    }

    private static func tornDown(path: String, response: TeardownResponse) -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let message = "\(path) is unavailable: this extension's host has been torn down."
        switch response {
        case .rejectedPromise:
            return rejectedPromise(message: message, in: context)
        case .raisedException:
            return raise(message, in: context)
        }
    }

    // MARK: - Arguments

    /// The arguments of the block call currently running, as `JSValue`s.
    ///
    /// Empty rather than `nil` when there is no call in flight: every caller
    /// immediately asks about a specific position, and an empty list answers
    /// that question the same way a missing one would.
    public static func currentArguments() -> [JSValue] {
        (JSContext.currentArguments() as? [JSValue]) ?? []
    }

    // MARK: - Raising

    /// Raises `message` as a JavaScript `Error` on `context` and answers `nil`,
    /// so a member can `return VSCodeAPI.raise(…)` in one line.
    ///
    /// Setting `context.exception` is how a `@convention(block)` throws — a
    /// Swift `throw` has nowhere to go from inside one. The returned `nil`
    /// never reaches JavaScript as a value: the exception supersedes it.
    @discardableResult
    public static func raise(_ message: String, in context: JSContext) -> JSValue? {
        context.exception = JSValue(newErrorFromMessage: message, in: context)
        return nil
    }

    // MARK: - Promises

    /// An already-resolved promise carrying `value`, which may be any
    /// JavaScriptCore-bridgeable Swift value — a `String`, an array of them, or
    /// a `JSValue`, which bridges to itself.
    public static func resolvedPromise(with value: Any?, in context: JSContext) -> JSValue? {
        JSValue(newPromiseResolvedWithResult: value as Any, in: context)
    }

    /// An already-rejected promise carrying `reason`, the JavaScript value the
    /// extension's `catch` receives.
    ///
    /// Takes the raw `JSValue` rather than a message so an exception an
    /// extension's own callback threw can be handed back to it **unchanged** —
    /// same `Error` subclass, same `stack`, same custom properties. A
    /// paraphrase would be the app inventing a cause for a failure it did not
    /// have.
    public static func rejectedPromise(reason: JSValue, in context: JSContext) -> JSValue? {
        JSValue(newPromiseRejectedWithReason: reason as Any, in: context)
    }

    /// An already-rejected promise carrying a fresh `Error` built from
    /// `message` — for the failures the app itself diagnosed, where there is no
    /// extension-thrown value to preserve.
    public static func rejectedPromise(message: String, in context: JSContext) -> JSValue? {
        guard let reason = JSValue(newErrorFromMessage: message, in: context) else { return nil }
        return rejectedPromise(reason: reason, in: context)
    }

    /// The promise a member hands back for a value an extension callback
    /// produced.
    ///
    /// Three cases, and the middle one is the point. A callback that returned
    /// nothing answers a promise resolved with `undefined` — not `null`, which
    /// an extension's `if (result === undefined)` would read as a different
    /// answer. A callback that returned a **thenable** — every `async`
    /// function does — answers *with that thenable*, rather than with a second
    /// promise wrapping it: `await executeCommand(…)` must settle with what the
    /// `async` command eventually produced, and passing the promise through is
    /// both the shorter path and the one that keeps the identity VS Code's own
    /// `executeCommand` has. Anything else resolves as itself.
    ///
    /// Reading `.then` is a property access on extension-controlled data, so it
    /// is done inside `absorbingExceptions` — a `Proxy` or a lazily-defined
    /// property can throw from the *getter*, and an exception raised there
    /// would otherwise escape into the host's `exceptionHandler` and be
    /// misattributed to whatever the host was doing at the time. A getter that
    /// throws rejects the promise with what it threw, which is what
    /// `Promise.resolve` does with the same object.
    public static func settledPromise(for value: JSValue?, in context: JSContext) -> JSValue? {
        guard let value else {
            return resolvedPromise(with: JSValue(undefinedIn: context), in: context)
        }
        let (isThenable, thrown) = absorbingExceptions(in: context) { self.isThenable(value, in: context) }
        if let thrown {
            return rejectedPromise(reason: thrown, in: context)
        }
        return isThenable ? value : resolvedPromise(with: value, in: context)
    }

    private static func isThenable(_ value: JSValue, in context: JSContext) -> Bool {
        guard value.isObject, value.hasProperty("then") else { return false }
        guard let then = value.forProperty("then"),
              let functionConstructor = context.objectForKeyedSubscript("Function") else { return false }
        return then.isInstance(of: functionConstructor)
    }

    // MARK: - Calling back into the extension

    /// What an extension callback did.
    ///
    /// Not `Result`: the failure here is a `JSValue`, which conforms to nothing
    /// and is not the app's error to begin with — it is the extension's, being
    /// carried back to the extension. A two-case enum says that without
    /// claiming otherwise.
    public enum CallOutcome {

        /// The callback returned, with this value. `nil` only when the call
        /// could not be made at all — a `JSValue` whose context is gone.
        case returned(JSValue?)

        /// The callback threw, with this value. Almost always an `Error`, but
        /// JavaScript permits throwing anything, so it is not narrowed.
        case threw(JSValue)
    }

    /// Calls `function` — an extension's own callback — and answers with what
    /// it returned *or* what it threw, without the throw ever reaching the
    /// host.
    ///
    /// That last clause is the whole reason this exists. `ExtensionHost`
    /// installs a `context.exceptionHandler` that records into its
    /// `pendingException` and is read after `callActivate`; an exception thrown
    /// by a command callback while an `async activate()` is still in flight
    /// therefore fails the *extension's activation*, naming a cause that had
    /// nothing to do with `activate`. Measured, not deduced: with a custom
    /// handler installed JavaScriptCore calls that handler **instead of**
    /// setting `context.exception`, so reading `context.exception` after the
    /// call finds nothing and there is nothing to clear. Swapping the handler
    /// for the duration of the call is what actually keeps the exception out of
    /// the host's bookkeeping — it nests correctly (a callback that calls back
    /// into another callback saves and restores in order) and it puts the
    /// host's own handler back before returning.
    ///
    /// - Parameters:
    ///   - function: The extension's callback.
    ///   - thisArg: What to bind as `this`, or `nil` for the default. Passed
    ///     through `Function.prototype.call`, which is the only way to bind a
    ///     receiver from this side.
    ///   - arguments: Anything `JSValue.call(withArguments:)` accepts —
    ///     `JSValue`s pass through untouched, native Swift values are bridged
    ///     by JavaScriptCore itself.
    public static func call(
        _ function: JSValue,
        thisArg: JSValue?,
        arguments: [Any]
    ) -> CallOutcome {
        guard let context = function.context else { return .returned(nil) }
        let (value, thrown) = absorbingExceptions(in: context) { () -> JSValue? in
            if let thisArg {
                return function.invokeMethod("call", withArguments: [thisArg] + arguments)
            }
            return function.call(withArguments: arguments)
        }
        if let thrown {
            return .threw(thrown)
        }
        return .returned(value)
    }

    /// Runs `body` with `context`'s exception handler replaced by one that
    /// captures, and puts the original back afterwards.
    ///
    /// The sink is a class rather than a captured `var` because the handler is
    /// an Objective-C block property whose imported signature makes no promise
    /// about isolation. It never crosses one: JavaScriptCore invokes the
    /// handler synchronously, inside `body`, on the thread that called it —
    /// the same argument `UncheckedJSValueBox` makes, for the same reason.
    private static func absorbingExceptions<T>(
        in context: JSContext,
        _ body: () -> T
    ) -> (T, JSValue?) {
        let saved = context.exceptionHandler
        let sink = JSExceptionSink()
        context.exceptionHandler = { _, exception in sink.exception = exception }
        let value = body()
        context.exceptionHandler = saved
        return (value, sink.exception)
    }
}

/// Collects the one exception `VSCodeAPI.absorbingExceptions` is installed to
/// catch. A reference type so the handler block can write where the caller
/// reads; `@unchecked Sendable` because the block property's imported type
/// carries no isolation, and this value provably never leaves the thread that
/// created it.
private final class JSExceptionSink: @unchecked Sendable {
    var exception: JSValue?
}

/// Carries a `JSValue?` out of `MainActor.assumeIsolated`, whose generic
/// return type must be `Sendable` even though nothing here actually crosses
/// an isolation domain: every block above runs synchronously, on the one
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
