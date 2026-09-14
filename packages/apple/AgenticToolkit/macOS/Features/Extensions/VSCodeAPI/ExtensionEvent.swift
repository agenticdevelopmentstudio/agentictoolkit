//
//  ExtensionEvent.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore
import OSLog
import AgenticToolkitCore

// MARK: - The window seam

/// Opens the fixed coalescing window `ExtensionEventEmitter` delivers at the
/// close of, so a test can close it on demand instead of sleeping.
///
/// **This exists to be replaced.** The production conformer below is a real
/// timer; a test hands in one that records the request and closes it when the
/// test says so. Without the seam, every window behaviour below — the fixed
/// (not trailing-edge) window, the second window opening after the first
/// closes, the absence of a leading edge — could only be observed by sleeping
/// for the real delay, and a test that sleeps measures the machine's load, not
/// the window.
///
/// One method, and it takes the delay rather than reading it from a property:
/// the emitter owns the delay (it is `extHostDiagnostics.ts:240`'s `delay: 50`
/// for diagnostics, and some other number for the next event), and a
/// conformer that stored its own would be a second place for it to disagree.
///
/// There is deliberately **no cancel**. Upstream never cancels: the whole
/// ruling in `event.ts:1605-1612` is that a `fire` inside an open window does
/// not touch the pending timer. A seam that offered cancellation would invite
/// the trailing-edge implementation this task exists to rule out.
@MainActor
public protocol ExtensionEventWindowScheduling: AnyObject {

    /// Calls `onClose` exactly once, `delay` seconds from now.
    func openWindow(closingAfter delay: TimeInterval, onClose: @escaping @MainActor () -> Void)
}

/// The production window: a real main-queue timer.
///
/// `DispatchQueue.main.asyncAfter` is fine *here* — the brief's "not a raw
/// `asyncAfter` you cannot control from a test" is about the emitter, and the
/// emitter reaches this only through `ExtensionEventWindowScheduling`. Behind
/// the seam, the simplest real timer is the right one.
@MainActor
public final class ExtensionEventTimerWindow: ExtensionEventWindowScheduling {

    public init() {}

    public func openWindow(closingAfter delay: TimeInterval, onClose: @escaping @MainActor () -> Void) {
        // `asyncAfter`'s block is `@Sendable` and `onClose` is not, so the
        // closure crosses in a box on the same terms as this directory's
        // other `@unchecked Sendable` boxes: nothing actually changes
        // isolation domain — the block runs on `DispatchQueue.main`, which is
        // the main actor — but the compiler cannot see that through
        // `asyncAfter`'s signature.
        let work = UncheckedMainActorWork(body: onClose)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { work.body() }
        }
    }
}

/// Carries a `@MainActor` closure through `asyncAfter`'s `@Sendable`
/// requirement — see `ExtensionEventTimerWindow.openWindow` for why this is
/// honest rather than a hole.
private struct UncheckedMainActorWork: @unchecked Sendable {
    let body: @MainActor () -> Void
}

// MARK: - The emitter

