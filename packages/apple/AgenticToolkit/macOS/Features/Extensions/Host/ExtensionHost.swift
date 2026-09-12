//
//  ExtensionHost.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore
import OSLog

import AgenticToolkitCore

/// Runs one VS Code **web** extension's JavaScript in its own `JSContext`.
///
/// One host per extension, one context per host, and one `JSVirtualMachine`
/// shared by every host in the process. Contexts inside a single VM are torn
/// down independently and cost little; separate VMs would buy isolation between
/// extensions that already cannot reach each other — nothing crosses between
/// two contexts except through Swift, and Swift never carries a `JSValue` from
/// one to the other.
///
/// `@MainActor`, and not by accident. `JSContext` and `JSValue` are not
/// `Sendable`, every adaptor Stage 5 builds on top of this hangs off main-actor
/// components (the command registry, the document store, the window layout),
/// and a host that hopped executors would have to marshal JavaScript values
/// across them. The one thing that genuinely does not belong on the main thread
/// — reading a bundled extension's JavaScript off disk, which can be megabytes
/// — is the one thing `activate()` does off it.
///
/// What this host deliberately does *not* do is give the extension anything to
/// call. The `vscode` namespace it hands to `require('vscode')` is a wall of
/// recorded, throwing stubs (see `NotImplementedLedger` and
/// `Resources/extension-runtime.js`); stages 5.3 onward replace those one
/// member at a time. That is the point: an extension that reaches for an API
/// this build does not have fails loudly and by name, instead of activating
/// successfully and then doing nothing.
@MainActor
public final class ExtensionHost {

    // MARK: - State

    /// One host's position in its one-way trip from "nothing has happened" to
    /// "torn down".
    ///
    /// The order the cases are *evaluated* in is the load-bearing part, and it
    /// is documented on `activationState`, which is the only thing that builds
    /// one of these.
    public enum ActivationState: Sendable, Equatable {

        /// Why a host can never activate again. Both reasons describe the same
        /// physical situation — a module that has been evaluated into a runtime
        /// this host cannot un-run — and they are distinguished only so the
        /// refusal a caller gets can say which one happened.
        public enum TerminationReason: Sendable, Equatable {

            /// The task awaiting `activate()` was cancelled **after the module
            /// had been evaluated**. The extension's own `activate()` may still
            /// be running. A cancellation that lands before that — while the
            /// entry point is still being read off disk — abandons nothing and
            /// leaves the host `.neverActivated`; see `moduleEvaluated`.
            case cancelled

            /// `activate()` failed after the module was evaluated: the
            /// extension's code has run, and it did not finish activating.
            case failed
        }

        case neverActivated
        case activating
        case activated
        case terminal(TerminationReason)
        case disposed
    }

    // MARK: - Properties

    /// The extension this host runs, and the directory every path it declares
    /// resolves against.
    public let loadedExtension: LoadedExtension

    public var identifier: String { loadedExtension.identifier }

    /// Where unimplemented API members are recorded. Injected rather than owned
    /// outright so a caller running several extensions can give them all one
    /// ledger and hand the whole thing to a report; a caller with one extension
    /// gets a private one and never has to think about it.
    public let notImplementedLedger: NotImplementedLedger

    /// Every `console.*` call the extension makes, alongside the OSLog line it
    /// always produces. A host with no observer still logs; this is for a UI
    /// that wants to show the extension's own output, and for tests, which
    /// otherwise have no way to observe that the extension's code ran at all.
    public var onConsoleMessage: ((ExtensionConsoleMessage) -> Void)?

    /// Where this host is, as one value.
    ///
    /// Four rounds of fixes to this file were each a correct answer to the
    /// route that had just been demonstrated, and each left the *state* it led
    /// to reachable by another route, because the state had no name — only a
    /// scatter of booleans that each guard re-derived for itself. This is the
    /// name. Every guard in this file reads it, and stages 5.3 onward read it
    /// instead of re-deriving the precedence below from fields they cannot see.
    ///
    /// **The evaluation order is the contract**, and it is not the order the
    /// fields happen to be declared in:
    ///
    /// 1. `.disposed` — teardown outranks everything; it is the one state that
    ///    is genuinely final.
    /// 2. `.activated` — **before** `.terminal`, deliberately. A cancellation
    ///    can land while an activation is already succeeding, so
    ///    `terminationReason` and a successful activation are simultaneously
    ///    true (measured, at six different timings). A host that did activate
    ///    must not be reported as cancelled, which is exactly why
    ///    `terminationReason` is not exposed as a standalone `isCancelled`:
    ///    it is only meaningful once teardown and success have been ruled out.
    /// 3. `.terminal` — a cancelled or failed activation. Both abandoned a
    ///    runtime that nothing can un-run; see `terminationReason`.
    /// 4. `.activating` — a call is inside `activate()`.
    /// 5. `.neverActivated` — nothing has happened yet.
    ///
    /// `.terminal` outranking `.activating` is deliberate too, and it is
    /// visible to exactly one caller: `markTerminal(.failed)` runs inside
    /// `performActivation`'s `catch`, while `activate()`'s
    /// `defer { activationTask = nil }` runs several main-actor jobs later,
    /// when the awaiting caller resumes. A *second* `activate()` arriving in
    /// that window is refused with `activationAlreadyFailed` instead of
    /// joining the still-live task and being handed the original
    /// `activationThrew` message. Both answers are refusals, and this one is
    /// the answer every caller arriving a microsecond later also gets, which
    /// is worth more than the diagnostic: a state whose name changes with the
    /// scheduler is the defect this enum exists to end. The caller who
    /// actually made the failing call still receives the real error.
    public var activationState: ActivationState {
        if disposed { return .disposed }
        if activationSucceeded { return .activated }
        if let terminationReason { return .terminal(terminationReason) }
        if activationTask != nil { return .activating }
        return .neverActivated
    }

    /// Whether the extension's `activate()` ran to completion.
    ///
    /// Stays true through `dispose()`: it records what happened, not what the
    /// host can still do. `activationState` is the one that becomes
    /// `.disposed`.
    public var isActivated: Bool { activationSucceeded }

    /// Whether `dispose()` has run. The same answer as
    /// `activationState == .disposed`, spelled the way call sites ask it.
    public var isDisposed: Bool { disposed }

    private var activationSucceeded = false
    private var disposed = false

    /// One VM for the whole process. `JSVirtualMachine` is not `Sendable`; this
    /// static is main-actor isolated with the rest of the type, which is the
    /// same confinement every host that uses it already has.
    private static let virtualMachine = JSVirtualMachine()

    /// Read once and kept: the shim is a fixed resource in this framework's
    /// bundle, and re-reading it per extension is disk work with one possible
    /// answer.
    private static var cachedRuntimeSource: String?

    private var context: JSContext?

    /// The live `JSContext`, or `nil` once `dispose()` has released it.
    ///
    /// Internal, and it exists for one reason: `dispose()` dropping the context
    /// is correct-but-unobservable from outside. Every behaviour a test can see
    /// after teardown — no callbacks, no timers, refused re-activation — is
    /// already guaranteed by `isDisposed` alone, so a `dispose()` that leaked
    /// the whole JavaScript heap for the life of the host would pass every one
    /// of them. A `weak` reference to this is the only way to state that the
    /// context is actually gone, and the context is the largest thing this host
    /// owns.
    var javaScriptContext: JSContext? { context }

    /// `__extensionRuntime` from the shim, captured before its global is
    /// deleted. Holding it here rather than looking it up by name is what lets
    /// the globals go away: the extension's code cannot reach an object it has
    /// no name for, and this host still can.
    private var runtime: JSValue?

    /// Real implementations installed over the shim's stubs, in the order they
    /// were declared.
    ///
    /// Kept rather than applied and forgotten because a caller may define
    /// members *before* `activate()` — that is the normal order, since the
    /// adaptor that owns a member is wired at construction time and the
    /// extension is activated later. The list is replayed onto the runtime as
    /// soon as one exists.
    ///
    /// A definition the shim refuses is taken back out again
    /// (`applyOrWithdraw`). It has to be: the replay happens from inside
    /// `activate()`, the refusal is not terminal — nothing ran — and a list
    /// that kept the bad entry would fail every future `activate()` in exactly
    /// the same way, leaving a host that reports `.neverActivated` and can
    /// never activate. There is no API to withdraw a queued definition, so the
    /// one that cannot work withdraws itself.
    private var vscodeMemberDefinitions: [VSCodeMemberDefinition] = []

