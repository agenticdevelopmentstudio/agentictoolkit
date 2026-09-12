//
//  VSCodeAPI.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore
import OSLog
import AgenticToolkitCore

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
    ///
    /// **`nil` resolves with `undefined`, not `null`.** A Swift `nil` handed to
    /// JavaScriptCore as `Any` bridges to `NSNull` and arrives in JavaScript as
    /// `null`, so an extension writing `if (result === undefined)` would take
    /// the wrong branch for every command that simply returned nothing — and
    /// every `AppCommand` built with the legacy `() -> Void` initializer
    /// returns exactly that. "Returned nothing" is `undefined` in JavaScript,
    /// and a caller that genuinely means `null` says so with
    /// `JSValue(nullIn:)`.
    public static func resolvedPromise(with value: Any?, in context: JSContext) -> JSValue? {
        guard let value else {
            guard let undefinedValue = JSValue(undefinedIn: context) else { return nil }
            return JSValue(newPromiseResolvedWithResult: undefinedValue, in: context)
        }
        return JSValue(newPromiseResolvedWithResult: value, in: context)
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
    /// happens inside the JavaScript trampoline (see `thenFunction(of:in:)`) —
    /// a `Proxy` or a lazily-defined property can throw from the *getter*, and
    /// an exception raised there would otherwise escape into the host's
    /// `exceptionHandler` and be misattributed to whatever the host was doing
    /// at the time. A getter that throws rejects the promise with what it
    /// threw, which is what `Promise.resolve` does with the same object.
    ///
    /// A context that cannot answer the question at all — no trampoline, or
    /// one that answered something other than its contracted record — rejects
    /// rather than guessing. Guessing "not a thenable" would resolve the
    /// extension's promise with the raw object, which is a different answer
    /// from the one its command produced.
    public static func settledPromise(for value: JSValue?, in context: JSContext) -> JSValue? {
        guard let value else {
            return resolvedPromise(with: nil, in: context)
        }
        switch thenFunction(of: value, in: context) {
        case .threw(let reason):
            return rejectedPromise(reason: reason, in: context)
        case .thenable:
            return value
        case .notThenable:
            return resolvedPromise(with: value, in: context)
        case .unavailable:
            return rejectedPromise(message: dispatchUnavailableMessage(for: context), in: context)
        }
    }

    // MARK: - Calling back into the extension

    /// What an extension callback did.
    ///
    /// Not `Result`: the failure here is a `JSValue`, which conforms to nothing
    /// and is not the app's error to begin with — it is the extension's, being
    /// carried back to the extension. A plain enum says that without
    /// claiming otherwise.
    public enum CallOutcome {

        /// The callback returned, with this value.
        ///
        /// `nil` is vanishingly rare and never means "returned nothing": a
        /// callback that returns nothing answers a `JSValue` holding
        /// `undefined`. It means the trampoline's record carried no `value`
        /// property at all, which the shape check in `outcome(of:in:)` has
        /// already ruled out for every record it accepts.
        case returned(JSValue?)

        /// The callback threw, with this value. Almost always an `Error`, but
        /// JavaScript permits throwing anything, so it is not narrowed.
        case threw(JSValue)

        /// **The callback was never invoked.** Its context is gone, the
        /// dispatch trampoline could not be installed there, or the trampoline
        /// answered something that is not the record it is contracted to
        /// answer.
        ///
        /// A separate case rather than `.returned(nil)`, and that is the whole
        /// point of it: `.returned(nil)` resolves an extension's promise with
        /// `undefined`, which is exactly what a successful `void` command
        /// answers — so the old spelling told an extension its command had run
        /// when nothing had. A caller must turn this into a rejection or a
        /// raised exception, never into a value (`fail-fast`).
        case unavailable
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
    /// call finds nothing and there is nothing to clear.
    ///
    /// **The catch is in JavaScript, not in the handler.** An earlier round
    /// swapped `context.exceptionHandler` for the duration of the call, and
    /// that was wrong in two directions: `exceptionHandler` is *context-wide*
    /// state being used for a *call-scoped* job, so restoring it
    /// unconditionally undid `ExtensionHost.dispose()`'s deliberate
    /// `exceptionHandler = nil`, and any host operation re-entered from inside
    /// a callback lost its own exception into the sink. Going through a JS
    /// `try`/`catch` instead touches no context-wide state at all, and is
    /// re-entrant for free: each invocation gets its own JavaScript stack
    /// frame.
    ///
    /// - Parameters:
    ///   - function: The extension's callback.
    ///   - thisArg: What to bind as `this`, or `nil` for the default. `nil`,
    ///     JS `undefined` and JS `null` are the same answer here (Ruling 7),
    ///     and `undefined` is the spelling the trampoline's `Reflect.apply`
    ///     receives for it.
    ///   - arguments: Anything `JSValue.call(withArguments:)` accepts —
    ///     `JSValue`s pass through untouched, native Swift values are bridged
    ///     by JavaScriptCore itself.
    public static func call(
        _ function: JSValue,
        thisArg: JSValue?,
        arguments: [Any]
    ) -> CallOutcome {
        guard let context = function.context else { return .unavailable }
        guard let invoke = helperFunction("call", in: context),
              let undefinedValue = JSValue(undefinedIn: context) else {
            // Deliberately **not** falling back to calling `function`
            // directly: an uncaught throw from that call is exactly the thing
            // this method exists to keep out of the host's bookkeeping, so a
            // context that cannot host the trampoline gets no call at all.
            // `sharedHelper(in:)` has already logged why. `.unavailable` and
            // not `.returned(nil)`, so the caller reports a failure rather
            // than resolving with the `undefined` that means success.
            return .unavailable
        }
        let callArguments: [Any] = [function, thisArg ?? undefinedValue] + arguments
        return outcome(of: invoke.call(withArguments: callArguments), in: context)
    }

    /// What an extension is told when its context cannot dispatch commands.
    ///
    /// Shared by every refusal on that path — `registerCommand`'s raised
    /// exception, `executeCommand`'s rejection — so an extension author
    /// chasing one sees the same sentence as the host's log line rather than
    /// two paraphrases of one fault.
    public static func dispatchUnavailableMessage(for context: JSContext) -> String {
        """
        The extension host could not install its command dispatch trampoline in \
        JavaScript context '\(name(of: context))', so extension command callbacks \
        cannot be invoked in it.
        """
    }

    /// Whether `context` can dispatch extension callbacks at all — both halves
    /// of the trampoline present and reachable.
    ///
    /// For the member that has something to refuse *before* any callback runs:
    /// `registerCommand` returns a `Disposable`, and handing one back for a
    /// command that could never be invoked is the same silent lie
    /// `.unavailable` exists to stop. Calling this also installs the
    /// trampoline, so a later dispatch in the same context finds it cached.
    public static func canDispatch(in context: JSContext) -> Bool {
        helperFunction("call", in: context) != nil && helperFunction("thenOf", in: context) != nil
    }

    /// Attaches `handler` to `value`'s rejection, if `value` is a thenable,
    /// **without changing what `value` is**.
    ///
    /// The failure this closes: a command callback declared `async` does not
    /// throw, it returns a rejected promise. Nothing in `call` sees that — the
    /// call itself returned perfectly well — so a palette dispatch of
    /// `async () => { throw new Error('disk full') }` produced no log, no
    /// surfacing and no trace of any kind. `CommandRegistry.execute(id:)`
    /// returns `Void` and has no caller to tell, so the log line *is* the
    /// report, and something has to be watching the promise for there to be
    /// one.
    ///
    /// **The original value is what the caller keeps.** `then` answers a
    /// *derived* promise, and handing that one back would be the swallow this
    /// is supposed to prevent: the derived promise resolves (the handler
    /// returned normally), so an extension awaiting it would see success where
    /// its own command failed. The derived promise is discarded here — it is
    /// settled and handled, so it is not itself an unobserved rejection — and
    /// `value`, still rejecting, is what `executeCommand` hands to the
    /// extension.
    ///
    /// - Parameters:
    ///   - value: The value a callback returned. A non-thenable is left alone.
    ///   - context: The context `value` belongs to.
    ///   - handler: Called with the rejection reason, on the main actor.
    /// - Returns: Whether the handler was actually attached. `false` covers
    ///   three things the caller has to treat identically — `value` is not a
    ///   thenable, reading its `then` threw, or calling `then` threw — because
    ///   all three end in "nothing is watching this value", which is the only
    ///   fact a caller can act on. In particular a `Proxy` whose `then` trap
    ///   throws is the case the comment below anticipates, and saying `true`
    ///   for it would be claiming an observer that does not exist.
    @discardableResult
    public static func observeRejection(
        of value: JSValue,
        in context: JSContext,
        _ handler: @escaping @MainActor (JSValue) -> Void
    ) -> Bool {
        guard case .thenable(let then) = thenFunction(of: value, in: context),
              let undefinedValue = JSValue(undefinedIn: context) else {
            return false
        }
        // No formal parameters, for `member`'s reason: the reason is read off
        // the actual argument list rather than off however many parameters the
        // block happened to declare.
        let onRejected: @convention(block) () -> Void = {
            MainActor.assumeIsolated {
                guard let reason = currentArguments().first else { return }
                handler(reason)
            }
        }
        let thenArguments: [Any] = [undefinedValue, onRejected]
        // Through `call`, not `invokeMethod`: `then` is extension-controlled
        // and a `Proxy`'s trap can throw from it.
        switch call(then, thisArg: value, arguments: thenArguments) {
        case .returned:
            return true
        case .threw, .unavailable:
            return false
        }
    }

    // MARK: - The JavaScript trampoline

    /// What `thenFunction(of:in:)` found.
    private enum ThenLookup {

        /// `value` has no callable `then`, so it is a plain value.
        case notThenable

        /// `value` is a thenable, and this is its `then` function.
        case thenable(JSValue)

        /// Reading `value.then` threw — an extension-controlled getter.
        case threw(JSValue)

        /// The lookup could not be performed: no trampoline in this context,
        /// or a trampoline that answered something other than its contracted
        /// record. As with `CallOutcome.unavailable`, never conflated with
        /// "not a thenable" — that answer would resolve a promise with a value
        /// nothing ever produced.
        case unavailable
    }

    /// Reads `value.then` from inside the trampoline and reports what it found.
    ///
    /// The read has to be guarded for the same reason the callback call does:
    /// `then` on a `Proxy`, or a lazily-defined accessor, is extension code,
    /// and an exception from it would land in `ExtensionHost.pendingException`
    /// and be attributed to whatever the host happened to be doing.
    private static func thenFunction(of value: JSValue, in context: JSContext) -> ThenLookup {
        guard let lookup = helperFunction("thenOf", in: context) else { return .unavailable }
        let lookupArguments: [Any] = [value]
        switch outcome(of: lookup.call(withArguments: lookupArguments), in: context) {
        case .threw(let reason):
            return .threw(reason)
        case .unavailable:
            return .unavailable
        case .returned(let result):
            guard let result, !result.isNull, !result.isUndefined else { return .notThenable }
            return .thenable(result)
        }
    }

    /// Unpacks the `{ ok, value, error }` record the trampoline answers with,
    /// and refuses anything that is not that record.
    ///
    /// A record rather than an out-parameter because that is the only shape a
    /// JavaScript function can return two things in, and `ok` rather than
    /// "`error` is absent" because a callback is perfectly entitled to
    /// `throw undefined`.
    ///
    /// **The shape check is the security boundary, and it is here rather than
    /// at the property lookup, deliberately.** `sharedHelper(in:)` adopts
    /// whatever object it finds under the trampoline's global name, and an
    /// extension's own top-level code runs before the first command dispatch,
    /// so an extension can get there first and be adopted. No identity check
    /// fixes that — a JavaScript object cannot prove its provenance to
    /// JavaScript, and every test a liar would have to pass, a liar can fake.
    /// What can be bounded is the damage: the one thing a fake trampoline
    /// bought was an uncaught throw out of the API-level `call` below, which
    /// reaches `ExtensionHost`'s `exceptionHandler` and its `pendingException`
    /// — *host* state, shared with `activate()` and misattributed there, which
    /// is precisely the F3/F4 defect the JavaScript catch was introduced to
    /// close. A record that is not an object, or whose `ok` is absent or not a
    /// boolean, is therefore `.unavailable`: the dispatch fails, loudly, and
    /// an extension that pre-empted the global has broken only its own
    /// commands in its own context, which is its right.
    private static func outcome(of settled: JSValue?, in context: JSContext) -> CallOutcome {
        guard let settled, settled.isObject,
              let succeeded = settled.forProperty("ok"), succeeded.isBoolean else {
            logger.error(
                """
                The command dispatch trampoline in JavaScript context \
                '\(name(of: context), privacy: .public)' answered something other than its \
                contracted record; treating the dispatch as failed
                """)
            return .unavailable
        }
        guard succeeded.toBool() else {
            guard let reason = settled.forProperty("error") else { return .unavailable }
            return .threw(reason)
        }
        return .returned(settled.forProperty("value"))
    }

    /// The global the trampoline is cached under, in the `__` namespace the
    /// host already reserves for itself.
    private static nonisolated let helperGlobalName = "__vscodeAPITrampoline"

    /// The trampoline's source, evaluated at most once per `JSContext`.
    ///
    /// `Reflect.apply` and `Array.prototype.slice` are captured into the
    /// closure rather than resolved at call time, so a reassignment of either
    /// cannot change what the app believes a callback did.
    ///
    /// **That capture is weaker than the one `extension-runtime.js` makes, and
    /// the difference is when it happens.** That file captures its intrinsics
    /// while it is the only code that has ever run in the context; this is
    /// evaluated lazily, by `sharedHelper(in:)`, on the first call that needs
    /// it — the extension's first `registerCommand`, or its first dispatch if
    /// the app registered the command. Either way that is *after* the
    /// extension's module code has run. So an extension that writes
    /// `Reflect.apply = function () { throw new Error('x'); };` at its top
    /// level poisons this capture *before* it is taken, and every one of its
    /// own command callbacks then reports as having thrown. What the capture
    /// does cover is a reassignment made after the first dispatch, which is
    /// the case a long-lived extension can still stumble into by accident.
    /// The damage either way is confined to that extension's own commands in
    /// its own context (see `outcome(of:in:)` for why it stops there), which
    /// is why this is documented rather than defended against.
    ///
    /// Every risky step is inside a JavaScript `try`, including the caching
    /// itself, so evaluating this can never be the thing that writes to
    /// `ExtensionHost.pendingException`. A context hostile enough to break it
    /// answers `null`, and `call` refuses to invoke anything there.
    private static nonisolated let helperSource = """
    (function () {
        'use strict';
        try {
            var apply = Reflect.apply;
            var slice = Array.prototype.slice;
            var helper = {
                call: function (fn, thisArg) {
                    try {
                        return { ok: true, value: apply(fn, thisArg, apply(slice, arguments, [2])) };
                    } catch (error) {
                        return { ok: false, error: error };
                    }
                },
                thenOf: function (value) {
                    try {
                        if (value === null || value === undefined) {
                            return { ok: true, value: null };
                        }
                        var then = value.then;
                        return { ok: true, value: typeof then === 'function' ? then : null };
                    } catch (error) {
                        return { ok: false, error: error };
                    }
                }
            };
            try {
                Object.defineProperty(globalThis, '\(helperGlobalName)', {
                    value: helper,
                    writable: false,
                    enumerable: false,
                    configurable: false
                });
            } catch (ignored) {
                // Caching is an optimisation. The helper works without it.
            }
            return helper;
        } catch (error) {
            return null;
        }
    })()
    """

    /// The trampoline object for `context`, evaluating it the first time and
    /// reading it back from the context afterwards.
    ///
    /// **The cache lives on the context, not in Swift.** A Swift-side
    /// `[ObjectIdentifier: JSValue]` would be the obvious spelling and is a
    /// leak: a `JSValue` retains its `JSContext`, so every context this is ever
    /// called for would outlive its host forever. Stashed on `globalThis` it
    /// has exactly the lifetime it should — the context's — and costs a
    /// property lookup per call.
    ///
    /// Non-enumerable, non-writable and non-configurable, so it does not show
    /// up in `Object.keys(globalThis)` and cannot be replaced **once this code
    /// has installed it**.
    ///
    /// That last clause is the real guarantee, and it is narrower than it
    /// looks. This function adopts whatever object it finds under the name,
    /// and extension module code runs before the first command dispatch in an
    /// environment `extension-runtime.js` is explicit is not a sandbox — so an
    /// extension that defines the global first is adopted and the
    /// `defineProperty` below never runs. Nothing here can prevent that: a
    /// JavaScript object cannot prove its provenance to JavaScript. What is
    /// bounded instead is what a liar gains, and the answer is nothing outside
    /// its own context: `outcome(of:in:)` validates every record before
    /// believing it, so an extension that pre-empts this global is lying to
    /// its own dispatches and breaking its own commands.
    ///
    /// It is not withdrawn the way `__host` and `__extensionRuntime` are,
    /// because unlike those it is not a line back into the app: it is a pure
    /// JavaScript function holding no host reference, and an extension gains
    /// nothing from it that its own `try`/`catch` does not already give it.
    private static func sharedHelper(in context: JSContext) -> JSValue? {
        if let cached = context.objectForKeyedSubscript(helperGlobalName), cached.isObject {
            return cached
        }
        guard let created = context.evaluateScript(helperSource), created.isObject else {
            logger.error(
                """
                Could not install the vscode API trampoline in context \
                '\(name(of: context), privacy: .public)'; extension callbacks in it \
                will not be invoked
                """)
            return nil
        }
        return created
    }

    /// A `JSContext`'s name for a log line or an extension-facing message,
    /// with a stand-in for the unnamed case. `JSContext.name` arrives from
    /// Objective-C as an implicitly unwrapped `String!`, so the fallback is
    /// not decoration.
    private static func name(of context: JSContext) -> String {
        context.name ?? "<unnamed>"
    }

    private static func helperFunction(_ name: String, in context: JSContext) -> JSValue? {
        guard let helper = sharedHelper(in: context),
              let function = helper.forProperty(name),
              !function.isUndefined, !function.isNull else {
            return nil
        }
        return function
    }
}

extension VSCodeAPI: Loggable {

    /// The shared adaptor ceremony's own log destination — the same `Loggable`
    /// shape `CommandRegistry` and `ExtensionHost` use. It has exactly one
    /// caller today, `sharedHelper(in:)`, which reports the one failure here
    /// that no JavaScript caller can be told about.
    public static nonisolated let logger = makeLogger()
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