/// This host's port of VS Code's `DebounceEmitter` + `PauseableEmitter` +
/// `Event.map` stack (`event.ts:1544-1615`, pinned commit
/// `3addbda66f9e80c3ed1b943822ab823bb6747b02`), exposed to extensions as
/// `vscode.d.ts:1766`'s **callable** `Event<T>`.
///
/// `vscode.languages.onDidChangeDiagnostics` is its first caller; every later
/// event member in this host — `onDidChangeTextDocument`,
/// `onDidChangeActiveTextEditor`, `onDidChangeConfiguration` — is meant to be
/// another one, which is why `merge` and `map` are injected closures rather
/// than diagnostics logic inlined here. `map` is upstream's `Event.map`
/// (`extHostDiagnostics.ts:250`) kept as a separate stage rather than folded
/// into delivery.
///
/// ## The four upstream behaviours a reading of `vscode.d.ts` would miss
///
/// 1. **The window is fixed, not trailing-edge.** `event.ts:1606`'s
///    `if (!this._handle)` arms the timer only when none is pending, so a
///    later `fire` inside the window does *not* push the deadline out. Fire at
///    t=0, t=25 and t=49 with a 50 ms delay and all three are delivered
///    together at t≈50, not at t≈99. Despite the upstream class being named
///    `DebounceEmitter`, this is a fixed window opened by the first event.
/// 2. **No leading edge.** `event.ts:1607` calls `pause()` *before*
///    `super.fire(event)` (`event.ts:1613`), so by the time the first event
///    reaches `PauseableEmitter.fire` the emitter is already paused and the
///    event is queued like every other. Nothing is delivered at the start of
///    the window.
/// 3. **With zero listeners the event is dropped, not queued.**
///    `event.ts:1585`'s `if (this._size)` guards the queue push. An extension
///    that subscribes *after* a change has fired never hears about that
///    change — it does not receive a backlog.
/// 4. **A window that closes with an empty queue fires nothing.**
///    `event.ts:1568`'s `if (this._eventQueue.size > 0)` guards the merge, so
///    the listeners see no event at all rather than an empty payload. Combined
///    with (3), a window whose every event was dropped for want of a listener
///    produces nothing.
///
/// Note that (1) is armed unconditionally while (3) drops conditionally: the
/// window is opened by `DebounceEmitter.fire` before `PauseableEmitter.fire`
/// ever consults the listener count, so a zero-listener `fire` still opens a
/// window. `fire(_:)` below reproduces that order exactly, and it is what
/// makes a listener added *during* an open window receive the events fired
/// after it joined.
///
/// ## Isolation
///
/// `@MainActor` for the reason every adaptor in this directory is: `JSValue`
/// is not `Sendable`, and every listener runs on the thread that made the
/// call, which for this host is always the main actor.
///
/// ## Lifetime
///
/// Registrations hold their listener `JSValue` strongly, which holds its
/// `JSContext` strongly. That is not a cycle — a context reaches an adaptor
/// only through `VSCodeAPI.member`'s *weak* capture — but it does mean a torn
/// down extension's context outlives its host until its listeners go. Hence
/// `removeListeners(ownedBy:)`, which the subscribing adaptor's own
/// `dispose()` calls, on `MainThreadDiagnostics.ownedOwners`' and
/// `MainThreadLanguages.ownedHandles`' pattern: an emitter may be shared
/// across adaptors, so tearing one down must not take another's listeners
/// with it.
@MainActor
public final class ExtensionEventEmitter<Payload> {

    /// One live subscription.
    ///
    /// `thisArgs` is stored rather than bound at registration time the way
    /// `event.ts:1287`'s `callback = callback.bind(thisArgs)` binds it,
    /// because this host already has one way to call an extension's callback
    /// with a chosen `this` — `VSCodeAPI.call(_:thisArg:arguments:)`, whose
    /// JavaScript trampoline keeps a thrown exception out of the host's
    /// bookkeeping. Re-implementing `bind` here would give up that catch to
    /// gain nothing.
    private struct Registration {
        let identifier: Int
        let owner: ObjectIdentifier
        let listener: JSValue
        let thisArgs: JSValue?
    }

    /// The member's full path, `vscode.languages.onDidChangeDiagnostics`
    /// shaped — read back only in a refusal message and a log line, which is
    /// the one place an extension author can see which event refused them.
    private let path: String

    /// The window's width. `extHostDiagnostics.ts:240`'s `delay: 50` for
    /// diagnostics; every event picks its own.
    private let delay: TimeInterval

    /// The seam. **No default**, deliberately: a default is how a seam
    /// quietly stops being one — every test would keep compiling while
    /// silently reverting to the real timer.
    private let window: ExtensionEventWindowScheduling

    /// `event.ts:1571`'s `this._mergeFn(events)` — upstream's
    /// `merge: all => all.flat()` for diagnostics. One flat payload for the
    /// whole window.
    private let merge: ([Payload]) -> Payload