    /// The in-flight `activate()`, so two concurrent calls are one activation.
    ///
    /// `activate()` was synchronous-enough to guard with `isActivated` alone
    /// when it did not await anything the extension controlled. It now awaits
    /// `activate()`'s own promise, which an extension can keep pending for as
    /// long as it likes, and a second caller arriving inside that window would
    /// otherwise evaluate the module a second time.
    private var activationTask: Task<Void, Error>?

    /// Whether this host has evaluated its extension's module.
    ///
    /// The invariant `terminationReason` describes, as a field rather than as
    /// prose: it is written in exactly one place — inside `evaluateModule`,
    /// on the line before the shim's `run` call — and every route into a
    /// terminal state reads it rather than each deciding for itself where the
    /// boundary is.
    ///
    /// That line is the boundary because it is the only line that runs the
    /// extension's code. *Compiling* the module does not, and `evaluateModule`
    /// throws three ways above the assignment with zero extension statements
    /// executed (measured): no `JSContext`, a source that will not parse, and
    /// a wrapper that did not compile to a function. So
    /// `performActivation`'s `catch` tests this field rather than assuming
    /// its `do` block implies it — it does not. It once did, and a host whose
    /// extension file merely would not parse was told its code had already
    /// run, refused a retry, and refused `defineVSCodeMember` besides.
    ///
    /// `endActivation` reads it from the other side and for the same reason:
    /// a cancellation lands wherever the caller happens to cancel, with no
    /// `do` block to sit inside at all.
    ///
    /// Never cleared. A host that evaluated a module has evaluated it; a
    /// retry is what this exists to refuse.
    private var moduleEvaluated = false

    /// Why this host can never activate again, or `nil` while it still can.
    ///
    /// The property that makes a host terminal is not cancellation. It is that
    /// the module has been **evaluated** (`moduleEvaluated`): from that instant
    /// the extension's code has run, its top level has registered whatever it
    /// registers and started whatever timers it starts, and nothing can reach
    /// into JavaScript and un-run it. Every failure at or after the shim's
    /// `run` call inside `evaluateModule` lands there — a sync throw, a
    /// rejected promise, a throwing `.then` getter, a top-level throw — and so
    /// does a cancellation that arrives once the module is running. They are
    /// one state, so they set one field.
    ///
    /// Nothing that arrives *before* that instant sets it, cancellation and
    /// failure alike. Reading the entry point off disk is a real suspension
    /// point, a bundled web extension is routinely megabytes, and the caller
    /// who wraps `activate()` in a timeout — the reason it is
    /// cancellation-responsive at all — is asking to stop a slow read, not to
    /// spend the host. A module that will not *compile* is the same story one
    /// step later: the compile throws with the author's own file and line
    /// attached, which is the most valuable thing this host produces for that
    /// mistake, and spending the host would replace it with "this host is
    /// spent". Nothing ran, so nothing is abandoned, and the host stays
    /// retryable.
    ///
    /// A retry would therefore evaluate the module a second time into a
    /// *second* runtime: `context` overwritten while the abandoned instance
    /// still ran in the old one, and `runningTimerCount` counting both
    /// instances, so the teardown invariant would stop meaning one host-worth
    /// of timers. Measured, both of them.
    ///
    /// `dispose()` is what follows. It is the operation that really does undo a
    /// runtime, and it is already safe to call on a host in this state.
    private var terminationReason: ActivationState.TerminationReason?

    /// The raw reason, before `activationState`'s precedence hides it.
    ///
    /// Internal, and it exists for exactly one test. `activationState` reports
    /// `.activated` for a host that both activated *and* had a cancellation
    /// land on it, which is correct and is the whole point of the ordering — but
    /// it also makes that state indistinguishable from an ordinary activation
    /// from outside. A test that cannot see this field cannot tell whether it
    /// built the state it meant to build, and would pass just as happily
    /// against a run where the cancellation never landed at all.
    var recordedTerminationReason: ActivationState.TerminationReason? { terminationReason }

    /// Resumes the suspended `activate()`. Taken-and-nilled by
    /// `finishActivation`, so activation ends exactly once however it ends:
    /// the shim's callback, a JavaScript exception thrown before that callback
    /// could fire, or `dispose()`.
    private var activationContinuation: ((Result<Void, ExtensionHostError>) -> Void)?

    /// The clocks behind the shim's `setTimeout`/`setInterval`. `Task`, not
    /// `Timer` or a dispatch source, because cancellation is then the language
    /// primitive rather than a bookkeeping convention — `dispose()` cancels
    /// every one of these, and a cancelled task cannot reach JavaScript again.
    private var timerTasks: [Int32: Task<Void, Never>] = [:]

    /// Started and not yet finished. Kept separately from `timerTasks` because
    /// that dictionary says which timers are *addressable*, and teardown empties
    /// it in one line whether or not the tasks behind it actually stopped.
    private var runningTimerTasks = 0

    /// How many of the extension's clocks are still turning.
    ///
    /// This exists because teardown has two independent defences and only one
    /// of them is visible from outside. A disposed host's timer callback cannot
    /// run in any case — the task re-checks `isDisposed` when it wakes, and
    /// `fireTimer` finds no runtime — so a test that only watched for the
    /// callback would pass just as happily against a `dispose()` that cancelled
    /// nothing. What cancellation actually buys is that the task stops *now*:
    /// without it, `setInterval(fn, 3600000)` leaves a task asleep for the rest
    /// of that hour, holding this host weakly and waking once more to decide it
    /// has nothing to do. Mutation testing found exactly that hole, and this is
    /// what closes it.
    ///
    /// Internal, not public: it is a teardown assertion and a debugging read,
    /// and nothing outside this framework has a use for it yet.
    var runningTimerCount: Int { runningTimerTasks }

    /// Set by the context's `exceptionHandler`, read and cleared around every
    /// evaluation. A `JSContext` reports an uncaught exception by calling the
    /// handler and returning a nil-ish value, so `try` alone catches nothing:
    /// without this, an extension whose top-level code throws would look
    /// exactly like one that loaded cleanly and exported nothing.
    private var pendingException: String?

    // MARK: - Initialization

    public init(
        loadedExtension: LoadedExtension,
        notImplementedLedger: NotImplementedLedger = NotImplementedLedger()
    ) {
        self.loadedExtension = loadedExtension
        self.notImplementedLedger = notImplementedLedger
    }

    // MARK: - Activation

    /// Resolves the entry point, evaluates the extension's code in a fresh
    /// context, and calls its exported `activate` if it has one.
    ///
    /// **Returns only once `activate()` has finished.** VS Code declares
    /// `activate(context): any | Thenable<any>`, and `export async function
    /// activate()` is what most real extensions ship: a host that returned as
    /// soon as the call did would report an extension activated before it had
    /// registered anything, and the command a palette asks for a moment later
    /// would not exist yet. A rejected promise fails activation with its reason,
    /// for the same reason — JavaScriptCore routes an unhandled rejection
    /// nowhere the exception handler can see it, so an async `activate` that
    /// threw would otherwise be indistinguishable from one that succeeded.
    ///
    /// An extension whose `activate()` promise never settles suspends this call
    /// for as long as it stays unsettled. There is no timeout, because there is
    /// no honest number: a real extension may legitimately await a network
    /// round trip during activation, and a host that gave up at *n* seconds
    /// would be reporting a failure that did not happen. There are two escapes
    /// instead. `dispose()` ends it and tears the host down; **cancelling the
    /// calling task ends it**, throwing `activationCancelled` — cancellation
    /// is the first thing a Swift caller reaches for, and an `activate()` that
    /// ignored it would turn an ordinary timeout-and-give-up into a hang.
    ///
    /// **An activation that runs the extension's code and does not succeed is
    /// terminal, and `dispose()` is what follows it.** Cancellation ends the
    /// call, not the activation: the extension's promise is still pending
    /// inside a runtime this host cannot un-run. A *failure* — a throw from
    /// `activate()`, a rejected promise, a throw from the module's top level —
    /// is the same situation arrived at by a different route, because by then
    /// the module has been evaluated and its top level has already run. Either
    /// way a later `activate()` refuses, naming which of the two happened,
    /// rather than evaluating the module into a second runtime beside the
    /// abandoned one. `activationState` reports it as `.terminal`.
    ///
    /// What does *not* spend the host is an attempt that never reached the
    /// extension's code: a cancellation that lands while the entry point is
    /// still being read, an unloadable shim, a namespace an adaptor spelled
    /// wrong, a module that will not *compile*. Nothing ran, so there is
    /// nothing to abandon, and the host stays `.neverActivated` and can be
    /// activated again. The last of those is the ordinary one — a truncated
    /// download, a bad minifier run, a file hand-edited during development —
    /// and it is the case where a retry can genuinely differ, because the
    /// file can be corrected under a host that is still willing to run it.
    ///
    /// Calling twice is a no-op, and two concurrent calls are one activation.
    /// VS Code activates an extension once, callers re-emit activation events
    /// routinely, and re-evaluating the module would leave two sets of
    /// registrations behind that one `dispose()` cannot undo (`idempotency`).
    /// The corollary is that cancellation is shared too: there is one
    /// activation with one outcome, so a second caller who cancels ends it for
    /// the first as well.
    ///
    /// - Throws: `ExtensionHostError.activationCancelled` if the calling task
    ///   is cancelled, in place of `CancellationError` — every error this host
    ///   raises names the extension, because a failure reaches the user
    ///   through a list of extensions. The same error, and
    ///   `ExtensionHostError.activationAlreadyFailed` after a failure, for a
    ///   later call on a host that is already terminal.
    public func activate() async throws {
        // One read, and the precedence lives in `activationState` rather than
        // in a ladder of guards each answering for a narrower machine than the
        // one that exists. That ladder is what produced four rounds of the same
        // defect: every widening of the state space left the older guards
        // answering the older question.
        switch activationState {
        case .disposed:
            throw ExtensionHostError.hostDisposed(identifier: identifier)
        case .activated:
            return
        case let .terminal(reason):
            throw Self.terminalRefusal(reason, identifier: identifier)
        case .activating, .neverActivated:
            break
        }

        if let activationTask {
            try await awaitActivation(activationTask)
            return
        }

        let task = Task { @MainActor in try await self.performActivation() }
        activationTask = task
        defer { activationTask = nil }
        try await awaitActivation(task)
    }