    /// `extHostDiagnostics.ts:250`'s `Event.map(…, ExtHostDiagnostics._mapper)`
    /// — the merged payload turned into the JavaScript value a listener
    /// receives. Takes the `JSContext` because the value must be built in the
    /// listener's own context.
    private let map: @MainActor (Payload, JSContext) -> JSValue?

    private var registrations: [Registration] = []
    private var nextIdentifier = 0

    /// `event.ts:1547`'s `_eventQueue`.
    private var queue: [Payload] = []

    /// `event.ts:1598`'s `_handle` — "a window is already open", not a timer
    /// handle, because this seam has nothing to cancel.
    private var windowIsOpen = false

    /// - Parameters:
    ///   - path: The member path, for refusals and logs.
    ///   - delay: The window's width in seconds.
    ///   - window: The window seam. Not defaulted — see the property's doc.
    ///   - merge: Collapses one window's queued payloads into one.
    ///   - map: Builds the JavaScript value a listener receives.
    public init(
        path: String,
        delay: TimeInterval,
        window: ExtensionEventWindowScheduling,
        merge: @escaping ([Payload]) -> Payload,
        map: @escaping @MainActor (Payload, JSContext) -> JSValue?
    ) {
        self.path = path
        self.delay = delay
        self.window = window
        self.merge = merge
        self.map = map
    }

    /// How many listeners are live — `event.ts:1585`'s `this._size`, exposed
    /// so a caller (and a test) can ask without reaching into storage.
    public var listenerCount: Int {
        registrations.count
    }

    // MARK: - Firing

    /// `DebounceEmitter.fire` (`event.ts:1605-1614`) and
    /// `PauseableEmitter.fire` (`event.ts:1584-1591`) in one method, in
    /// upstream's order: open the window first, *then* decide whether the
    /// event is worth queueing.
    public func fire(_ payload: Payload) {
        // event.ts:1606-1612 — armed only when no window is open. A later
        // fire inside the window does not extend it.
        if !windowIsOpen {
            windowIsOpen = true
            window.openWindow(closingAfter: delay) { [weak self] in
                self?.closeWindow()
            }
        }
        // event.ts:1585's `if (this._size)` — dropped, not queued, when
        // nobody is listening. Note this runs *after* the window opened,
        // exactly as upstream's `super.fire(event)` does.
        guard !registrations.isEmpty else { return }
        queue.append(payload)
    }

    /// `PauseableEmitter.resume`'s merge branch (`event.ts:1563-1574`).
    ///
    /// The window is marked closed and the queue emptied **before** any
    /// listener runs, mirroring upstream's `--this._isPaused === 0` and its
    /// `this._eventQueue.clear()`, both of which precede `super.fire`. That
    /// ordering is what makes a listener that throws — or one that fires the
    /// same emitter re-entrantly — leave a clean emitter behind rather than a
    /// permanently paused one.
    private func closeWindow() {
        windowIsOpen = false
        // event.ts:1568 — an empty queue delivers nothing at all, not an
        // empty payload.
        guard !queue.isEmpty else { return }
        let merged = merge(queue)
        queue.removeAll()
        deliver(merged)
    }

    /// `Emitter._deliverQueue` (`event.ts:1398-1404`) over a snapshot, with
    /// `Emitter._deliver`'s try/catch (`event.ts:1390-1394`).
    ///
    /// Two upstream details are reproduced rather than simplified away:
    ///
    /// - **A listener that throws does not stop the others.**
    ///   `event.ts:1391-1393` wraps the call and hands the exception to
    ///   `onUnexpectedError`, then `_deliverQueue`'s `while` continues. Here
    ///   `VSCodeAPI.call` returns `.threw` instead of letting the exception
    ///   reach the host, and the loop continues; the exception is logged,
    ///   which is this host's `onUnexpectedError`.
    /// - **A listener disposed mid-delivery is not called.**
    ///   `event.ts:1360` clears the slot (`listeners[index] = undefined;`)
    ///   and `event.ts:1380-1382` is where that is honoured — `_deliver`
    ///   opens with `if (!listener) { return; }`, unconditionally. The
    ///   snapshot below is a Swift array value, so removal cannot corrupt the
    ///   walk, but it *can* leave a disposed listener in the snapshot — hence
    ///   the liveness re-check.
    ///
    /// The mapped value is built once per distinct `JSContext` rather than
    /// once per listener: upstream hands every listener the same event object
    /// (one `super.fire(this._mergeFn(events))`), and two listeners in one
    /// context should see one object. Two listeners in *different* contexts
    /// cannot, because a `JSValue` belongs to its context — and an emitter is
    /// shared across extensions, so that case is real, not hypothetical.
    private func deliver(_ payload: Payload) {
        let snapshot = registrations
        var mappedByContext: [ObjectIdentifier: JSValue] = [:]
        for registration in snapshot {
            guard registrations.contains(where: { $0.identifier == registration.identifier }) else {
                continue
            }
            guard let context = registration.listener.context else { continue }
            let key = ObjectIdentifier(context)
            let value: JSValue
            if let cached = mappedByContext[key] {
                value = cached
            } else {
                guard let mapped = map(payload, context) else {
                    Self.logger.error(
                        """
                        \(self.path, privacy: .public) could not build its event value in context \
                        '\(VSCodeAPI.name(of: context), privacy: .public)'; this listener is skipped
                        """)
                    continue
                }
                mappedByContext[key] = mapped
                value = mapped
            }
            let outcome = VSCodeAPI.call(
                registration.listener, thisArg: registration.thisArgs,
                arguments: [value])
            switch outcome {
            case .returned:
                continue
            case .threw(let exception):
                Self.logger.error(
                    """
                    A \(self.path, privacy: .public) listener threw: \
                    \(exception.toString() ?? "<unprintable>", privacy: .public)
                    """)
            case .unavailable:
                Self.logger.error(
                    """
                    A \(self.path, privacy: .public) listener could not be invoked: \
                    \(VSCodeAPI.dispatchUnavailableMessage(for: context), privacy: .public)
                    """)
            }
        }
    }

    // MARK: - Subscribing