    /// Awaits the one in-flight activation, and makes cancelling *this* call
    /// actually end it.
    ///
    /// `performActivation` runs in an unstructured task, and `task.value`
    /// forwards nothing: without this, a caller who wrapped `activate()` in a
    /// cancellable task would cancel only their own wrapper while the
    /// activation ran on — forever, for a promise that never settles.
    private func awaitActivation(_ task: Task<Void, Error>) async throws {
        // Everything the handler has to touch is main-actor state, and the
        // handler itself runs on whatever executor cancelled — so it hops, and
        // the hop is also what makes the capture legal. A plain `@Sendable`
        // closure may not capture this host; a `@Sendable @MainActor` one may,
        // because it can only ever run where the host's state already lives,
        // and a closure *value* is `Sendable` even when what it closes over is
        // not.
        let endActivation: @Sendable @MainActor () -> Void = { [weak self] in
            // A cancellation that arrives as the activation is already ending
            // must not reach the *next* one: by the time this hop runs, the
            // owner's `defer` may have cleared the task it belongs to.
            guard let self, self.activationTask == task else { return }
            // Terminal only if there is something to abandon. A cancellation
            // that lands while the entry point is still being read has no
            // context and no runtime behind it, and spending the host for it
            // would refuse both a retry *and* every later
            // `defineVSCodeMember`, over a file that was merely slow.
            if self.moduleEvaluated { self.markTerminal(.cancelled) }
            self.finishActivation(.failure(.activationCancelled(identifier: self.identifier)))
        }

        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            // Both halves are load-bearing, because there are two places an
            // activation can be when cancellation lands. `cancel()` reaches
            // the one still reading the entry point off disk, which has no
            // continuation to resume yet and is stopped by the check in
            // `performActivation`; `endActivation` reaches the one suspended
            // on `activate()`'s promise, which a `CheckedContinuation` will
            // never notice cancellation from on its own.
            task.cancel()
            Task { @MainActor in endActivation() }
        }
    }

    private func performActivation() async throws {
        let entryPoint = try resolveEntryPoint()
        let source = try await Self.readSource(at: entryPoint, identifier: identifier)
        // Read here rather than where it is used, which is the difference
        // between adding a suspension point the guards below already cover and
        // opening a second one underneath them — between `self.context =
        // context` and the module evaluation, where a `dispose()` would leave
        // this activation installing a shim into a context the host has already
        // let go of.
        let runtimeSource = try await Self.runtimeSource(identifier: identifier)

        // Reading the sources is the only suspension point before any
        // JavaScript exists, so it is the one place a `dispose()` can land
        // unnoticed.
        guard !isDisposed else {
            throw ExtensionHostError.hostDisposed(identifier: identifier)
        }

        // And the one place a cancellation can, for the same reason: past this
        // line there is a context and a running module, and stopping is
        // `dispose()`'s job rather than a `return`.
        guard !Task.isCancelled else {
            throw ExtensionHostError.activationCancelled(identifier: identifier)
        }

        let context = try makeContext()
        self.context = context

        guard let runtime = try installRuntime(runtimeSource: runtimeSource, into: context) else {
            throw ExtensionHostError.runtimeUnavailable(identifier: identifier)
        }
        self.runtime = runtime

        // The boundary is `moduleEvaluated`, and it is *not* this line: it is
        // the shim's `run` call inside `evaluateModule`, the one call that
        // runs the extension's own code. Past it a failure is not a failure to
        // *start*: it is a module that has been evaluated, whose top level has
        // already registered whatever it registers and started whatever timers
        // it starts. That is the same abandoned state a cancellation produces
        // and it is reached far more often — a sync throw, a rejected promise,
        // a throwing `.then` getter, a top-level throw — so it is marked the
        // same way rather than left as the one route with no guard over it.
        //
        // The `catch` below and `endActivation`'s cancellation are the two
        // writers of `terminationReason`, and they agree because they read one
        // predicate. The `catch` tests it rather than inferring it from the
        // `do` block: `evaluateModule` throws three ways with nothing
        // executed, and the commonest of them is a syntax error in the
        // extension's own file.
        //
        // Everything before that boundary is deliberately not terminal: no
        // extension code has run yet, so a retry orphans one `JSContext` and
        // nothing inside it. Measured — evaluating the shim alone makes no
        // call on the host block table, and neither does `defineMember`,
        // valid or invalid, nor compiling the module — and that context is
        // released on the next `self.context = context`. A shim that will not
        // load or a namespace an adaptor spelled wrong fails the same way on
        // every attempt, and refusing the second attempt would only hide the
        // reason behind a different error; a file that will not parse is the
        // case where the retry can actually differ, once the file is fixed.
        do {
            let exports = try evaluateModule(runtime: runtime, source: source, entryPoint: entryPoint)
            try await callActivate(on: exports, runtime: runtime)
        } catch {
            if moduleEvaluated { markTerminal(.failed) }
            throw error
        }
        activationSucceeded = true
    }

    /// Records why this host became terminal, keeping the *first* reason.
    ///
    /// Both routes into the state arrive at once when a cancellation is what
    /// caused the failure: `endActivation` names the cancellation and the throw
    /// it produced then leaves `performActivation`. The throw is a consequence
    /// of the cancellation, not a second reason for it, and the caller who
    /// cancelled should be told what they did.
    private func markTerminal(_ reason: ActivationState.TerminationReason) {
        guard terminationReason == nil else { return }
        terminationReason = reason
    }

    /// What a terminal host refuses with. One mapping, so `activate()` and
    /// `defineVSCodeMember` cannot drift into refusing the same state with
    /// different words.
    private static func terminalRefusal(
        _ reason: ActivationState.TerminationReason,
        identifier: String
    ) -> ExtensionHostError {
        switch reason {
        case .cancelled:
            return .activationCancelled(identifier: identifier)
        case .failed:
            return .activationAlreadyFailed(identifier: identifier)
        }
    }

    // MARK: - The 5.3-5.7 seam

    /// Installs a real implementation over one of the shim's throwing stubs.
    ///
    /// This is the seam stages 5.3 through 5.7 each register through, and the
    /// reason none of them has to edit `extension-runtime.js`: the shim retains
    /// every namespace's member table, and `defineMember` writes into the table
    /// the namespace proxy already reads. A member defined here stops throwing,
    /// stops being recorded as unimplemented, and leaves its siblings exactly as
    /// they were.
    ///
    /// `implementation` is passed to JavaScriptCore as-is, so the useful shapes
    /// are a `@convention(block)` closure, a `JSValue`, or any bridgeable value
    /// — `vscode.env.appName` is a string, and most absent members are values
    /// rather than functions.
    ///
    /// Callable before or after `activate()`. Before is the normal case, and
    /// definitions made then are applied the moment the runtime exists.
    ///
    /// `fileID` and `line` are the call's own, and they are the answer to
    /// *when* the throw below happens. The shim owns the list of namespaces
    /// that exist, so a namespace can only be checked against it once a
    /// runtime is running; before `activate()` — again, the normal case —
    /// there is nothing to check against, and the refusal arrives later, from
    /// inside `activate()`, where it would otherwise read as a failed
    /// activation of the *extension*. Carrying the origin means the error
    /// still names the adaptor's line however late it is raised. Copying the
    /// shim's namespace list into Swift would report it earlier and would be a
    /// second source of truth for something one file already owns; a drifting
    /// copy is worse than a late error.
    ///
    /// - Throws: `ExtensionHostError.hostDisposed` if the host has been torn
    ///   down — a definition appended then would go onto a list nothing will
    ///   ever replay — and `activationCancelled` or `activationAlreadyFailed`
    ///   if the host is terminal, for the stronger version of the same reason:
    ///   the list will never be replayed *and* the runtime it would be applied
    ///   to belongs to an abandoned activation.
    ///   `ExtensionHostError.vscodeMemberNotDefinable` if the
    ///   namespace is not one the shim knows, which is a programming error in
    ///   the adaptor: immediately when the host is already running, and
    ///   otherwise from the `activate()` that first installs a runtime. A
    ///   definition refused that way is withdrawn rather than left queued, so
    ///   the host is still activatable and the adaptor's other members are
    ///   untouched; correcting the spelling means calling this again.
    public func defineVSCodeMember(
        namespacePath: String,
        name: String,
        implementation: Any,
        fileID: String = #fileID,
        line: Int = #line
    ) throws {
        // The same read `activate()` makes, for the same reason: this guard
        // used to ask "is it disposed?", which stopped being the whole question
        // the moment a host could be terminal without being torn down. On a
        // terminal host the call did not merely queue a definition nothing
        // would replay — it *installed* the implementation into the abandoned
        // runtime, where the abandoned extension's still-running `setInterval`
        // picked it up on the next tick and began calling a real adaptor. An
        // extension the app has decided it is not running must not be handed a
        // live implementation. Measured.
        switch activationState {
        case .disposed:
            throw ExtensionHostError.hostDisposed(identifier: identifier)
        case let .terminal(reason):
            throw Self.terminalRefusal(reason, identifier: identifier)
        case .neverActivated, .activating, .activated:
            break
        }
        let definition = VSCodeMemberDefinition(
            namespacePath: namespacePath,
            name: name,
            implementation: implementation,
            origin: "\(fileID):\(line)")
        vscodeMemberDefinitions.append(definition)
        if let runtime {
            try applyOrWithdraw(at: vscodeMemberDefinitions.count - 1, to: runtime)
        }
    }

    /// Applies the queued definition at `index`, and takes it back off the
    /// queue if the shim refuses it.
    ///
    /// One function for both call sites — this one and `installRuntime`'s
    /// replay — because they are one rule: a definition the shim will not
    /// accept is a definition no future activation should replay. The caller
    /// still gets the full `vscodeMemberNotDefinable`, naming the namespace,
    /// the member and the adaptor's `file:line`, so nothing is swallowed;
    /// what is removed is only the entry that would raise it again, forever,
    /// on a host that is otherwise perfectly able to activate.
    ///
    /// The runtime is passed rather than read from `self`, because the replay
    /// runs inside `installRuntime`, before `performActivation` has adopted
    /// the runtime it is building.
    ///
    /// And it is logged, because withdrawing is the one event here that
    /// changes what a *later*, apparently clean activation contains. The
    /// adaptor's typo fails one `activate()` loudly and is then gone from the
    /// queue; the next `activate()` succeeds with that member left as the
    /// shim's not-implemented stub, and when the extension reaches for it the
    /// host records it against the *extension*, in the ledger task 5.8
    /// reports. That entry is a misattribution — the member is implemented,
    /// and the app spelled its namespace wrong — so the log line carries the
    /// same three facts the thrown error does, and the adaptor's bug stays
    /// findable after the throw has been handled and scrolled past. Logged
    /// here rather than at either call site, for the reason this function
    /// exists at all: two copies of one rule drift.
    private func applyOrWithdraw(at index: Int, to runtime: JSValue) throws {
        do {
            try apply(vscodeMemberDefinitions[index], to: runtime)
        } catch {
            let withdrawn = vscodeMemberDefinitions.remove(at: index)
            logger.error(
                """
                Extension '\(self.identifier, privacy: .public)' withdrew the definition of \
                '\(withdrawn.name, privacy: .public)' on '\(withdrawn.namespacePath, privacy: .public)', \
                declared at \(withdrawn.origin, privacy: .public): the shim refused it, so that member \
                stays a not-implemented stub on every later activation
                """)
            throw error
        }
    }

    private struct VSCodeMemberDefinition {
        let namespacePath: String
        let name: String
        let implementation: Any
        /// Where `defineVSCodeMember` was called, `file:line`.
        let origin: String
    }

    private func apply(_ definition: VSCodeMemberDefinition, to runtime: JSValue) throws {
        pendingException = nil
        runtime.invokeMethod(
            "defineMember",
            withArguments: [definition.namespacePath, definition.name, definition.implementation])
        if let message = pendingException {
            pendingException = nil
            throw ExtensionHostError.vscodeMemberNotDefinable(
                identifier: identifier,
                namespacePath: definition.namespacePath,
                name: definition.name,
                // The shim's complaint, then where the definition came from.
                // This is routinely thrown from `activate()`, long after the
                // call that is actually wrong.
                message: "\(message) Defined at \(definition.origin)."
            )
        }
    }

    /// Releases the context, cancels every timer the extension scheduled, and
    /// drops the host's handle on the runtime object.
    ///
    /// Deliberately does *not* call the extension's `deactivate`. Teardown's
    /// contract here is that nothing can call back into the app afterwards, and
    /// running extension JavaScript as the last act of teardown is the opposite
    /// of that. There is also nothing yet for an extension to clean up — every
    /// `vscode` member that would let it acquire a resource is a stub — so the
    /// callback would be ceremony with a failure mode.
    ///
    /// Safe to call more than once, and safe to call on a host that never
    /// activated.
    ///
    /// **Calling it is mandatory**, and not because `deinit` cannot cancel the
    /// timers — it can, including a repeating one, since `scheduleTimer`'s task
    /// captures the host weakly and so nothing a live `setInterval` holds keeps
    /// this object alive. What `deinit` cannot do is happen *at a known time*.
    /// This is synchronous and immediate; an `isolated deinit` hops to the main
    /// actor and runs whenever the last release happens to land, which for a
    /// host still referenced by a view model or an in-flight task is some later
    /// turn of the run loop or never. And only this clears `onConsoleMessage`
    /// and releases the context, which is the largest thing the host owns.
    /// Teardown is an act, not a consequence of going out of scope.
    public func dispose() {
        disposed = true

        for task in timerTasks.values {
            task.cancel()
        }
        timerTasks.removeAll()

        // A suspended `activate()` has to be released, and this is the only
        // thing that releases it: an extension's `activate()` promise may never
        // settle, and there is no timeout to fall back on. Teardown is the
        // escape.
        finishActivation(.failure(.hostDisposed(identifier: identifier)))

        // Blocks installed into the context capture this host weakly, so there
        // is no cycle to break — but the handler is cleared anyway, because a
        // context torn down mid-evaluation would otherwise still have a route
        // to `pendingException` on a host that is no longer listening.
        context?.exceptionHandler = nil
        runtime = nil
        context = nil

        // The observer outlives the host in the direction that matters: it is
        // supplied by a UI that keeps a strong reference to whatever it closes
        // over, and a disposed host holding it would keep that alive for as
        // long as the host itself is held. There is also nothing left to report.
        onConsoleMessage = nil
    }

    /// The net under `dispose()`, for the host that was dropped without one.
    ///
    /// It catches every timer, repeating included: `scheduleTimer` builds its
    /// task with `[weak self]`, so the host holds the tasks and no task holds
    /// the host, and a host with a live `setInterval` deallocates like any
    /// other. What it does not catch is *when* — see `dispose()` — and it does
    /// not catch the host dropped **while an activation is in flight** at all:
    /// `activationTask` is an unstructured `Task` that strongly captures the
    /// host, and the host holds `activationTask`, so a host abandoned on an
    /// activation that never settles never deallocates and never reaches here.
    /// That is precisely what `dispose()` being mandatory is for. Measured.
    ///
    /// The case it does catch is real: a host whose `activate()` threw, dropped
    /// by a caller that never learned it had timers to cancel, would otherwise
    /// leave a `setTimeout(fn, 3600000)` task asleep for the rest of the hour.
    ///
    /// `isolated deinit` because everything it touches is main-actor state.
    isolated deinit {
        for task in timerTasks.values {
            task.cancel()
        }
    }

    // MARK: - Entry point

    /// The file this extension's code lives in, proven to be inside the
    /// extension's own directory.
    ///
    /// Only `browser` is honoured. `main` is Node's entry point and this host
    /// has no Node: a Node extension refused with a generic "could not load"
    /// is the single most likely confusion this feature can produce, so it gets
    /// its own error that says which runtime it needed and which one exists.
    private func resolveEntryPoint() throws -> URL {
        let manifest = loadedExtension.manifest

        guard let browser = manifest.browser else {
            if let main = manifest.main {
                throw ExtensionHostError.requiresNodeRuntime(identifier: identifier, declaredMain: main)
            }
            throw ExtensionHostError.noEntryPoint(identifier: identifier)
        }

        // The base re-making, the symlink/`..` normalization of both sides and
        // the component-wise containment check all live in
        // `ExtensionResourcePath` now: the snippets, themes and theme-`include`
        // points resolve extension-declared paths under exactly the same rule,
        // and three of the four were missing the escape half of it.
        //
        // The error is re-thrown as this host's own rather than let through,
        // because the host's is the one that names *which* extension failed —
        // a path resolver has no identifier to report.
        do {
            return try ExtensionResourcePath.resolve(browser, inside: loadedExtension.directory)
        } catch let error as ExtensionResourcePathError {
            switch error {
            case .escapesExtensionDirectory(let declared, let resolved):
                throw ExtensionHostError.entryPointEscapesExtensionDirectory(
                    identifier: identifier,
                    declared: declared,
                    resolved: resolved
                )
            }
        }
    }

    /// Reads the entry point off the main thread. A bundled web extension is
    /// one concatenated file and routinely megabytes; the project's standing
    /// rule is that nothing lengthy blocks the main thread, and this is the
    /// only part of activation that can honour it.
    private static func readSource(at url: URL, identifier: String) async throws -> String {
        do {
            return try await Task.detached(priority: .userInitiated) {
                try String(contentsOf: url, encoding: .utf8)
            }.value
        } catch {
            throw ExtensionHostError.entryPointUnreadable(
                identifier: identifier,
                path: url.path,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Context

    private func makeContext() throws -> JSContext {
        guard let context = JSContext(virtualMachine: Self.virtualMachine) else {
            throw ExtensionHostError.javaScriptEngineUnavailable(identifier: identifier)
        }
        context.name = "extension:\(identifier)"
        context.exceptionHandler = { [weak self] _, exception in
            // The handler runs synchronously inside `evaluateScript` /
            // `JSValue.call`, on whatever thread made that call — and this host
            // only ever makes them from the main actor.
            MainActor.assumeIsolated {
                self?.pendingException = self?.describe(exception)
            }
        }
        return context
    }

    /// Installs the host block table, evaluates the shim, captures
    /// `__extensionRuntime`, installs the `VSCodeAPI` ceremony that has to be
    /// in place before any extension code runs (the command-dispatch
    /// trampoline, `vscode.Uri`), replays every adaptor-registered
    /// `vscode.*` member onto the fresh runtime, and then removes both
    /// globals.
    ///
    /// Removing `__host` and `__extensionRuntime` is the difference between
    /// "the extension is given a bounded runtime" and "the extension is given
    /// a bounded runtime plus a direct line to the app": `__host` carries
    /// blocks that schedule timers and write to the log, and an extension
    /// that found it could use them without going through any of the shim's
    /// checks.
    private func installRuntime(runtimeSource: String, into context: JSContext) throws -> JSValue? {
        guard let table = JSValue(newObjectIn: context) else {
            throw ExtensionHostError.javaScriptEngineUnavailable(identifier: identifier)
        }

        let console: @convention(block) (String, String) -> Void = { [weak self] level, text in
            MainActor.assumeIsolated { self?.handleConsole(level: level, text: text) }
        }
        let record: @convention(block) (String) -> Void = { [weak self] memberPath in
            MainActor.assumeIsolated { self?.handleNotImplemented(memberPath: memberPath) }
        }
        let probe: @convention(block) (String) -> Void = { [weak self] memberPath in
            MainActor.assumeIsolated { self?.handleNegativeProbe(memberPath: memberPath) }
        }
        let schedule: @convention(block) (Int32, Double, Bool) -> Void = { [weak self] timerID, delay, repeats in
            MainActor.assumeIsolated {
                self?.scheduleTimer(timerID: timerID, delayMilliseconds: delay, repeats: repeats)
            }
        }
        // `Double`, not `Int32`, and that is the entire Swift half of the
        // truncation fix: a `@convention(block) (Int32) -> Void` makes
        // JavaScriptCore apply ToInt32 to whatever it is handed, so
        // `clearTimeout(4294967297)` arrived here as `1` and cancelled a live
        // timer that had nothing to do with it — with no error on either side,
        // because the JS table had no such key to report on. A `Double` carries
        // the value the extension actually wrote, which is the only way this
        // side can refuse it at all.
        let cancel: @convention(block) (Double) -> Void = { [weak self] timerID in
            MainActor.assumeIsolated { self?.cancelTimer(rawTimerID: timerID) }
        }

        table.setObject(console, forKeyedSubscript: "console" as NSString)
        table.setObject(record, forKeyedSubscript: "recordNotImplemented" as NSString)
        table.setObject(probe, forKeyedSubscript: "recordNegativeProbe" as NSString)
        table.setObject(schedule, forKeyedSubscript: "scheduleTimer" as NSString)
        table.setObject(cancel, forKeyedSubscript: "cancelTimer" as NSString)
        context.setObject(table, forKeyedSubscript: "__host" as NSString)

        pendingException = nil
        context.evaluateScript(runtimeSource, withSourceURL: Self.runtimeSourceURL)
        if let message = pendingException {
            pendingException = nil
            throw ExtensionHostError.runtimeShimFailed(identifier: identifier, message: message)
        }

        let runtime = context.objectForKeyedSubscript("__extensionRuntime")
        guard let runtime, !runtime.isUndefined, !runtime.isNull else { return nil }

        // Eager, ahead of every adaptor-registered member below and ahead of
        // the extension's own module code: `VSCodeAPI.installTrampoline(in:)`
        // caches the command-dispatch trampoline under its non-configurable,
        // non-writable global *before* anything else in this context can
        // write to that name first. See `VSCodeAPI.sharedHelper(in:)` for
        // exactly what that closes and what it cannot. A same-named top-level
        // assignment the extension makes afterwards has one of two outcomes,
        // not one: in sloppy-mode extension code it is a silent no-op
        // (`helperSource` also freezes the trampoline object itself, not
        // just the global binding, so a member-level hijack like
        // `.call = ...` no-ops the same way); in strict-mode extension code —
        // what a `tsc`-compiled extension's own `"use strict"` prologue makes
        // its top-level statements — the identical assignment throws
        // `TypeError` instead, and that failure is the extension's own module
        // evaluation failing, which fails its own activation. What this call
        // cannot do: a context it does not succeed in still falls back to
        // the old lazy install, with the old window. Not fatal to
        // activation: a context that cannot host the trampoline yet is
        // exactly what the lazy fallback exists for, and
        // `installTrampoline(in:)` has already logged the failure.
        VSCodeAPI.installTrampoline(in: context)

        // Same eagerness, for `vscode.Uri`: installed directly into the local
        // `runtime` rather than through `defineVSCodeMember`, because that
        // public API's "apply immediately" branch reads `self.runtime`, which
        // is still `nil` here — `performActivation` only assigns it once this
        // method returns. Not queued onto `vscodeMemberDefinitions` either:
        // that list exists for adaptors with an owner to tear down and a
        // reason to be replayed on a later activation, and `Uri` is neither —
        // it is host ceremony, installed the same way on every activation,
        // exactly like the trampoline above. A failure here is logged and
        // left as the shim's not-implemented stub; it is not fatal to
        // activation, for the same reason a missing trampoline is not.
        if let uriClass = VSCodeAPI.installUriClass(in: context) {
            pendingException = nil
            runtime.invokeMethod("defineMember", withArguments: ["vscode", "Uri", uriClass])
            if let message = pendingException {
                pendingException = nil
                logger.error(
                    """
                    Extension '\(self.identifier, privacy: .public)' could not have 'vscode.Uri' \
                    installed (\(message, privacy: .public)); it stays the shim's not-implemented stub
                    """)
            }
        }

        // Before the extension's first statement runs, so a member defined by
        // an adaptor is already there when the module body reaches for it —
        // extensions routinely destructure `vscode` at the top of the file.
        //
        // By index, because a refused definition withdraws itself and the
        // throw leaves the loop immediately: nothing iterates past the
        // mutation.
        for index in vscodeMemberDefinitions.indices {
            try applyOrWithdraw(at: index, to: runtime)
        }

        context.evaluateScript("delete globalThis.__extensionRuntime; delete globalThis.__host;")
        return runtime
    }

    private static let runtimeSourceURL = URL(fileURLWithPath: "/agentic-extension-runtime.js")

    /// The bundled shim, read once per process and off the main thread.
    ///
    /// `readSource(at:identifier:)` above wraps its read in `Task.detached` for
    /// the project's no-lengthy-work-on-the-main-thread rule, and this is the
    /// same read of a file in the same size class; doing it inline here
    /// contradicted the rule its own neighbour documents, and it did so at the
    /// worst moment — inside the first activation, on the main actor.
    /// Memoized exactly as before: the answer cannot change within a process.
    ///
    /// Its caller reads it up with the entry point rather than at the point of
    /// use, so the suspension it adds sits *above* `performActivation`'s
    /// `isDisposed` and `Task.isCancelled` guards instead of opening a new
    /// window below them. See `performActivation`.
    private static func runtimeSource(identifier: String) async throws -> String {
        if let cachedRuntimeSource { return cachedRuntimeSource }
        let bundle = Bundle(for: ExtensionHostBundleToken.self)
        guard let url = bundle.url(forResource: "extension-runtime", withExtension: "js") else {
            // The shim ships inside this framework. Missing means a broken
            // build, not a broken extension — and it must not be reported as
            // the extension's fault.
            throw ExtensionHostError.runtimeUnavailable(identifier: identifier)
        }
        let read = await Task.detached(priority: .userInitiated) {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
        guard let read else {
            throw ExtensionHostError.runtimeUnavailable(identifier: identifier)
        }
        cachedRuntimeSource = read
        return read
    }

    // MARK: - Evaluation

    /// The extension's source, wrapped in the CommonJS parameter list.
    ///
    /// The prefix carries no trailing newline, and that is load-bearing rather
    /// than terse: Node's module wrapper is written the same way so that line
    /// *n* of the author's file is line *n* of the compiled script. Only the
    /// first line's columns shift, and a stack trace an author reads against
    /// their own editor agrees with it everywhere else.
    private static func moduleWrapperSource(_ source: String) -> String {
        // The trailing newline before `})` matters for the opposite reason: a
        // source whose last line is a `//` comment would otherwise swallow the
        // closing brace.
        "(function (exports, require, module, __filename, __dirname) { \(source)\n})"
    }

    /// Compiles the extension's module *as its own script*, named after the
    /// entry point, and runs it through the shim's CommonJS wrapper.
    ///
    /// Compiling host-side rather than with `new Function` inside the shim is
    /// what puts the author's own path and line numbers in their stack traces.
    /// JavaScriptCore attributes dynamically compiled code to no script at all
    /// — a `//# sourceURL=` directive reaches Web Inspector and never
    /// `Error.stack`, whose frames come back with an empty location — so the
    /// source URL has to be attached at compile time, which only the host can
    /// do.
    private func evaluateModule(runtime: JSValue, source: String, entryPoint: URL) throws -> JSValue {
        guard let context else {
            throw ExtensionHostError.javaScriptEngineUnavailable(identifier: identifier)
        }

        pendingException = nil
        let wrapper = context.evaluateScript(
            Self.moduleWrapperSource(source), withSourceURL: entryPoint)
        if let message = pendingException {
            // A syntax error in the extension's own file lands here, already
            // carrying the file name it came from.
            pendingException = nil
            logger.error(
                "Extension '\(self.identifier, privacy: .public)' would not compile: \(message, privacy: .public)")
            throw ExtensionHostError.entryPointThrew(identifier: identifier, message: message)
        }
        guard let wrapper, wrapper.isObject else {
            throw ExtensionHostError.entryPointThrew(
                identifier: identifier,
                message: "The entry point did not compile to a module function."
            )
        }

        pendingException = nil
        // The boundary. Everything above compiles; the line below *runs*, and
        // from the instant it does the extension's code cannot be un-run, so
        // every failure from here on is terminal and a retry is refused — see
        // `moduleEvaluated`. Nothing sits between the assignment and the call
        // that can throw or suspend, so there is no window in which one is
        // true without the other.
        moduleEvaluated = true
        let exports = runtime.invokeMethod(
            "run",
            withArguments: [wrapper, entryPoint.path, entryPoint.deletingLastPathComponent().path]
        )
        if let message = pendingException {
            pendingException = nil
            logger.error(
                "Extension '\(self.identifier, privacy: .public)' threw while loading: \(message, privacy: .public)")
            throw ExtensionHostError.entryPointThrew(identifier: identifier, message: message)
        }
        guard let exports, !exports.isUndefined, !exports.isNull else {
            throw ExtensionHostError.entryPointThrew(
                identifier: identifier,
                message: "The entry point produced no module exports."
            )
        }
        return exports
    }

    /// Calls `exports.activate(context)` and waits for it to *finish*.
    ///
    /// The waiting is the point. `activate` may return a thenable, and the
    /// shim's `callActivate` reports the end of it — resolution or rejection —
    /// through a completion block rather than a return value, because a
    /// rejected promise is invisible from Swift: JavaScriptCore does not route
    /// unhandled rejections to a context's `exceptionHandler`, so
    /// `pendingException` stays nil and an async `activate` that threw would
    /// look exactly like one that succeeded.
    ///
    /// An extension without `activate` is legal — a manifest can ship code that
    /// only contributes through side effects — so its absence is logged and is
    /// not an error. What it is handed *is* an error surface: the activation
    /// context is a recorded, throwing stub like every `vscode` member, so an
    /// extension that reaches for `context.subscriptions` today is told which
    /// member it wanted rather than failing later on an `undefined`.
    private func callActivate(on exports: JSValue, runtime: JSValue) async throws {
        // Named `context`, the way the author typed it. The ledger is read by a
        // person looking for the line they wrote, and
        // `vscode.ExtensionContext.subscriptions` is a name that appears
        // nowhere in their file.
        let activationContext = runtime.invokeMethod("makeStubNamespace", withArguments: ["context"])

        // The one window the state machine did not cover, and the last one:
        // between `performActivation`'s guards and the continuation installed
        // below, `evaluateModule` runs the extension's top level — and a host
        // observer called from inside it can `dispose()` the host, exactly as
        // a cancellation can land there. Both routes end an activation through
        // `finishActivation`, which is a no-op while there is no continuation
        // to resume, so an activation that installed one anyway suspended on a
        // host that had already been told to stop, with nothing left to wake
        // it. Read through `activationState` rather than an ad-hoc
        // `isDisposed`, so both routes are refused by the same precedence rule
        // as every other transition and neither has to be enumerated here.
        //
        // Throwing rather than resuming: `performActivation`'s `catch` is
        // below, `moduleEvaluated` is already true, and `markTerminal` keeps
        // the first reason — so a cancellation that came through
        // `endActivation` is still reported as `.cancelled` and is not
        // relabelled `.failed` on its way out.
        switch activationState {
        case .disposed:
            throw ExtensionHostError.hostDisposed(identifier: identifier)
        case let .terminal(reason):
            throw Self.terminalRefusal(reason, identifier: identifier)
        case .activating, .activated, .neverActivated:
            break
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            activationContinuation = { result in continuation.resume(with: result) }

            let done: @convention(block) (Bool, String) -> Void = { [weak self] succeeded, message in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if succeeded {
                        self.finishActivation(.success(()))
                    } else {
                        Self.logger.error(
                            """
                            Extension '\(self.identifier, privacy: .public)' threw from activate(): \
                            \(message, privacy: .public)
                            """)
                        self.finishActivation(
                            .failure(.activationThrew(identifier: self.identifier, message: message)))
                    }
                }
            }

            pendingException = nil
            let hadActivate = runtime.invokeMethod(
                "callActivate", withArguments: [exports, activationContext as Any, done])

            // Load-bearing, and not only for a broken bridge: the shim reads
            // `result.then` outside any `try`, so a thenable whose `.then`
            // *getter* throws — extension-controlled, and the shape a Proxy or
            // a lazily-defined property produces — leaves `callActivate`
            // through this line rather than through `done`. Verified in real
            // JSC: `invokeMethod` returns `undefined`, `done` was never called,
            // and the exception arrives here. Delete it and that extension
            // hangs activation instead of failing it.
            if let message = pendingException {
                pendingException = nil
                finishActivation(
                    .failure(.activationThrew(identifier: identifier, message: message)))
                return
            }

            if hadActivate?.toBool() != true {
                logger.info("Extension '\(self.identifier, privacy: .public)' exports no activate() function")
            }
        }
    }

    /// Ends the suspended `activate()`, once and only once.
    ///
    /// Four callers race for it — the shim's completion block, the bridge's
    /// own failure path, `dispose()`, and a cancelled caller — and a
    /// `CheckedContinuation` resumed twice is a crash, not a warning. The
    /// cancellation case is the one that makes this more than a formality: it
    /// resumes an activation whose JavaScript is still running, so the
    /// extension's promise settling afterwards *will* call `done` on a
    /// continuation that is already gone.
    private func finishActivation(_ result: Result<Void, ExtensionHostError>) {
        guard let resume = activationContinuation else { return }
        activationContinuation = nil
        resume(result)
    }

    /// Whether `describe` is already running, one level up.
    ///
    /// The thing being described is a value the extension threw, and describing
    /// it means *calling into JavaScript*: `toString()` and the `stack` getter
    /// are both extension-controlled. JavaScriptCore reports an exception
    /// raised by either of them the only way it has — by calling the context's
    /// exception handler — and that handler is what called `describe` in the
    /// first place. A value that keeps throwing while being described therefore
    /// recurses: `throw (hostile = new Proxy({}, { get() { throw hostile } }))`
    /// nests a native frame per cycle and the process dies on a stack overflow
    /// rather than reporting an extension error.
    ///
    /// One owned bit, checked at entry — the same shape as the reentrancy flag
    /// in `TextDocumentStorage`. A nested call describes nothing and touches no
    /// JavaScript, so the recursion is two deep and bounded by construction
    /// however the outer description is later grown.
    private var describingException = false

    private func describe(_ exception: JSValue?) -> String {
        guard let exception else { return "unknown JavaScript exception" }
        // The nested call is the one raised *by* describing, so it has no
        // description of its own to give: returning a literal is the whole
        // point, and it is the one answer that cannot throw again.
        guard !describingException else { return "a JavaScript exception raised while describing another" }
        describingException = true
        defer { describingException = false }

        let message = exception.toString() ?? "unknown JavaScript exception"
        guard let stack = exception.objectForKeyedSubscript("stack"),
              !stack.isUndefined, !stack.isNull,
              let text = stack.toString(), !text.isEmpty else {
            return message
        }
        return "\(message)\n\(text)"
    }

    // MARK: - Host callbacks

    private func handleConsole(level: String, text: String) {
        let resolved = ExtensionConsoleMessage.Level(rawValue: level) ?? .log
        switch resolved {
        case .debug:
            logger.debug("[\(self.identifier, privacy: .public)] \(text, privacy: .public)")
        case .info:
            logger.info("[\(self.identifier, privacy: .public)] \(text, privacy: .public)")
        case .warn:
            logger.warning("[\(self.identifier, privacy: .public)] \(text, privacy: .public)")
        case .error:
            logger.error("[\(self.identifier, privacy: .public)] \(text, privacy: .public)")
        case .log:
            logger.log("[\(self.identifier, privacy: .public)] \(text, privacy: .public)")
        }
        onConsoleMessage?(
            ExtensionConsoleMessage(extensionIdentifier: identifier, level: resolved, text: text))
    }

    private func handleNotImplemented(memberPath: String) {
        let access = notImplementedLedger.record(memberPath: memberPath, extensionIdentifier: identifier)
        // Only the first reach is logged. The ledger already counts the rest,
        // and a member reached for inside a loop would otherwise fill the log
        // with the one line that carries no new information.
        guard access.count == 1 else { return }
        logger.notice(
            """
            Extension '\(self.identifier, privacy: .public)' reached for \
            '\(memberPath, privacy: .public)', which is not implemented yet
            """)
    }

    /// An extension asked whether a member exists and was honestly told no.
    ///
    /// `'registerCommand' in vscode.commands`, `Object.keys(vscode.window)`,
    /// `getOwnPropertyDescriptor(...)` — feature detection, which must answer
    /// rather than throw, or every library that guards its own calls would
    /// break. But the question is worth more to task 5.8's report than the
    /// throwing accesses are: an extension that *looked* and quietly took its
    /// fallback path is telling us what it wanted, and nothing else in this
    /// host would ever notice.
    private func handleNegativeProbe(memberPath: String) {
        let access = notImplementedLedger.recordProbe(
            memberPath: memberPath, extensionIdentifier: identifier)
        // First probe only, for the same reason as `handleNotImplemented`: a
        // library that feature-detects inside a loop would otherwise fill the
        // log with one line that carries no new information.
        guard access.probeCount == 1 else { return }
        logger.notice(
            """
            Extension '\(self.identifier, privacy: .public)' checked for \
            '\(memberPath, privacy: .public)' and was told it does not exist
            """)
    }

    // MARK: - Timers

    /// The largest delay this host will sleep for, in milliseconds — the
    /// signed 32-bit ceiling `setTimeout` has on every platform an extension
    /// author has used, about 24.8 days.
    ///
    /// A ceiling is required here, not merely tidy. `Duration.seconds(Double)`
    /// scales its argument into fixed-width attoseconds, so it **traps** on any
    /// value it cannot represent — and the value reaching it is an ordinary
    /// `setTimeout` argument: `setTimeout(fn, Number.MAX_VALUE)` is one JS call
    /// in one extension, and it took the whole process down. `max(0, …)` alone
    /// guarded only the end that could not overflow. The shim clamps too, but
    /// the shim is extension-reachable and this is not, and one bad
    /// `setTimeout` must not be able to kill every other extension and the app
    /// with it — which is the isolation property this host exists to provide.
    private static let maximumTimerDelayMilliseconds: Double = 2_147_483_647

    private func scheduleTimer(timerID: Int32, delayMilliseconds: Double, repeats: Bool) {
        guard !isDisposed else { return }
        timerTasks[timerID]?.cancel()

        // `max` first, and it is what handles NaN: a NaN comparison is false,
        // so `max(0, .nan)` is 0 rather than NaN. `min` then takes the ceiling,
        // including for `.infinity`.
        let seconds = min(max(0, delayMilliseconds), Self.maximumTimerDelayMilliseconds) / 1000
        runningTimerTasks += 1
        timerTasks[timerID] = Task { @MainActor [weak self] in
            defer { self?.timerTaskDidFinish() }
            while true {
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    // The only throw here is cancellation, which is teardown or
                    // `clearTimeout`. Either way the callback must not run.
                    return
                }
                guard !Task.isCancelled, let self, !self.isDisposed else { return }
                if !repeats {
                    self.timerTasks[timerID] = nil
                }
                self.fireTimer(timerID: timerID)
                if !repeats { return }
            }
        }
    }

    /// One timer task ended. Exactly as many of these as there were starts.
    ///
    /// The count going negative would mean a task finished twice, which cannot
    /// happen through any route this file has — so it is stated rather than
    /// clamped. A `max(0, …)` here would keep the invariant *looking* true
    /// while the bug it was protecting against went on being a bug, and this
    /// counter is the only evidence a teardown test has.
    private func timerTaskDidFinish() {
        guard runningTimerTasks > 0 else {
            assertionFailure("A timer task finished that was never counted as running.")
            logger.fault(
                """
                Extension '\(self.identifier, privacy: .public)' finished a timer task that was \
                never counted as running
                """)
            return
        }
        runningTimerTasks -= 1
    }

    /// Cancels by the id the extension wrote, or by nothing at all.
    ///
    /// An id outside `Int32`, or one with a fraction, is not an id this host
    /// ever issued — the shim numbers from 1 and stops at the same ceiling —
    /// so there is nothing to cancel and, crucially, nothing to *round* onto.
    private func cancelTimer(rawTimerID: Double) {
        guard rawTimerID.isFinite,
              rawTimerID == rawTimerID.rounded(.towardZero),
              rawTimerID >= Double(Int32.min),
              rawTimerID <= Double(Int32.max) else { return }
        cancelTimer(timerID: Int32(rawTimerID))
    }

    private func cancelTimer(timerID: Int32) {
        timerTasks[timerID]?.cancel()
        timerTasks[timerID] = nil
    }

    private func fireTimer(timerID: Int32) {
        guard let runtime else { return }
        pendingException = nil
        runtime.invokeMethod("fireTimer", withArguments: [Int(timerID)])
        if let message = pendingException {
            pendingException = nil
            logger.error(
                "Extension '\(self.identifier, privacy: .public)' threw from a timer: \(message, privacy: .public)")
        }
    }
}

extension ExtensionHost: Loggable {
    public static nonisolated let logger = makeLogger()
}

/// Resolves this framework's bundle for `Bundle(for:)`. Same device as
/// `AIModelCatalog.BundleToken`: a framework's own resources are found through
/// a class it defines, never through `Bundle.main`, which is the *app*.
private final class ExtensionHostBundleToken {}

/// One `console.*` call an extension made.
public struct ExtensionConsoleMessage: Sendable, Equatable {

    public enum Level: String, Sendable, CaseIterable {
        case log
        case info
        case warn
        case error
        case debug
    }

    public let extensionIdentifier: String
    public let level: Level
    /// Already stringified by the shim, the way a developer expects — an object
    /// arrives as `{ a: 1 }`, not `[object Object]`.
    public let text: String

    public init(extensionIdentifier: String, level: Level, text: String) {
        self.extensionIdentifier = extensionIdentifier
        self.level = level
        self.text = text
    }
}

/// Why an extension's code did not run.
///
/// Every case names the extension, because a host failure reaches the user
/// through a list of extensions and "it didn't work" attached to none of them
/// is not a report. `Equatable` for the same reason `ExtensionLoadError` is: a
/// test can state the exact refusal it expects.
public enum ExtensionHostError: Error, Sendable, Equatable {

    /// The manifest declares `main` but not `browser`. The distinction matters
    /// enough to be its own case: `main` is Node's entry point, this host is a
    /// JavaScriptCore web-extension host, and an author whose extension is
    /// simply the wrong *kind* needs to be told that rather than left reading a
    /// generic load failure.
    case requiresNodeRuntime(identifier: String, declaredMain: String)

    /// Neither `main` nor `browser`. Nothing was refused — the extension
    /// declares no code at all, and everything it contributes it contributes
    /// through its manifest.
    case noEntryPoint(identifier: String)

    /// `browser` resolved outside the extension's own directory. `resolved` is
    /// carried alongside the declared string because the declared one alone
    /// (`../../../etc/passwd`) does not show what it reached.
    case entryPointEscapesExtensionDirectory(identifier: String, declared: String, resolved: String)

    case entryPointUnreadable(identifier: String, path: String, message: String)

    /// The extension's top-level code threw. Caught, not crashed on: one bad
    /// extension is one failed extension.
    case entryPointThrew(identifier: String, message: String)

    /// `activate()` itself threw — which, until stages 5.3-5.7 land, is what
    /// happens to every extension that reaches for a `vscode` member.
    case activationThrew(identifier: String, message: String)

    /// The task awaiting `activate()` was cancelled. Its own case rather than
    /// `CancellationError` because every failure here names the extension it
    /// belongs to, and because it says something `CancellationError` does not:
    /// the extension's `activate()` may still be running in JavaScript.
    ///
    /// What the host can do next depends on where the cancellation landed, and
    /// `activationState` is what answers it. A cancellation that reached a
    /// module already evaluated leaves the host `.terminal(.cancelled)`, and
    /// then `dispose()` is the only thing left — a later `activate()` and a
    /// later `defineVSCodeMember` both refuse with this same error. A
    /// cancellation that landed earlier, while the entry point was still being
    /// read, ran nothing and abandoned nothing: the host stays
    /// `.neverActivated` and can simply be activated again.
    case activationCancelled(identifier: String)

    /// An earlier `activate()` failed after the extension's module had already
    /// been evaluated, so this host is spent. Its own case because the caller
    /// who retries needs to be told something the original failure does not
    /// say: retrying *this host* is not the way to try again. The module has
    /// run; a second attempt would evaluate it into a second runtime beside the
    /// first.
    case activationAlreadyFailed(identifier: String)

    /// The runtime shim is missing from this framework's bundle. A build
    /// problem, not an extension problem.
    case runtimeUnavailable(identifier: String)

    /// The shim itself threw while being evaluated. Also a build problem.
    case runtimeShimFailed(identifier: String, message: String)

    case javaScriptEngineUnavailable(identifier: String)

    case hostDisposed(identifier: String)

    /// `defineVSCodeMember` named a namespace the shim does not have. An
    /// adaptor's bug, not an extension's — and one that would otherwise present
    /// as a member that mysteriously went on throwing.
    case vscodeMemberNotDefinable(identifier: String, namespacePath: String, name: String, message: String)
}

extension ExtensionHostError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case let .requiresNodeRuntime(identifier, declaredMain):
            return """
                '\(identifier)' declares a Node entry point ('main': '\(declaredMain)') and no 'browser' \
                entry point. This host runs web extensions in JavaScriptCore and has no Node runtime, so \
                only extensions that declare 'browser' can be run.
                """
        case let .noEntryPoint(identifier):
            return "'\(identifier)' declares no code: its manifest has neither 'main' nor 'browser'."
        case let .entryPointEscapesExtensionDirectory(identifier, declared, resolved):
            return """
                '\(identifier)' declares a 'browser' entry point of '\(declared)', which resolves to \
                '\(resolved)' — outside the extension's own directory. Refused.
                """
        case let .entryPointUnreadable(identifier, path, message):
            return "'\(identifier)' could not read its entry point at '\(path)': \(message)"
        case let .entryPointThrew(identifier, message):
            return "'\(identifier)' threw while its code was loading: \(message)"
        case let .activationThrew(identifier, message):
            return "'\(identifier)' threw from activate(): \(message)"
        case let .activationCancelled(identifier):
            return """
                '\(identifier)' did not finish activating: the task awaiting it was cancelled. If its \
                code had already started, the extension's own activate() may still be running, and \
                tearing the host down is what stops it.
                """
        case let .activationAlreadyFailed(identifier):
            return """
                '\(identifier)' already failed to activate, and a failed activation cannot be retried on \
                the same host: its code has already run. Tear this host down and build a new one.
                """
        case let .runtimeUnavailable(identifier):
            return "'\(identifier)' could not be started: the extension runtime is missing from this build."
        case let .runtimeShimFailed(identifier, message):
            return "'\(identifier)' could not be started: the extension runtime failed to load: \(message)"
        case let .javaScriptEngineUnavailable(identifier):
            return "'\(identifier)' could not be started: a JavaScript context could not be created."
        case let .hostDisposed(identifier):
            return "'\(identifier)' cannot be activated: its host has already been torn down."
        case let .vscodeMemberNotDefinable(identifier, namespacePath, name, message):
            return """
                '\(identifier)' could not have '\(name)' installed on '\(namespacePath)': \(message)
                """
        }
    }
}