    /// The body of the callable `Event<T>` (`vscode.d.ts:1766`):
    /// `(listener, thisArgs?, disposables?) => Disposable`.
    ///
    /// Takes the already-read argument list rather than reading it itself, so
    /// the member wrapping it keeps `VSCodeAPI.member`'s one rule about
    /// reading `JSContext.currentArguments()` rather than declaring formal
    /// block parameters.
    ///
    /// Three behaviours, each measured:
    ///
    /// - **`thisArgs` is truthy-tested**, not merely non-`undefined`:
    ///   `event.ts:1286` is `if (thisArgs)`, so the `null` in the idiomatic
    ///   `onDidChangeDiagnostics(fn, null, context.subscriptions)` binds
    ///   nothing.
    /// - **The disposable is returned *and* pushed** onto a `disposables`
    ///   array argument — `event.ts:1973-1979`'s `addToDisposables` does
    ///   exactly `disposables.push(result)` for an array. Both effects, not
    ///   one. (Upstream also accepts a `DisposableStore`; this host has no
    ///   such type, so the array branch is the whole of it.)
    /// - **A non-callable listener is refused**, and refused by the only
    ///   test that actually means callable: `listener instanceof Function`,
    ///   spelled as `isInstance(of:)` against the context's own `Function`.
    ///   `isObject` would not do — it is true of `{}` — and a plain object
    ///   accepted here would register, hand back a real `Disposable`, and
    ///   then fail once per window from inside `deliver` instead.
    ///   This is a deliberate divergence: `event.ts:1264-1329` validates
    ///   nothing, so upstream stores a non-function and either throws from
    ///   `.bind` or throws a `TypeError` per window from inside its own
    ///   error handler, where the extension author never sees it. Refusing
    ///   here follows this directory's own precedent for a callback
    ///   argument, `MainThreadCommands.swift:138-141` — which that file's
    ///   own `:134-137` explains is safe to read as `typeof === 'function'`
    ///   here, because there is only ever one realm in this host. (That file
    ///   is untouched by this task, so the numbers hold at this commit too.)
    ///   Refusing turns a silent per-window failure into one synchronous
    ///   error at the call the author wrote.
    ///
    /// - Parameters:
    ///   - arguments: The call's arguments, from `VSCodeAPI.currentArguments()`.
    ///   - context: The calling context.
    ///   - owner: Whose subscription this is, for `removeListeners(ownedBy:)`.
    ///     Held only as an `ObjectIdentifier`, never strongly.
    /// - Returns: The `Disposable`, or `nil` with `context.exception` set.
    public func subscribe(
        arguments: [JSValue], in context: JSContext, owner: AnyObject
    ) -> JSValue? {
        // `listener instanceof Function`, which is `typeof listener ===
        // 'function'` for anything reachable from this context — there is
        // only ever one realm here, so the cross-realm gap between the two
        // checks does not apply. `MainThreadCommands.swift:130-141` is the
        // precedent.
        let functionConstructor = context.objectForKeyedSubscript("Function")
        guard let listener = arguments.first,
              let functionConstructor,
              listener.isInstance(of: functionConstructor) else {
            return VSCodeAPI.raise(
                "\(path) requires a listener function.", in: context)
        }

        let thisArgsArgument = arguments.count > 1 ? arguments[1] : nil
        let thisArgs = ExtensionEventEmitter.isTruthy(thisArgsArgument) ? thisArgsArgument : nil

        let identifier = nextIdentifier
        nextIdentifier += 1
        registrations.append(
            Registration(
                identifier: identifier, owner: ObjectIdentifier(owner),
                listener: listener, thisArgs: thisArgs))

        // `VSCodeAPI.disposable(in:onDispose:)` rather than a second
        // disposable shape, so the idempotence an extension is promised —
        // `dispose()` twice is one teardown — is the one guard this host
        // already has, not a new one that has to be right again.
        guard let disposable = VSCodeAPI.disposable(in: context, onDispose: { [weak self] in
            self?.registrations.removeAll { $0.identifier == identifier }
        }) else {
            registrations.removeAll { $0.identifier == identifier }
            return VSCodeAPI.raise(
                "\(path) could not create a Disposable in context '\(VSCodeAPI.name(of: context))'.",
                in: context)
        }

        // event.ts:1976-1978 — an array argument receives the disposable too.
        if arguments.count > 2 {
            let disposables = arguments[2]
            if disposables.isArray {
                disposables.invokeMethod("push", withArguments: [disposable])
            }
        }

        return disposable
    }

    /// Drops every listener registered with `owner`, leaving every other
    /// owner's alone — an emitter is shared, so a torn-down adaptor must not
    /// take its neighbours' subscriptions with it. The boundary
    /// `MainThreadDiagnostics.dispose()` and `MainThreadLanguages.dispose()`
    /// both already draw around a shared store.
    public func removeListeners(ownedBy owner: AnyObject) {
        let key = ObjectIdentifier(owner)
        registrations.removeAll { $0.owner == key }
    }

    // MARK: - Small helpers

    /// JavaScript truthiness, for `event.ts:1286`'s `if (thisArgs)`.
    ///
    /// `VSCodeAPI/` had exactly one named helper for this idea —
    /// `MainThreadDiagnostics.isFalsy(_:)` — so this is the second, and a
    /// second copy of the rule would be worse than a second caller of the
    /// first. `isFalsy` is promoted from `private` to `internal` for exactly
    /// this reuse, on `MainThreadWindow.installReadonlyGetter`'s own
    /// precedent for promoting rather than duplicating.
    private static func isTruthy(_ value: JSValue?) -> Bool {
        !MainThreadDiagnostics.isFalsy(value)
    }
}

extension ExtensionEventEmitter: Loggable {

    /// Computed, not stored: Swift forbids a static *stored* property in a
    /// generic type, and `Loggable` declares `logger` as a `get` requirement
    /// precisely so a type like this one can satisfy it.
    public static nonisolated var logger: Logger { makeLogger() }
}
