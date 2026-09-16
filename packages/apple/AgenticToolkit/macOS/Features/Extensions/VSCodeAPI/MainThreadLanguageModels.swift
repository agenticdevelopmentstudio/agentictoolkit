//
//  MainThreadLanguageModels.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore
import OSLog
import AgenticToolkitCore

// MARK: - Value types mirroring vscode.d.ts's LanguageModelChat family

/// One chat model this host can offer an extension — the data
/// `vscode.LanguageModelChat`'s six readonly properties expose
/// (`vscode.d.ts:20242-20312`, commit
/// 3addbda66f9e80c3ed1b943822ab823bb6747b02).
///
/// A plain value type, not the JS object itself: `selectChatModels` builds a
/// fresh `JSValue` per call from whichever of these match a selector
/// (`MainThreadLanguageModels.makeChatModelObject`, below), so this struct is
/// what `ExtensionLanguageModelProviding` deals in and the only thing a test
/// double needs to construct.
public struct LanguageModelChatDescriptor: Sendable, Equatable {
    /// `vscode.d.ts:20247`.
    public var name: String
    /// `vscode.d.ts:20252`.
    public var id: String
    /// `vscode.d.ts:20258`.
    public var vendor: String
    /// `vscode.d.ts:20264`.
    public var family: String
    /// `vscode.d.ts:20270`.
    public var version: String
    /// `vscode.d.ts:20275`.
    public var maxInputTokens: Int

    public init(
        name: String,
        id: String,
        vendor: String,
        family: String,
        version: String,
        maxInputTokens: Int
    ) {
        self.name = name
        self.id = id
        self.vendor = vendor
        self.family = family
        self.version = version
        self.maxInputTokens = maxInputTokens
    }
}

/// One `vscode.LanguageModelChatMessage` after parsing
/// (`LanguageModelMessageVocabulary.swift:238`) — a value type, not the
/// `JSValue` itself, because `sendRequest`'s seam call crosses into an async
/// `Task` (`MainThreadLanguageModels.handleSendRequest`, below) and a
/// `JSValue` cannot cross a suspension point safely.
///
/// `text` is built by the same array-reading logic `extractedText(from:)`
/// already uses for `countTokens` (`:302-326`) — generalised, not
/// duplicated, per this task's own brief: both
/// readers agree that `content` is always an array of parts and that only a
/// part with a string `.value` contributes text.
public struct ExtensionLanguageModelMessage: Sendable, Equatable {
    /// `vscode.LanguageModelChatMessageRole` (`LanguageModelMessageVocabulary
    /// .swift:172-173`): `User` or `Assistant`, nothing else.
    public enum Role: Sendable, Equatable {
        case user
        case assistant
    }

    public var role: Role
    public var name: String?
    public var text: String

    public init(role: Role, name: String?, text: String) {
        self.role = role
        self.name = name
        self.text = text
    }
}

/// One element of `sendRequest`'s response stream — the seam's own value
/// type, alongside `LanguageModelChatDescriptor` above (Ruling 52). No new
/// file: `ExtensionLanguageModelProviding` gains no shared-tier gate by
/// adding a case-y value type next to the one it already declares.
///
/// `AIPluginKit/AIStreamEvent.swift` (38 lines at `ffd243a7`) declares three
/// cases this type must map onto **losslessly**, without this file gaining a
/// dependency on `AIPluginKit` itself: `textDelta(String)` (`:8`),
/// `toolUse(id: String, name: String, argumentsJSON: Data)` (`:11`), and
/// `end(stopReason: String?)` (`:14`). Three cases here, one per one there.
///
/// `.end` is a **part**, not the stream's own termination signal, precisely
/// so `stopReason` survives the seam — the loss happens one layer higher,
/// deliberately: `vscode.LanguageModelChatResponse` (`vscode.d.ts
/// :20194-20235`) declares exactly two members, `stream` and `text`, and
/// neither has anywhere to put a stop reason, so the JS projection this file
/// builds drops it. `.end` arriving finishes both of that object's async
/// iterables (`{done: true}`); a source that ends without emitting `.end`
/// finishes them the same way; a source that emits after `.end` is a seam
/// violation this file ignores rather than traps.
public enum ExtensionLanguageModelResponsePart: Sendable, Equatable {
    case text(String)
    case toolCall(id: String, name: String, argumentsJSON: Data)
    case end(stopReason: String?)
}

// MARK: - The extension language-model seam

/// Every chat model this host currently knows about, for
/// `vscode.lm.selectChatModels` (`vscode.d.ts:20769`, commit
/// 3addbda66f9e80c3ed1b943822ab823bb6747b02).
///
/// A seam rather than a direct reference to whatever eventually fronts a real
/// model provider: that type would be `@MainActor`, live production code —
/// reaching it directly from this adaptor would make every test of
/// `selectChatModels` construct a real provider, the same reason
/// `ExtensionLanguageVocabulary` exists instead of a direct reference to
/// `LanguageContributionPoint` (`MainThreadLanguages.swift:448-463`, commit
/// 6409e2de). `AIPluginLanguageModelProvider` is the production conformer —
/// it reads the user's configured AI providers and sends through the
/// `.aiplugin` behind each one — and a test hands in a double instead.
///
/// Two members, not one — `streamResponse` joined `availableChatModels`
/// under Rulings 52 and 54 — but `MainThreadLanguageModels` still does all
/// selector matching itself (below), so `availableChatModels` only has to
/// answer what exists, not what matches — keeping the selector semantics
/// (no-selector-means-all, `{}`-same-as-omitted, per-field conjunction) in
/// one place, testable against one simple double, rather than duplicated
/// behind every future conformer.
@MainActor
public protocol ExtensionLanguageModelProviding: AnyObject {
    /// Every chat model this host currently knows about, in a deterministic
    /// order, unfiltered by any selector.
    var availableChatModels: [LanguageModelChatDescriptor] { get }

    /// Produces the streamed response to one `sendRequest` call
    /// (`vscode.d.ts:20302`), as a single-consumption
    /// `AsyncThrowingStream` — the seam's own value type (Ruling 52), not
    /// `AIStreamEvent`, so this protocol carries no `AIPluginKit` dependency.
    ///
    /// `justification` is `options.justification` (`:20392`), passed straight
    /// through per Ledger Ruling 4: this task implements no consent gate, so
    /// nothing between the extension and this call interprets it.
    /// `modelOptions`, `tools` and `toolMode`
    /// (`:20398`,`:20411`,`:20416`) do **not** reach here — Ruling 54 keeps
    /// them at the adaptor, recorded into
    /// `notImplementedLedger` instead, because a provider that received them
    /// would have to at least pretend to honour them, and none does yet.
    func streamResponse(
        for model: LanguageModelChatDescriptor,
        messages: [ExtensionLanguageModelMessage],
        justification: String?,
        extensionIdentifier: String
    ) async throws -> AsyncThrowingStream<ExtensionLanguageModelResponsePart, Error>
}

// MARK: - The onDidChangeChatModels window

/// The window `onDidChangeChatModelsEmitter` (below) is built with:
/// `ExtensionEventEmitter.window` has no default
/// (`ExtensionEvent.swift:158-160`'s own doc explains why a default would
/// stop the seam from being one), and `onDidChangeChatModels` has nothing
/// for a
/// window to coalesce — the set-identity filter in
/// `availableChatModelsDidChange()` *is* the debounce (Ruling 63), the
/// same division upstream draws in the one step its own constructor
/// performs: `mainThreadLanguageModels.ts:78-86` builds the current id
/// set, compares it to the last one, and only republishes on a real
/// difference — no time window in that filter-and-forward step itself
/// (commit `3addbda66f9e80c3ed1b943822ab823bb6747b02`). Those nine
/// lines are the whole of what is pinned here; they say nothing about
/// `onDidChangeLanguageModels`'s own emission on the line above it,
/// which this doc does not claim to have inspected.
///
/// **Honest limit:** upstream's own filter reads
/// `this._chatProviderService.getLanguageModelIds()`, one call away from the
/// `LanguageModelChat.id` this host's `availableChatModelsDidChange()`
/// compares — the two are only guaranteed to agree because this host has
/// exactly one place that lists chat models (`provider.availableChatModels`),
/// where upstream's service and its id accessor are two separate things that
/// merely happen to agree today.
///
/// This closes the one window it is ever asked to open in the same call
/// that opened it, rather than deferring to a real timer the way
/// `ExtensionEventTimerWindow` does for `onDidChangeDiagnostics` — a window
/// that cannot fire late, not a second event mechanism. `fire(_:)`
/// (`ExtensionEvent.swift`) queues this call's payload *before* it opens the
/// window, precisely so a window that closes synchronously, like this one,
/// finds that payload already there — see `fire(_:)`'s own doc for why
/// upstream's literal statement order (open, then queue) does not carry over
/// to a seam that allows a synchronous conformer. The net effect is still
/// that a listener's delivery is synchronous with the
/// `availableChatModelsDidChange()` call that triggered it, which is what
/// lets this file's tests assert a delivery without polling or sleeping.
@MainActor
private final class ChatModelsImmediateWindow: ExtensionEventWindowScheduling {
    func openWindow(closingAfter delay: TimeInterval, onClose: @escaping @MainActor () -> Void) {
        onClose()
    }
}

// MARK: - vscode.lm

/// Installs `vscode.lm.selectChatModels` (`vscode.d.ts:20769`) and the
/// `vscode.LanguageModelChat` objects it hands back (`:20242-20312`) — the
/// second half of task 5.7a, plus (task 5.7b) `sendRequest`'s real streaming
/// response. 5.7a-i installed the value types an extension *constructs*
/// (`LanguageModelMessageVocabulary.swift`); this installs the namespace
/// function that *finds a model*, the object it hands back, and the response
/// `sendRequest` resolves with — plus (task 5.7c)
/// `vscode.lm.onDidChangeChatModels` itself (`vscode.d.ts:20742`), the
/// `Event<void>` `selectChatModels`'s own doc block tells listeners to re-query on
/// (`:20763-20764`), fired only when the *set* of model ids changes
/// (`availableChatModelsDidChange()`, below).
///
/// **Whoever owns this adaptor must call `dispose()`** when it tears the
/// extension host down, in the shape `MainThreadCommands.swift:36-48` and
/// `MainThreadWindow.swift:838-842` both use. Nothing calls it in this
/// framework today: `ExtensionHost.dispose()` (`ExtensionHost.swift:800-827`)
/// tears down only its own state, not any adaptor's, because nothing
/// instantiates `ExtensionHost` in production yet. Inventing an owner here
/// would be a guess at a wiring design the `ExtensionsCoordinator` task owns.
@MainActor
public final class MainThreadLanguageModels {

    /// The source of chat models this member selects from.
    /// `handleSelectChatModels` reads `availableChatModels` and filters it
    /// itself; `ExtensionLanguageModelProviding` has a second member,
    /// `streamResponse`, that this property does not stand in for — see the
    /// protocol's own doc (above) for why matching stays here rather than
    /// moving into a conformer.
    private let provider: ExtensionLanguageModelProviding

    /// Recipient of `sendRequest`'s "not implemented" access — the same
    /// ledger `MainThreadWindow`'s status-bar item setters record into
    /// (`MainThreadWindow.swift:2293-2294`, `:2306-2307`).
    private let notImplementedLedger: NotImplementedLedger

    /// Whose extension is asking, for `notImplementedLedger`'s
    /// `extensionIdentifier` field. Stored, not defaulted —
    /// `MainThreadWindow` stores its own the same way and equally without a
    /// default (`MainThreadWindow.swift:881`, commit 6409e2de, which states
    /// no reason). The reason here is mine: there is no safe silent default
    /// for "whose extension," and a wrong one mislabels every ledger entry.
    private let extensionIdentifier: String

    /// Checked before a `sendRequest` response settles and again after its
    /// `await` returns — modelled verbatim on `MainThreadWindow.swift:890`
    /// (Ruling 51). Weak capture already answers *is the adaptor still
    /// there*; this answers *should this settle*, which a request in flight
    /// during teardown needs, because the adaptor **is** still there — the
    /// `Task` awaiting the seam's stream holds it strongly for that turn.
    /// `fileprivate`, not `private`: `LanguageModelResponseRequest` (below)
    /// reads it too, and the two types share this file rather than a shared
    /// tier because there is no seam a second file would sit behind.
    fileprivate var isDisposed = false

    /// The sole strong reference to each in-flight `sendRequest` response —
    /// the same shape `MainThreadWindow.statusBarItems` uses
    /// (`MainThreadWindow.swift:896`, doc `:892-895`). A request removes
    /// itself once both its cursors finish (Ruling 53's ruled-in
    /// divergence). `dispose()` deliberately leaves any request still here
    /// in place (Ruling 81/82): rejecting a `next()` call issued after
    /// teardown needs the request object to still exist, since
    /// `attemptSettleOrStore`'s `!owner.isDisposed` branch below is what
    /// produces that rejection, and a deallocated request answers `nil` —
    /// which bridges to JavaScript as `undefined`, not a rejection. A
    /// response an extension never fully iterates (or never iterates at
    /// all) is therefore retained for the adaptor's whole lifetime as a
    /// result — the cost Ruling 82 accepts rather than reopening request
    /// ownership from the JS side, which would overturn Ledger Ruling 2's
    /// weak-capture rule. What that retention now holds is broader than a
    /// transient waiter box: each retained request also carries the two
    /// `JSValue` vocabulary constructors cached on it, so what Ruling 82's
    /// post-`dispose()` retention holds reaches into the JS heap, and
    /// through those `JSValue`s, the `JSContext` itself — not only
    /// Swift-side state.
    fileprivate var liveRequests: [UUID: LanguageModelResponseRequest] = [:]

    /// The last `Set` of `LanguageModelChatDescriptor.id`s
    /// `availableChatModelsDidChange()` saw, seeded here from
    /// `provider.availableChatModels` rather than left to seed lazily on the
    /// first call — a lazily-seeded (empty) snapshot would make that first
    /// call always differ and fire unconditionally, the opposite of
    /// `mainThreadLanguageModels.ts:75-77`'s reason for filtering at all
    /// (commit `3addbda66f9e80c3ed1b943822ab823bb6747b02`). Compared as a
    /// `Set<String>` of ids, not as `[LanguageModelChatDescriptor]`: the
    /// descriptor is `Equatable` over all six of its stored properties, so an
    /// array comparison would fire on a metadata-only republish —
    /// exactly what `:75-77`'s filter exists to suppress — and would treat
    /// reordering as a change, which a set does not.
    private var lastModelIdentifiers: Set<String>

    /// The emitter behind `vscode.lm.onDidChangeChatModels`
    /// (`vscode.d.ts:20742`, `Event<void>`). Built with an immediate window
    /// rather than `ExtensionEventTimerWindow` — see
    /// `ChatModelsImmediateWindow`'s own doc for why —
    /// because this event has nothing to coalesce (Ruling 63): the identity
    /// filter in `availableChatModelsDidChange()` below is the whole
    /// debounce, the same way upstream's is identity-based rather than
    /// time-based (`mainThreadLanguageModels.ts:78-86`).
    private let onDidChangeChatModelsEmitter = ExtensionEventEmitter<Void>(
        path: "vscode.lm.onDidChangeChatModels",
        delay: 0,
        window: ChatModelsImmediateWindow(),
        merge: { _ in () },
        map: { _, context in JSValue(undefinedIn: context) }
    )

    /// Test-only window onto `onDidChangeChatModelsEmitter`'s registration
    /// count. Unlike `MainThreadDiagnostics`'s injected, shared emitter
    /// (`MainThreadDiagnostics.swift:365`, commit `90c38b02`), the emitter
    /// above is a private, per-instance `let` — a test has no reference of
    /// its own to hold, and once `dispose()` has run, no fire can reach it
    /// to report on its listener count indirectly. `internal`, not
    /// `public`: this framework's public surface does not grow for a test;
    /// `MainThreadLanguageModelsTests.swift` reaches it through
    /// `@testable import AgenticToolkitMacOS`.
    var onDidChangeChatModelsListenerCount: Int {
        onDidChangeChatModelsEmitter.listenerCount
    }

    public init(
        provider: ExtensionLanguageModelProviding,
        notImplementedLedger: NotImplementedLedger,
        extensionIdentifier: String
    ) {
        self.provider = provider
        self.notImplementedLedger = notImplementedLedger
        self.extensionIdentifier = extensionIdentifier
        self.lastModelIdentifiers = Set(provider.availableChatModels.map { $0.id })
    }

    /// Tears this adaptor down: (1) `isDisposed = true`, so no `sendRequest`
    /// promise created after this point ever settles with data; (2) every
    /// live request's outstanding `next()` promises reject with the same
    /// wording `rejectTornDown(_:path:)` uses; (3) each request's source is
    /// cancelled, so nothing keeps pumping the seam's stream once nothing
    /// can observe it; (4) this adaptor's `onDidChangeChatModels` listeners
    /// are dropped from `onDidChangeChatModelsEmitter` — not because the
    /// emitter is shared (it is not: the stored property above is a
    /// private, per-instance `let`, and `Registration.owner`
    /// (`ExtensionEvent.swift:144`) holds its owner only as an
    /// `ObjectIdentifier`, never strongly, so there is no retain path from
    /// the emitter back to this adaptor for `dispose()` to break) — but
    /// because a registration holds its listener `JSValue` strongly, and
    /// that `JSValue` holds its `JSContext` strongly, so leaving the
    /// registration in place after this adaptor has torn down would leave a
    /// torn-down extension's context outliving its host until that listener
    /// goes — exactly what `ExtensionEvent.swift`'s own "Lifetime" doc
    /// (`:119-129`) says of every registration, not something this
    /// adaptor's teardown introduces. `MainThreadDiagnostics.dispose()`
    /// (`MainThreadDiagnostics.swift:876`) removes its own listeners for the
    /// same
    /// reason; (5) `handleOnDidChangeChatModels()` and
    /// `availableChatModelsDidChange()` (below) both additionally guard on
    /// `isDisposed`: `VSCodeAPI.member`'s `[weak owner]` capture
    /// (`VSCodeAPI.swift:78-85`) only answers a torn-down response once this
    /// object actually deallocates, and `dispose()` does not deallocate it —
    /// without this guard, an extension could still register a new listener,
    /// and a later `availableChatModelsDidChange()` could still fire into
    /// it, in the window between `dispose()` and dealloc. A post-dispose
    /// registration now raises the same message `whenTornDown:
    /// .raisedException` raises for the dealloc case, so an extension sees
    /// one consistent answer regardless of which teardown state it caught.
    /// `liveRequests` is deliberately **not**
    /// cleared here (Ruling 81 — this brief's *behaviour* sentence, "a
    /// `sendRequest` that already resolved leaves an extension holding an
    /// iterable whose next `next()` rejects," outranks its *mechanism*
    /// sentence, "clear the dictionary"): a request whose promise already
    /// resolved must be left holding an iterable whose next `next()`
    /// rejects, and producing that rejection requires the request object to
    /// still be alive when that later `next()` arrives —
    /// `attemptSettleOrStore`'s `!owner.isDisposed` branch is what answers
    /// it, and it can only run on a request that still exists. A request
    /// still leaves `liveRequests` the ordinary way, once both its cursors
    /// finish (`checkCompletion()`).
    public func dispose() {
        isDisposed = true
        for request in liveRequests.values {
            request.rejectOutstandingForTeardown()
        }
        for request in liveRequests.values {
            request.cancelSource()
        }
        onDidChangeChatModelsEmitter.removeListeners(ownedBy: self)
    }

    // MARK: - vscode.lm.selectChatModels

    /// `implementation` for `vscode.lm.selectChatModels`, handed to
    /// `ExtensionHost.defineVSCodeMember(namespacePath:name:implementation:)`
    /// as-is — the adaptor-with-owner route `MainThreadLanguages.getLanguages`
    /// uses (`MainThreadLanguages.swift:627-629`), not 5.7a-i's host-ceremony
    /// route (`ExtensionHost.swift:1037-1052`, which draws that distinction).
    /// Rejects on a torn-down adaptor, for
    /// the reason `MainThreadLanguages.getLanguages` does.
    public private(set) lazy var selectChatModels: Any = VSCodeAPI.member(
        "vscode.lm.selectChatModels", of: self, whenTornDown: .rejectedPromise
    ) { $0.handleSelectChatModels() }

    /// `vscode.d.ts:20744-20768`'s own doc block says this function "can
    /// yield multiple or no chat models" and extensions "must handle these
    /// cases, esp. when no chat model exists, gracefully" (`:20745-20746`),
    /// and `:20767` spells it out further: "can be empty!" A `provider` with
    /// nothing configured therefore resolves with `[]` — never a rejection,
    /// never a NotImplemented record, never a logged warning — because `[]`
    /// is upstream's *specified* answer for "no model," not this host's
    /// stand-in for one.
    ///
    /// `selectChatModels()` (no argument), `selectChatModels({})` and a
    /// selector with any subset of its four optional fields
    /// (`vscode.d.ts:20325`,`:20331`,`:20337`,`:20343`) set are all legal
    /// calls (`:20769` makes the whole selector optional). `currentArguments()
    /// .first` is `nil` for the first case, and reads as a criteria value with
    /// every field `nil` in `LanguageModelChatSelectorCriteria.make(from:)`
    /// through a different branch than the second case does — an empty
    /// object is `.isObject` and reads four `undefined` properties, while a
    /// missing argument never reaches property access at all. Both branches
    /// have to independently produce "match everything," which is why they
    /// are two tests, not one.
    private func handleSelectChatModels() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let selectorArgument = VSCodeAPI.currentArguments().first
        let criteria = LanguageModelChatSelectorCriteria.make(from: selectorArgument)
        let matches = provider.availableChatModels.filter(criteria.matches)
        let objects = matches.compactMap { model -> JSValue? in
            guard let object = MainThreadLanguageModels.makeChatModelObject(
                for: model, of: self, in: context) else {
                MainThreadLanguageModels.logger.error(
                    """
                    JSValue(newObjectIn:) answered nothing bridging chat \
                    model '\(model.id, privacy: .public)'; it is dropped, so \
                    selectChatModels resolves with fewer models than matched
                    """)
                return nil
            }
            return object
        }
        let arrayValue = MainThreadLanguageModels.arrayValue(of: objects, in: context)
        return VSCodeAPI.resolvedPromise(with: arrayValue, in: context)
    }

    // MARK: - vscode.lm.onDidChangeChatModels

    /// `implementation` for `vscode.lm.onDidChangeChatModels`
    /// (`vscode.d.ts:20742`), installed through
    /// `ExtensionHost.defineVSCodeMember(namespacePath:name:implementation:)`
    /// the same way `selectChatModels` above is
    /// (`MainThreadLanguageModelsTests.swift:86-90`).
    ///
    /// **Raises rather than rejects on a torn-down adaptor.** `Event<T>`
    /// (`vscode.d.ts:1755-1767`, commit
    /// `3addbda66f9e80c3ed1b943822ab823bb6747b02`) answers a `Disposable`
    /// synchronously, not a `Thenable` — `VSCodeAPI.TeardownResponse`'s own
    /// doc (`VSCodeAPI.swift:103-105`, the case itself `:106`) makes that the
    /// deciding question, the same choice `onDidChangeDiagnostics` makes for
    /// the same reason (`MainThreadDiagnostics.swift:421`).
    ///
    /// **Also raises between `dispose()` and deallocation, not just after
    /// deallocation.** `whenTornDown: .raisedException` above only answers
    /// once `VSCodeAPI.member`'s `[weak owner]` capture
    /// (`VSCodeAPI.swift:78-85`) actually observes `self` as `nil` — and
    /// `dispose()` (above) does not deallocate `self`, it only sets
    /// `isDisposed` and drops this adaptor's own listeners. Without a
    /// separate check here, a call arriving in that window would still
    /// reach `body(owner)` with a live `owner`, and would still succeed in
    /// registering a new listener nothing will ever remove. The guard below
    /// closes that window by raising the identical message for both causes,
    /// so an extension sees one answer regardless of which teardown state
    /// it caught.
    public private(set) lazy var onDidChangeChatModels: Any = VSCodeAPI.member(
        "vscode.lm.onDidChangeChatModels", of: self, whenTornDown: .raisedException
    ) { $0.handleOnDidChangeChatModels() }

    private func handleOnDidChangeChatModels() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        guard !isDisposed else {
            return VSCodeAPI.raise(
                "vscode.lm.onDidChangeChatModels is unavailable: this "
                    + "extension's host has been torn down.",
                in: context)
        }
        return onDidChangeChatModelsEmitter.subscribe(
            arguments: VSCodeAPI.currentArguments(), in: context, owner: self)
    }

    /// Re-reads `provider.availableChatModels`, and fires
    /// `onDidChangeChatModels` only when the **set of ids** has actually
    /// changed — mirroring `mainThreadLanguageModels.ts:78-86` (commit
    /// `3addbda66f9e80c3ed1b943822ab823bb6747b02`) in the same order: build
    /// the current set, return early if it equals `lastModelIdentifiers`,
    /// otherwise replace the snapshot *before* firing.
    ///
    /// **Nothing calls this in production yet.** Nothing constructs
    /// `MainThreadLanguageModels` in production yet either (this class's own
    /// doc, above), so there is no model-provider change to observe. The
    /// caller this is waiting for is upstream's own layering: one subscriber
    /// on whatever service eventually fronts real chat-model providers,
    /// fanning out to every extension's `MainThreadLanguageModels` — not a
    /// member on `ExtensionLanguageModelProviding` (Ruling 62: that seam
    /// gains no observer-registration member and no subscription token,
    /// because `MainThreadLanguageModels` is per-extension
    /// (`extensionIdentifier`, above) while `provider` is shared, and a
    /// single sink slot on the seam would serve only one adaptor and would
    /// retain it besides).
    ///
    /// Guards on `isDisposed` for the same reason
    /// `handleOnDidChangeChatModels()` (above) does: `dispose()` does not
    /// deallocate this object, so without this guard a call landing between
    /// `dispose()` and dealloc would still recompute `lastModelIdentifiers`
    /// and still fire into `onDidChangeChatModelsEmitter`, whose listeners
    /// `dispose()` already removed — silently dropped rather than raised,
    /// since this is a Swift-side notification, not a JS-facing call with
    /// anyone to raise to.
    public func availableChatModelsDidChange() {
        guard !isDisposed else { return }
        let currentModelIdentifiers = Set(provider.availableChatModels.map { $0.id })
        guard currentModelIdentifiers != lastModelIdentifiers else { return }
        lastModelIdentifiers = currentModelIdentifiers
        onDidChangeChatModelsEmitter.fire(())
    }

    // MARK: - The LanguageModelChat object-handback pattern

    /// Builds the JS-visible `LanguageModelChat` object for `model`
    /// (`vscode.d.ts:20242-20312`): a `defineProperty` readonly getter for
    /// each of the six data properties — never a plain `setObject`, which
    /// would produce a **writable** property and silently lose the
    /// `readonly` behaviour `vscode.d.ts` declares for every one of them —
    /// and two method blocks, `sendRequest` and `countTokens`, via
    /// `setObject(_:forKeyedSubscript:)`
    /// (`MainThreadWindow.swift:2170-2182` for the accessor descriptor shape,
    /// `:2197-2201` for the readonly-getter variant used here, `:2357-2371`
    /// for the method-block shape). Never constructed by
    /// an extension with `new` — this is the object-handback pattern, not
    /// 5.7a-i's class pattern, because `LanguageModelChat` is an interface an
    /// extension only ever *receives*.
    ///
    /// **No-capture evidence, one sentence per block kind
    /// installed here:**
    /// - Every readonly-getter block captures `model`, a value type, **by
    ///   copy** — there is no reference to weaken and nothing here can retain
    ///   the host, because a `LanguageModelChatDescriptor` holds only
    ///   `String`s and an `Int`.
    /// - `sendRequest`'s block is `VSCodeAPI.member(...)`'s own
    ///   `@convention(block) () -> JSValue?`, which already captures its
    ///   owner (`languageModels`) weakly and rejects when it is gone — the
    ///   same helper `selectChatModels` (above) uses, so this member gets the
    ///   identical teardown answer without a second hand-written weak
    ///   capture in this file. `handleSendRequest(for:)`, below, is the body
    ///   `VSCodeAPI.member` calls with the still-live owner.
    /// - `countTokens`'s block captures nothing but its own arguments —
    ///   `extractedText(from:)` and `approximateTokenCount(for:)` are pure
    ///   functions of whatever `JSValue` the extension passed, so there is
    ///   nothing to weaken.
    private static func makeChatModelObject(
        for model: LanguageModelChatDescriptor,
        of languageModels: MainThreadLanguageModels,
        in context: JSContext
    ) -> JSValue? {
        guard let object = JSValue(newObjectIn: context) else { return nil }

        MainThreadWindow.installReadonlyGetter(on: object, name: "name") { model.name }
        MainThreadWindow.installReadonlyGetter(on: object, name: "id") { model.id }
        MainThreadWindow.installReadonlyGetter(on: object, name: "vendor") { model.vendor }
        MainThreadWindow.installReadonlyGetter(on: object, name: "family") { model.family }
        MainThreadWindow.installReadonlyGetter(on: object, name: "version") { model.version }
        MainThreadWindow.installReadonlyGetter(on: object, name: "maxInputTokens") { model.maxInputTokens }

        let sendRequest = VSCodeAPI.member(
            "vscode.LanguageModelChat.sendRequest", of: languageModels,
            whenTornDown: .rejectedPromise
        ) { owner in owner.handleSendRequest(for: model) }
        object.setObject(sendRequest, forKeyedSubscript: "sendRequest" as NSString)

        let countTokens: @convention(block) () -> JSValue? = {
            MainActor.assumeIsolated {
                guard let context = JSContext.current() else { return UncheckedJSValueBox(value: nil) }
                let argument = VSCodeAPI.currentArguments().first
                let text = MainThreadLanguageModels.extractedText(from: argument)
                let count = MainThreadLanguageModels.approximateTokenCount(for: text)
                return UncheckedJSValueBox(value: VSCodeAPI.resolvedPromise(with: count, in: context))
            }.value
        }
        object.setObject(countTokens, forKeyedSubscript: "countTokens" as NSString)

        return object
    }

    // MARK: - LanguageModelChat.countTokens

    /// Extracts the text `countTokens` (`vscode.d.ts:20311`) should count
    /// from whichever of its two argument shapes arrived: a bare `string`,
    /// or a `LanguageModelChatMessage`
    /// (`LanguageModelMessageVocabulary.swift`, task 5.7a-i) whose `content`
    /// is *always* an array of parts after that class's own accessor pair
    /// coerces a bare-string assignment into
    /// `[new LanguageModelTextPart(value)]` — reading `content` as a string
    /// here would read `undefined` off an array and silently count zero for
    /// every message, string-sourced or not. Only `.value`-bearing parts
    /// (`LanguageModelTextPart`, `LanguageModelPromptTsxPart`) contribute
    /// text; a part with no string `.value` (`LanguageModelDataPart`,
    /// `LanguageModelToolCallPart`, `LanguageModelToolResultPart`) is
    /// skipped rather than guessed at, because guessing was out of scope for
    /// 5.7a-ii; `sendRequest`'s own message reader (`parseMessages(from:)`,
    /// below) reuses this same rule via `arrayElements(of:)` rather than
    /// disagreeing with it about what counts as text.
    private static func extractedText(from argument: JSValue?) -> String {
        guard let argument else { return "" }
        if argument.isString, let string = argument.toString() {
            return string
        }
        guard argument.isObject, let content = argument.forProperty("content") else { return "" }
        // A message built through `LanguageModelChatMessage` always has an
        // array here, because that class's accessor pair coerces a bare-string
        // assignment into `[new LanguageModelTextPart(value)]`. A message that
        // did not come through it — an object literal, a `JSON.parse`d
        // message, a polyfill — carries the plain string `vscode.d.ts` also
        // allows, and reading only the array shape turned that into an empty
        // prompt that was still forwarded to the provider and billed.
        if content.isString, let string = content.toString() { return string }
        guard let elements = arrayElements(of: content) else { return "" }
        let parts = elements.compactMap { part -> String? in
            guard let value = part.forProperty("value"), value.isString else { return nil }
            return value.toString()
        }
        return parts.joined()
    }

    /// Reads a JS array into a Swift array of its elements, via
    /// `.atIndex(_:)` element by element. This is `extractedText(from:)`'s
    /// own array-reading logic, factored out so `parseMessages(from:)`
    /// (below) reads the top-level `LanguageModelChatMessage[]` argument the
    /// same way `extractedText(from:)` reads one message's `content` —
    /// one reader, not two that could quietly disagree.
    ///
    /// The length goes through `VSCodeAPI.arrayLength(of:)`, which is what
    /// keeps `reserveCapacity` honest: a `length` an extension chose —
    /// `{length: 2_100_000_000}` — reserved sixteen gigabytes and then
    /// walked two billion indices on the main actor. That helper also
    /// demands a real array rather than any object carrying a `length`, so
    /// a string (`"abc".length === 3`, no `atIndex`) reads as absent here
    /// instead of as three undefined elements.
    private static func arrayElements(of value: JSValue?) -> [JSValue]? {
        guard let value, let count = VSCodeAPI.arrayLength(of: value) else { return nil }
        guard count > 0 else { return [] }
        var elements: [JSValue] = []
        elements.reserveCapacity(count)
        for index in 0..<count {
            guard let element = value.atIndex(index) else { continue }
            elements.append(element)
        }
        return elements
    }

    /// The actual number `countTokens` answers with. A real tokenizer is a
    /// model provider's business, not this task's — the same "no production
    /// conformer" ruling that keeps `ExtensionLanguageModelProviding` to one
    /// member keeps this a plain, deterministic word count rather than a
    /// second protocol requirement invented to route through a provider that
    /// does not exist yet. Whitespace-delimited so an empty string counts
    /// zero, matching zero words extracted.
    private static func approximateTokenCount(for text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    // MARK: - Bridging a Swift array to a fresh JS array

    /// Builds a JS array from `values` via `JSValue(object:in:)`, falling
    /// back to `NSNull()` on failure — the same shape
    /// `MainThreadWindow.swift:2716-2726`'s own `arrayValue(of:in:)` uses.
    /// That one is `private static`, so it is unreachable
    /// from here even though both files are in this module; this is a copy,
    /// not a shared helper. `JSValue(object:in:)` bridges a *new* JS array on
    /// every call, so mutating one call's result never affects the next.
    private static func arrayValue(of values: [JSValue], in context: JSContext) -> Any {
        JSValue(object: values, in: context) ?? NSNull()
    }

    // MARK: - LanguageModelChat.sendRequest

    /// The body `makeChatModelObject`'s `VSCodeAPI.member(...)` call hands
    /// `sendRequest` to, with a still-live `self` already resolved from that
    /// helper's own weak capture. Builds the `Thenable`
    /// `vscode.d.ts:20302` declares. Every failure path here produces
    /// a **rejected** promise, never a synchronous throw — the defect the
    /// stub this replaces had.
    ///
    /// All three declared arguments are read (`vscode.d.ts:20302`:
    /// `sendRequest(messages: LanguageModelChatMessage[], options?:
    /// LanguageModelChatRequestOptions, token?: CancellationToken)`):
    /// 1. **the messages.** A message whose `role` is neither `User` (1) nor
    ///    `Assistant` (2) rejects the whole call — `messageRole(_:)` and
    ///    `refuseUnsupportedRole(_:in:)`.
    /// 2. **the options.** `justification` reaches the seam;
    ///    `modelOptions`/`tools`/`toolMode` are recorded by
    ///    `ledgerDegradedOptions(_:)`.
    /// 3. **the cancellation token — honoured**, not accepted and ignored
    ///    the way `MainThreadWindow`'s `showQuickPick`/`showInputBox` tokens
    ///    are. A token already cancelled when the request would start
    ///    rejects the promise instead; one cancelled afterwards reaches
    ///    `LanguageModelResponseRequest.cancelBySourceToken()`, which stops
    ///    the pump and fails both cursors by the same `sourceFailure` route
    ///    a stream that threw takes. Because the token is acted on, it is
    ///    not a degraded argument and nothing is recorded for it.
    ///    `LanguageModelCancellation` states what is and is not read off it.
    private func handleSendRequest(for model: LanguageModelChatDescriptor) -> JSValue? {
        // `nil` is the only possible answer here, not a shortfall of the
        // rule that every failure path is a rejected promise: with no
        // `JSContext`, there is nowhere to construct a `JSValue`/promise
        // *in*, rejected or otherwise. A brief requirement that is not
        // constructible is a brief defect (Ruling 83); the honest code
        // stands, documented at the exact site rather than worked around.
        guard let context = JSContext.current() else { return nil }
        guard !isDisposed else {
            return VSCodeAPI.rejectedPromise(
                message: "vscode.LanguageModelChat.sendRequest is unavailable: " +
                    "this extension's host has been torn down.",
                in: context)
        }

        let arguments = VSCodeAPI.currentArguments()
        let messages: [ExtensionLanguageModelMessage]
        switch MainThreadLanguageModels.parseMessages(from: arguments.first) {
        case .parsed(let parsed):
            messages = parsed
        case .unsupportedRole(let role):
            return refuseUnsupportedRole(role, in: context)
        }
        let optionsArgument = arguments.count > 1 ? arguments[1] : nil
        let options = MainThreadLanguageModels.parseRequestOptions(optionsArgument)
        ledgerDegradedOptions(options)
        let cancellation = LanguageModelCancellation(
            token: arguments.count > 2 ? arguments[2] : nil)

        return JSValue(newPromiseIn: context) { [weak self] resolveValue, rejectValue in
            guard let resolveValue, let rejectValue else { return }
            let settlement = PromiseSettlementBox(resolve: resolveValue, reject: rejectValue)
            Task { @MainActor [weak self] in
                guard let self, !self.isDisposed else {
                    rejectLanguageModelTornDown(
                        settlement.reject, memberPath: "vscode.LanguageModelChat.sendRequest")
                    return
                }
                guard !cancellation.isCancelled else {
                    rejectLanguageModelError(
                        settlement.reject,
                        message: "vscode.LanguageModelChat.sendRequest failed: " +
                            "\(LanguageModelRequestCancelled())")
                    return
                }
                do {
                    let stream = try await self.provider.streamResponse(
                        for: model,
                        messages: messages,
                        justification: options.justification,
                        extensionIdentifier: self.extensionIdentifier)
                    guard !self.isDisposed, let resultContext = settlement.resolve.context else {
                        rejectLanguageModelTornDown(
                            settlement.reject,
                            memberPath: "vscode.LanguageModelChat.sendRequest")
                        return
                    }
                    let request = LanguageModelResponseRequest(
                        owner: self, cancellation: cancellation)
                    self.liveRequests[request.id] = request
                    guard let responseObject = request.makeResponseObject(in: resultContext) else {
                        self.liveRequests.removeValue(forKey: request.id)
                        rejectLanguageModelError(
                            settlement.reject,
                            message: "vscode.LanguageModelChat.sendRequest could not " +
                                "build its response object.")
                        return
                    }
                    request.startPump(consuming: stream)
                    cancellation.whenCancelled { [weak request] in request?.cancelBySourceToken() }
                    settlement.resolve.call(withArguments: [responseObject])
                } catch {
                    rejectLanguageModelError(
                        settlement.reject,
                        message: "vscode.LanguageModelChat.sendRequest failed: \(error)")
                }
            }
        }
    }

    /// Records `modelOptions`/`tools`/`toolMode` into `notImplementedLedger`
    /// when present, per Ruling 54 — they make `sendRequest` answer
    /// *wrongly* (promising tool calls that can never arrive) rather than
    /// merely uncancellably, which is the distinction
    /// `MainThreadWindow.swift:830-836` draws between a degraded argument
    /// and an absent member.
    private func ledgerDegradedOptions(_ options: ParsedRequestOptions) {
        if options.hasModelOptions {
            notImplementedLedger.record(
                memberPath: "vscode.LanguageModelChatRequestOptions.modelOptions",
                extensionIdentifier: extensionIdentifier)
        }
        if options.hasTools {
            notImplementedLedger.record(
                memberPath: "vscode.LanguageModelChatRequestOptions.tools",
                extensionIdentifier: extensionIdentifier)
        }
        if options.hasToolMode {
            notImplementedLedger.record(
                memberPath: "vscode.LanguageModelChatRequestOptions.toolMode",
                extensionIdentifier: extensionIdentifier)
        }
    }

    // MARK: - Reading sendRequest's arguments

    /// What `parseMessages(from:)` answers: every message read, or the first
    /// one whose `role` this host does not implement. There is no third
    /// case — a message that is not an object, or has no `content`, still
    /// parses, to an empty `text`.
    private enum ParsedMessages {
        case parsed([ExtensionLanguageModelMessage])
        case unsupportedRole(UnsupportedRole)
    }

    /// A `role` that is neither `User` (1) nor `Assistant` (2), carried as
    /// far as the rejection so the extension is told what it sent.
    /// `number` is the value when the role was a number at all, which is
    /// what distinguishes upstream's `System = 3` from arbitrary garbage.
    private struct UnsupportedRole {
        var described: String
        var number: Int32?
    }

    /// Reads `sendRequest`'s first argument, `LanguageModelChatMessage[]`
    /// (`vscode.d.ts:20302`), via `arrayElements(of:)` — the same
    /// array-reading logic `extractedText(from:)` uses for one message's
    /// own `content`.
    private static func parseMessages(from argument: JSValue?) -> ParsedMessages {
        var messages: [ExtensionLanguageModelMessage] = []
        for element in arrayElements(of: argument) ?? [] {
            guard let role = messageRole(element.forProperty("role")) else {
                return .unsupportedRole(describeRole(element.forProperty("role")))
            }
            messages.append(
                ExtensionLanguageModelMessage(
                    role: role,
                    name: optionalStringValue(element.forProperty("name")),
                    text: extractedText(from: element)))
        }
        return .parsed(messages)
    }

    /// `vscode.LanguageModelChatMessageRole` is `{ User: 1, Assistant: 2 }`
    /// (`LanguageModelMessageVocabulary.swift:172`). Anything else answers
    /// `nil`, which `handleSendRequest` turns into a rejected promise: the
    /// role is a writable own property assigned from an unvalidated
    /// constructor argument (`LanguageModelMessageVocabulary.swift:239`,
    /// and `:280-281` states that instances are never frozen), so an
    /// out-of-vocabulary value is reachable — upstream's `System = 3`
    /// (`extHostTypes.ts:3886-3890`) among them — and reading one as
    /// `.user` would send the model a message the extension did not write.
    ///
    /// The number is read with `Int32(exactly:)` rather than `toInt32()`,
    /// the way `MainThreadWindow.swift:1844` reads its own enum argument.
    /// `toInt32()` is ECMA-262 ToInt32: it truncates the fraction and then
    /// wraps modulo 2³², so `role: 4294967297` — a perfectly ordinary
    /// double — arrives as `1` and is read as `.user`, and `role: 1.5`
    /// arrives as `1` too. Both are out-of-vocabulary values that must
    /// reject, not values that round into a role.
    private static func messageRole(_ value: JSValue?) -> ExtensionLanguageModelMessage.Role? {
        guard let value, value.isNumber, let number = Int32(exactly: value.toDouble()) else {
            return nil
        }
        switch number {
        case 1: return .user
        case 2: return .assistant
        default: return nil
        }
    }

    /// Names an unsupported `role` for the rejection message, without
    /// calling `toString()` on an arbitrary object — an extension's own
    /// `toString` would then run inside this reader.
    ///
    /// `number` is filled in only for a value that *is* an `Int32`, because
    /// it is what decides whether a ledger row is filed for upstream's
    /// `System = 3`. Read through `toInt32()`'s wrapping, `role: 4294967299`
    /// answered `3` and filed a row saying the extension asked for
    /// `LanguageModelChatMessageRole.System`, which it had not. A number
    /// outside the range still names itself in the rejection — the
    /// extension author needs to see the value they passed — it just does
    /// not claim to be a member of the vocabulary.
    private static func describeRole(_ value: JSValue?) -> UnsupportedRole {
        guard let value else { return UnsupportedRole(described: "no value", number: nil) }
        if value.isNumber {
            let double = value.toDouble()
            guard let number = Int32(exactly: double) else {
                return UnsupportedRole(described: "\(double)", number: nil)
            }
            return UnsupportedRole(described: "\(number)", number: number)
        }
        if value.isUndefined { return UnsupportedRole(described: "undefined", number: nil) }
        if value.isNull { return UnsupportedRole(described: "null", number: nil) }
        if value.isString { return UnsupportedRole(described: "a string", number: nil) }
        if value.isBoolean { return UnsupportedRole(described: "a boolean", number: nil) }
        return UnsupportedRole(described: "a non-numeric value", number: nil)
    }

    /// Rejects the whole `sendRequest` call for an unsupported `role`, and
    /// records the one unsupported value that is a real part of upstream's
    /// vocabulary. `LanguageModelMessageVocabulary.swift:169-173` names
    /// `System = 3` PROPOSED and out of scope; an extension that reaches for
    /// it is reaching for a member this host does not implement, which is
    /// what `notImplementedLedger` is for. Any other value is not an
    /// unimplemented member, so nothing is recorded for it.
    private func refuseUnsupportedRole(_ role: UnsupportedRole, in context: JSContext) -> JSValue? {
        if role.number == 3 {
            notImplementedLedger.record(
                memberPath: "vscode.LanguageModelChatMessageRole.System",
                extensionIdentifier: extensionIdentifier)
        }
        return VSCodeAPI.rejectedPromise(
            message: "vscode.LanguageModelChat.sendRequest: every message's `role` must be " +
                "vscode.LanguageModelChatMessageRole.User (1) or .Assistant (2); " +
                "received \(role.described).",
            in: context)
    }

    /// `sendRequest`'s second argument, `LanguageModelChatRequestOptions?`
    /// (`vscode.d.ts:20387-20417`). `justification` reaches the seam
    /// (Ledger Ruling 4); `modelOptions`/`tools`/`toolMode` are read only for
    /// presence, for `ledgerDegradedOptions(_:)` — Ruling 54 stops at "was
    /// one passed," not "what was in it."
    private struct ParsedRequestOptions {
        var justification: String?
        var hasModelOptions: Bool
        var hasTools: Bool
        var hasToolMode: Bool
    }

    private static func parseRequestOptions(_ value: JSValue?) -> ParsedRequestOptions {
        guard let value, value.isObject else {
            return ParsedRequestOptions(
                justification: nil, hasModelOptions: false, hasTools: false,
                hasToolMode: false)
        }
        return ParsedRequestOptions(
            justification: optionalStringValue(value.forProperty("justification")),
            hasModelOptions: isPresentField(value.forProperty("modelOptions")),
            hasTools: isPresentField(value.forProperty("tools")),
            hasToolMode: isPresentField(value.forProperty("toolMode")))
    }

    /// `nil` unless `value` is a JS string — mirrors
    /// `LanguageModelChatSelectorCriteria.stringOptionalField`, duplicated
    /// rather than shared because that one is `private` to its own type.
    private static func optionalStringValue(_ value: JSValue?) -> String? {
        guard let value, value.isString, let string = value.toString() else { return nil }
        return string
    }

    /// `true` unless `value` is absent, `undefined` or `null` — an option
    /// left unset by the extension is not "present," whatever its declared
    /// type would otherwise allow through.
    private static func isPresentField(_ value: JSValue?) -> Bool {
        guard let value else { return false }
        return !value.isUndefined && !value.isNull
    }
}

// MARK: - Shared plumbing for LanguageModelChat.sendRequest's response

/// The error `scan(kind:in:)` fails `.stream` with when a response part
/// cannot be bridged into a JS value —
/// distinct from `sourceFailure`, which is the seam's own reported error:
/// this one is a bridging defect in this host, discovered only once a
/// part actually needs converting.
private struct LanguageModelPartBridgingFailure: Error, CustomStringConvertible {
    let partKind: String
    var description: String {
        "could not bridge a '\(partKind)' response part into a JS value"
    }
}

/// The error a request fails with when the `CancellationToken` handed to
/// `sendRequest` is cancelled. Distinct from `LanguageModelPartBridgingFailure`
/// (a defect in this host) and from the seam's own thrown error (a failure in
/// the provider): this one is the extension asking for the request to stop.
private struct LanguageModelRequestCancelled: Error, CustomStringConvertible {
    var description: String {
        "the CancellationToken passed to sendRequest was cancelled"
    }
}

/// The `CancellationToken` `sendRequest` was passed (`vscode.d.ts:20302`),
/// reduced to the two things this adaptor acts on: whether it is already
/// cancelled, and one callback for when it becomes cancelled.
///
/// The token is read by duck-typing, not by `isInstance(of:)`, because this
/// host installs no `CancellationToken` type and no `CancellationTokenSource`
/// for an extension to build one from — the object that arrives here is
/// whatever the extension brought. What is read is exactly the two members
/// `vscode.d.ts:1664` (`isCancellationRequested: boolean`) and `:1669`
/// (`readonly onCancellationRequested: Event<any>`) declare; an argument that
/// is absent, is not an object, or whose `onCancellationRequested` is not a
/// `Function` leaves this object permanently un-cancelled rather than
/// failing the call, because a token is optional in the declared signature.
///
/// The listener block captures `self` weakly, so subscribing does not keep
/// this object — or, through `whenCancelled`'s body, the request — alive: a
/// token outliving its request fires into a `nil` and does nothing. That is
/// why somebody else has to own it, and
/// `LanguageModelResponseRequest.cancellation` does: held by the `Task`
/// alone, it died with the promise's resolution and every later cancel was
/// a silent no-op.
@MainActor
private final class LanguageModelCancellation {
    private(set) var isCancelled = false
    private var body: (() -> Void)?

    init(token: JSValue?) {
        guard let token, token.isObject else { return }
        if let requested = token.forProperty("isCancellationRequested"), requested.toBool() {
            isCancelled = true
        }
        guard let subscribe = token.forProperty("onCancellationRequested"),
              let context = token.context,
              let functionConstructor = context.objectForKeyedSubscript("Function"),
              subscribe.isInstance(of: functionConstructor) else {
            return
        }
        let listener: @convention(block) () -> Void = { [weak self] in
            MainActor.assumeIsolated { self?.cancel() }
        }
        subscribe.call(withArguments: [listener])
    }

    /// Runs `body` when the token is cancelled — immediately if it already
    /// was, which is what closes the window between the caller's
    /// `isCancelled` check and this call.
    func whenCancelled(_ body: @escaping () -> Void) {
        if isCancelled {
            body()
        } else {
            self.body = body
        }
    }

    private func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        let body = self.body
        self.body = nil
        body?()
    }
}

/// The wording `MainThreadWindow.rejectTornDown(_:path:)` uses
/// (`MainThreadWindow.swift:2746`), rebuilt at file scope because that one is
/// `private` to its own type, and because both `MainThreadLanguageModels` and
/// `LanguageModelResponseRequest` below need it.
private func rejectLanguageModelTornDown(_ reject: JSValue, memberPath: String) {
    rejectLanguageModelError(
        reject,
        message: "\(memberPath) is unavailable: this extension's host has been torn down.")
}

private func rejectLanguageModelError(_ reject: JSValue, message: String) {
    guard let context = reject.context,
          let error = JSValue(newErrorFromMessage: message, in: context) else {
        return
    }
    reject.call(withArguments: [error])
}

/// Builds the outbound JS value for one response part, from the *same*
/// cached vocabulary `vscode.LanguageModelTextPart`/`.LanguageModelToolCallPart`
/// are exposed under (`VSCodeAPI.installLanguageModelVocabulary(in:)`), so
/// an extension's `instanceof` check against those globals succeeds rather
/// than comparing against a second, freshly-built prototype. `.end` never
/// reaches here — both cursors intercept it before calling this (Ruling 52).
///
/// Takes the two constructors already resolved, rather than resolving them
/// itself: `installLanguageModelVocabulary(in:)` does a
/// `objectForKeyedSubscript` plus a `forProperty` per vocabulary member and
/// allocates a fresh `[String: JSValue]`, and calling it once per streamed
/// part was pure overhead on a token stream's hot path.
/// `LanguageModelResponseRequest.makeResponseObject(in:)` is the
/// one caller that still routes through `installLanguageModelVocabulary`,
/// exactly once per request, and hands the results here on every part.
@MainActor
private func languageModelResponsePartJSValue(
    for part: ExtensionLanguageModelResponsePart,
    textPartConstructor: JSValue?,
    toolCallPartConstructor: JSValue?,
    in context: JSContext
) -> JSValue? {
    switch part {
    case .text(let text):
        guard let ctor = textPartConstructor else { return nil }
        return ctor.construct(withArguments: [text])
    case .toolCall(let id, let name, let argumentsJSON):
        guard let ctor = toolCallPartConstructor else { return nil }
        let input = languageModelParsedJSON(argumentsJSON, in: context)
        return ctor.construct(withArguments: [id, name, input])
    case .end:
        return nil
    }
}

/// `LanguageModelToolCallPart(callId, name, input)`
/// (`LanguageModelMessageVocabulary.swift:192-196`) takes `input` as an
/// `object`, not a string, so `argumentsJSON`'s bytes are parsed through
/// the context's own `JSON.parse` rather than handed over as a raw string.
///
/// **Through `VSCodeAPI.call`, because `JSON.parse` throws.** `argumentsJSON`
/// is whatever the *model* emitted for a tool call, so malformed JSON is an
/// ordinary outcome and not a bug in anything local. A bare
/// `parse.call(withArguments:)` lets the resulting `SyntaxError` leave
/// JavaScriptCore through `notifyException:`, which `ExtensionHost`'s
/// `exceptionHandler` records into `pendingException` — and that is read after
/// `callActivate`, so a bad tool call arriving while an `async activate()` was
/// still in flight failed the *extension's activation*, naming a JSON syntax
/// error as the reason. Keeping a throw out of the host's bookkeeping is the
/// single thing `VSCodeAPI.call` exists for.
///
/// `null` is the answer in every failure branch, unchanged: the part is still
/// delivered, with an `input` that says the arguments could not be read,
/// rather than the whole response dying over one malformed tool call. The
/// throw is logged so the malformed payload is not invisible.
@MainActor
private func languageModelParsedJSON(_ data: Data, in context: JSContext) -> JSValue {
    guard let jsonString = String(data: data, encoding: .utf8),
          let json = context.globalObject.forProperty("JSON"),
          let parse = json.forProperty("parse") else {
        return JSValue(nullIn: context)
    }
    switch VSCodeAPI.call(parse, thisArg: json, arguments: [jsonString]) {
    case .returned(let parsed):
        return parsed ?? JSValue(nullIn: context)
    case .threw(let exception):
        MainThreadLanguageModels.logger.error(
            """
            A language model tool call carried arguments JSON that would not parse, so its \
            input is null: \(exception.toString() ?? "unknown error", privacy: .public)
            """)
        return JSValue(nullIn: context)
    case .unavailable:
        return JSValue(nullIn: context)
    }
}

/// A small IIFE that assigns `target[Symbol.asyncIterator]`,
/// `target.next` and `target.return` — the `Symbol`-keyed-member idiom
/// `MainThreadDiagnostics.swift`'s `symbolIteratorInstallerSource` uses for
/// `Symbol.iterator` (evaluate a snippet that assigns the computed key,
/// since `JSValue.setObject(_:forKeyedSubscript:)` takes no `Symbol`).
/// Unlike that one, there is no live array to borrow an iterator from here
/// — an async stream's values arrive over time — so `next`/`return` are
/// real hand-written methods, supplied as the two blocks passed in. `target`
/// is both the iterable and its own iterator: `[Symbol.asyncIterator]`
/// returns `target` itself, the common combined-iterable-iterator shape for
/// a single-pass source.
private let languageModelIteratorInstallerSource = """
(function (target, nextFn, returnFn) {
    target[Symbol.asyncIterator] = function () { return target; };
    target.next = nextFn;
    target.return = returnFn;
})
"""

private func installLanguageModelAsyncIterator(
    on target: JSValue,
    next: @escaping @convention(block) () -> JSValue?,
    returning: @escaping @convention(block) (JSValue?) -> JSValue?,
    in context: JSContext
) {
    guard let installer = context.evaluateScript(languageModelIteratorInstallerSource)
    else { return }
    installer.call(withArguments: [target, next, returning])
}

// MARK: - The per-request response bridge (Ruling 53)

/// One live `sendRequest` response. The seam hands back a single
/// `AsyncThrowingStream<ExtensionLanguageModelResponsePart, Error>`, which is
/// single-consumption, but `vscode.LanguageModelChatResponse`
/// (`vscode.d.ts:20194-20235`) exposes **two** independent async iterables,
/// `stream` and `text` — an extension may read either, both, or neither to
/// completion, and iterating one must never advance the other. This class is
/// the "tee": one `Task` (`startPump(consuming:)`) pumps the seam's stream
/// into `buffer` exactly once, and two cursors, `streamCursor`/`textCursor`,
/// each track an independent read position into that same buffer.
///
/// `@MainActor`, and `MainThreadLanguageModels.liveRequests` keeps it as the
/// sole strong reference — the same shape `MainThreadWindow` uses for
/// `statusBarItems` (`MainThreadWindow.swift:896`, doc `:892-895`). Every
/// JS-facing block this class hands to `installLanguageModelAsyncIterator`
/// captures it **weakly** and re-obtains its `JSContext` at call time
/// (Ledger Ruling 2), and `startPump(consuming:)`'s own `Task` captures it
/// weakly too — the same rule, not an exception to it. A request already
/// gone by the time that `Task` starts running exits immediately at its
/// `guard let self else { return }`; past that guard, though, the binding
/// is strong for the rest of the task body, so a *running* pump holds this
/// object alive across every `for try await` suspension until `source` ends
/// or `cancelSource()` cancels it. What keeps `buffer` growing even while
/// no cursor is currently awaited (Ruling 53's "the pump is not lazy" rule)
/// is `liveRequests` holding this object reachable from *outside* that
/// window — before the pump has started, and after it has stopped — not the
/// pump `Task` holding itself alive. That is exactly why
/// `checkCompletion()` cancels the pump (`cancelSource()`) *before*
/// removing the entry from `liveRequests`: the running-task/strong-self
/// cycle above needs to be cancelled, not merely orphaned by removing the
/// one other reference to it.
@MainActor
private final class LanguageModelResponseRequest {

    enum CursorKind {
        case stream
        case text

        var memberPath: String {
            switch self {
            case .stream: return "vscode.LanguageModelChatResponse.stream"
            case .text: return "vscode.LanguageModelChatResponse.text"
            }
        }
    }

    /// One reader's position into `buffer`, whether that reader itself has
    /// finished — independently of the source and of the other reader — and
    /// its one outstanding `next()` waiter, if any. Never more than one
    /// waiter per cursor: `for await…of` never issues a second `next()`
    /// before the first settles (gate zero's `maxOutstanding == 1`, T1).
    private struct CursorState {
        var index = 0
        var isFinished = false
        var waiter: PromiseSettlementBox?
    }

    private enum ScanOutcome {
        case value(JSValue)
        case done
        case pending
        case failed(Error)
    }

    let id = UUID()
    private weak var owner: MainThreadLanguageModels?
    private var buffer: [ExtensionLanguageModelResponsePart] = []
    private var sourceFailure: Error?
    private var isSourceFinished = false
    private var streamCursor = CursorState()
    private var textCursor = CursorState()
    private var pumpTask: Task<Void, Never>?

    /// The two constructors `.stream` parts bridge through, resolved once —
    /// when `makeResponseObject(in:)` builds this request's response object
    /// — rather than re-resolved via `VSCodeAPI
    /// .installLanguageModelVocabulary(in:)` on every streamed part. `nil`
    /// only if the vocabulary was not
    /// installed by the time this request's response object was built;
    /// `makeResponseObject(in:)` is the one caller that still routes
    /// through `installLanguageModelVocabulary`, exactly once per request,
    /// so nothing about how the constructors are obtained changed, only how
    /// often.
    private var textPartConstructor: JSValue?
    private var toolCallPartConstructor: JSValue?

    /// The request's own `token` argument, held here for the request's
    /// whole life. It has to be held *somewhere* that outlives
    /// `handleSendRequest`'s `Task`: the token object on the JS side holds
    /// only the listener block, which captures the cancellation weakly, so
    /// a cancellation owned by the `Task` alone was deallocated the moment
    /// the promise resolved — and every cancel after that, which is nearly
    /// all of them, fired into a `nil` and did nothing while the provider
    /// kept streaming and billing. `liveRequests` keeps this request
    /// reachable for exactly as long as a cancel could still matter, so it
    /// is the right owner; the edge back is `whenCancelled`'s
    /// `[weak request]`, so there is no cycle.
    private let cancellation: LanguageModelCancellation

    init(owner: MainThreadLanguageModels, cancellation: LanguageModelCancellation) {
        self.owner = owner
        self.cancellation = cancellation
    }

    /// Starts the one pump that drains `source` into `buffer`. Called at
    /// most once, and only once this request is both stored in
    /// `liveRequests` — so a part arriving on the very first loop iteration
    /// always has somewhere to be recorded — and past
    /// `makeResponseObject(in:)`, whose failure branch abandons the request:
    /// a pump started before that guard would be left running with the one
    /// reference that could cancel it already removed.
    func startPump(consuming source: AsyncThrowingStream<ExtensionLanguageModelResponsePart, Error>) {
        pumpTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await part in source {
                    self.buffer.append(part)
                    self.wake(.stream)
                    self.wake(.text)
                    if case .end = part { break }
                }
                self.isSourceFinished = true
            } catch {
                self.sourceFailure = error
                self.isSourceFinished = true
            }
            self.wake(.stream)
            self.wake(.text)
        }
    }

    /// Builds the `vscode.LanguageModelChatResponse` object
    /// (`vscode.d.ts:20194-20235`) — exactly its two declared members,
    /// `stream` and `text`. Measured: there is no third member to carry
    /// anything else, which is why `ExtensionLanguageModelResponsePart.end`'s
    /// `stopReason` is dropped rather than surfaced here.
    func makeResponseObject(in context: JSContext) -> JSValue? {
        if let vocabulary = VSCodeAPI.installLanguageModelVocabulary(in: context) {
            textPartConstructor = vocabulary["LanguageModelTextPart"]
            toolCallPartConstructor = vocabulary["LanguageModelToolCallPart"]
        }
        guard let object = JSValue(newObjectIn: context),
              let streamValue = makeAsyncIterable(kind: .stream, in: context),
              let textValue = makeAsyncIterable(kind: .text, in: context) else {
            return nil
        }
        object.setObject(streamValue, forKeyedSubscript: "stream" as NSString)
        object.setObject(textValue, forKeyedSubscript: "text" as NSString)
        return object
    }

    /// `dispose()`'s step 2: rejects whatever `next()` waiter each cursor
    /// currently holds with the torn-down wording, using that cursor's own
    /// `memberPath`. Leaves `buffer`/`pumpTask` alone — step 3, on the
    /// adaptor, handles those.
    func rejectOutstandingForTeardown() {
        for kind in [CursorKind.stream, .text] {
            guard let settlement = waiter(for: kind) else { continue }
            setWaiter(nil, for: kind)
            rejectLanguageModelTornDown(settlement.reject, memberPath: kind.memberPath)
        }
    }

    /// `dispose()`'s step 3, for one request: stop pumping the source.
    func cancelSource() {
        pumpTask?.cancel()
        pumpTask = nil
    }

    /// The `CancellationToken` handed to `sendRequest` was cancelled. Puts
    /// this request into the exact state a source that *threw* leaves it in
    /// — pump stopped, `sourceFailure` set, source finished — so every
    /// outstanding and future `next()` settles through `scan(kind:in:)`'s
    /// existing `sourceFailure` branch rather than through a second
    /// cancellation path of its own. Parts already buffered are still
    /// delivered before that failure, because `scan(kind:in:)` reads
    /// `sourceFailure` only once the buffer is exhausted for that cursor.
    /// A source that has already finished is left alone: there is nothing
    /// left to cancel, and overwriting its outcome would turn a completed
    /// response into a failed one.
    func cancelBySourceToken() {
        guard !isSourceFinished else { return }
        cancelSource()
        sourceFailure = LanguageModelRequestCancelled()
        isSourceFinished = true
        wake(.stream)
        wake(.text)
    }

    // MARK: - The async-iterable factory

    private func makeAsyncIterable(kind: CursorKind, in context: JSContext) -> JSValue? {
        guard let target = JSValue(newObjectIn: context) else { return nil }
        let next: @convention(block) () -> JSValue? = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let context = JSContext.current() else {
                    return UncheckedJSValueBox(value: nil)
                }
                return UncheckedJSValueBox(value: self.next(kind: kind, in: context))
            }.value
        }
        let returning: @convention(block) (JSValue?) -> JSValue? = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let context = JSContext.current() else {
                    return UncheckedJSValueBox(value: nil)
                }
                return UncheckedJSValueBox(value: self.returned(kind: kind, in: context))
            }.value
        }
        installLanguageModelAsyncIterator(on: target, next: next, returning: returning, in: context)
        return target
    }

    /// One cursor's `next()`. Builds a promise via
    /// `JSValue(newPromiseIn:executor:)`: if `scan(kind:in:)` can already
    /// answer, it settles synchronously inside the executor, the same way
    /// `MainThreadWindow`'s promises do; if the buffer has nothing yet for
    /// this cursor (`.pending`), the resolve/reject pair becomes this
    /// cursor's one outstanding waiter, settled later by `wake(_:)`.
    private func next(kind: CursorKind, in context: JSContext) -> JSValue? {
        JSValue(newPromiseIn: context) { [weak self] resolveValue, rejectValue in
            guard let resolveValue, let rejectValue else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let settlement = PromiseSettlementBox(
                    resolve: resolveValue, reject: rejectValue)
                self.attemptSettleOrStore(kind: kind, settlement: settlement, in: context)
            }
        }
    }

    /// One cursor's `return(value)` — called by `for await…of` on a `break`
    /// or early exit (Ruling 53, and the second of the two cancellation
    /// routes `vscode.d.ts:20206-20207` names, the first being the
    /// `CancellationToken` `handleSendRequest` honours). Marks only *this*
    /// cursor finished; the other branch is unaffected and keeps draining.
    private func returned(kind: CursorKind, in context: JSContext) -> JSValue? {
        if let settlement = waiter(for: kind) {
            setWaiter(nil, for: kind)
            settlement.resolve.call(withArguments: [iteratorResult(value: nil, done: true, in: context)])
        }
        markFinished(kind)
        checkCompletion()
        let result = iteratorResult(value: nil, done: true, in: context)
        return VSCodeAPI.resolvedPromise(with: result, in: context)
    }

    /// Called after new data arrives or the source finishes: if this
    /// cursor has an outstanding waiter, re-attempts to settle it now.
    private func wake(_ kind: CursorKind) {
        guard let settlement = waiter(for: kind) else { return }
        guard let context = settlement.resolve.context else {
            // The promise's own `JSContext` is already gone — there is
            // nowhere left to settle *or*
            // reject this promise, so the only decision available is not
            // to strand the waiter silently: clear it, so a future
            // `wake(_:)` for this cursor does not hit this same guard again
            // for the same reason.
            setWaiter(nil, for: kind)
            return
        }
        setWaiter(nil, for: kind)
        attemptSettleOrStore(kind: kind, settlement: settlement, in: context)
    }

    private func attemptSettleOrStore(
        kind: CursorKind,
        settlement: PromiseSettlementBox,
        in context: JSContext
    ) {
        guard let owner, !owner.isDisposed else {
            rejectLanguageModelTornDown(settlement.reject, memberPath: kind.memberPath)
            checkCompletion()
            return
        }
        switch scan(kind: kind, in: context) {
        case .value(let value):
            settlement.resolve.call(
                withArguments: [iteratorResult(value: value, done: false, in: context)])
        case .done:
            settlement.resolve.call(
                withArguments: [iteratorResult(value: nil, done: true, in: context)])
            checkCompletion()
        case .failed(let error):
            rejectLanguageModelError(
                settlement.reject,
                message: "vscode.LanguageModelChat.sendRequest failed: \(error)")
            checkCompletion()
        case .pending:
            // `for await…of` never issues a second `next()` before the
            // first settles (gate zero, T1) — but the async-iterator
            // protocol does not forbid an extension writing
            // `const a = it.next(); const b = it.next();` by hand, and
            // `setWaiter` overwrites unconditionally. Left alone, that
            // silently strands the first promise forever with no
            // diagnostic: reject the
            // displaced waiter, naming the one-outstanding-`next()`
            // constraint, before installing the new one.
            if let existing = waiter(for: kind) {
                MainThreadLanguageModels.logger.error(
                    """
                    A second next() call arrived on \
                    \(kind.memberPath, privacy: .public) while one was \
                    already outstanding; rejecting the earlier call's \
                    promise rather than leaving it to hang forever
                    """)
                rejectLanguageModelError(
                    existing.reject,
                    message: "\(kind.memberPath) only supports one " +
                        "outstanding `next()` call at a time; a second " +
                        "`next()` was issued before the first settled.")
            }
            setWaiter(settlement, for: kind)
        }
    }

    /// Scans `buffer` from this cursor's current index, per Ruling 53's
    /// per-kind rules: `.stream` yields every non-`.end` part; `.text`
    /// yields only `.text` values, skipping (advancing past) everything
    /// else — "filters, does not stringify"
    /// (`extHostLanguageModels.ts:63-69`). Answers `.pending` only once the
    /// buffer is exhausted for this cursor *and* the source has not
    /// finished and has not failed.
    private func scan(kind: CursorKind, in context: JSContext) -> ScanOutcome {
        withCursor(kind) { cursor in
            if cursor.isFinished { return .done }
            while cursor.index < self.buffer.count {
                let part = self.buffer[cursor.index]
                cursor.index += 1
                if case .end = part {
                    cursor.isFinished = true
                    return .done
                }
                switch kind {
                case .stream:
                    guard let value = languageModelResponsePartJSValue(
                        for: part,
                        textPartConstructor: self.textPartConstructor,
                        toolCallPartConstructor: self.toolCallPartConstructor,
                        in: context)
                    else {
                        // A part that fails to bridge used to be silently
                        // `continue`d past, so a data-loss event masqueraded
                        // as a successful, merely-shorter response. Fail
                        // the cursor via the
                        // same route `sourceFailure` uses instead, so the
                        // extension actually sees an error rather than an
                        // empty-but-successful stream.
                        let kindName = LanguageModelResponseRequest.partKindName(part)
                        MainThreadLanguageModels.logger.error(
                            """
                            languageModelResponsePartJSValue(for:textPartConstructor:\
                            toolCallPartConstructor:in:) answered nothing bridging a \
                            '\(kindName, privacy: .public)' response part; \
                            failing vscode.LanguageModelChatResponse.stream \
                            rather than silently dropping it
                            """)
                        cursor.isFinished = true
                        return .failed(LanguageModelPartBridgingFailure(partKind: kindName))
                    }
                    return .value(value)
                case .text:
                    guard case .text(let text) = part else { continue }
                    return .value(JSValue(object: text, in: context) ?? JSValue(nullIn: context))
                }
            }
            if let sourceFailure = self.sourceFailure {
                cursor.isFinished = true
                return .failed(sourceFailure)
            }
            if self.isSourceFinished {
                cursor.isFinished = true
                return .done
            }
            return .pending
        }
    }

    /// The name `.stream`'s bridging-failure log/error uses for `part`'s
    /// kind. `.end` never reaches a caller of
    /// this — the `.stream`/`.text` switch above intercepts it first — so
    /// its branch here exists only so the function is total, not because it
    /// is ever reported.
    private static func partKindName(_ part: ExtensionLanguageModelResponsePart) -> String {
        switch part {
        case .text: return "text"
        case .toolCall: return "toolCall"
        case .end: return "end"
        }
    }

    private func iteratorResult(value: JSValue?, done: Bool, in context: JSContext) -> JSValue {
        let result = JSValue(newObjectIn: context) ?? JSValue(nullIn: context)
        result?.setObject(done, forKeyedSubscript: "done" as NSString)
        result?.setObject(
            value ?? JSValue(undefinedIn: context), forKeyedSubscript: "value" as NSString)
        return result ?? JSValue(nullIn: context)
    }

    /// Ruling 53's ruled-in divergence: once *both* cursors have finished —
    /// drained to `done`, rejected, or closed via `return()` — the pump is
    /// cancelled and this request drops out of the adaptor's `liveRequests`,
    /// rather than continuing to consume the seam's stream for no listener.
    ///
    /// This is the only production-code path that removes a request that
    /// was ever handed to JS from `liveRequests` — the other removal,
    /// `handleSendRequest`'s `makeResponseObject(in:)` failure path, undoes
    /// a registration whose response object an extension never received.
    /// An extension that iterates just one of `.stream`/`.text` to
    /// completion — or neither at all (Ruling 53 explicitly accepts
    /// unbounded `buffer` growth for an un-iterated branch, matching
    /// upstream) — leaves the other cursor's `isFinished` false forever, so
    /// this guard never fires, and the request (`buffer` included) is
    /// retained for the adaptor's entire remaining lifetime, until
    /// `dispose()`. That is a known, accepted cost (Ruling 82): re-owning a
    /// response's lifetime from the JS side instead — so it could be
    /// released the moment the extension drops it, the way upstream's own
    /// teed iterable is garbage-collected — would overturn Ledger Ruling 2's
    /// weak-capture rule, which is why that route is deferred rather than
    /// taken here.
    private func checkCompletion() {
        guard streamCursor.isFinished, textCursor.isFinished else { return }
        cancelSource()
        owner?.liveRequests.removeValue(forKey: id)
    }

    // MARK: - Per-kind cursor access

    private func withCursor<T>(_ kind: CursorKind, _ body: (inout CursorState) -> T) -> T {
        switch kind {
        case .stream: return body(&streamCursor)
        case .text: return body(&textCursor)
        }
    }

    private func waiter(for kind: CursorKind) -> PromiseSettlementBox? {
        withCursor(kind) { $0.waiter }
    }

    private func setWaiter(_ waiter: PromiseSettlementBox?, for kind: CursorKind) {
        withCursor(kind) { $0.waiter = waiter }
    }

    private func markFinished(_ kind: CursorKind) {
        withCursor(kind) { $0.isFinished = true }
    }
}

// MARK: - The parsed LanguageModelChatSelector

/// A parsed `vscode.LanguageModelChatSelector` (`vscode.d.ts:20319-20344`),
/// the plain object literal an extension passes *in* to `selectChatModels`.
/// All four fields are optional (`:20325`,`:20331`,`:20337`,`:20343`), and
/// the whole selector is optional too (`:20769`) — an absent argument and an
/// object with every field `undefined` both produce a criteria value with
/// every field `nil`, and `matches(_:)` treats a `nil` field as imposing no
/// constraint, so both mean "match everything."
private struct LanguageModelChatSelectorCriteria {
    var vendor: String?
    var family: String?
    var version: String?
    var id: String?

    /// `selector` is `currentArguments().first` — `nil` when the extension
    /// called `selectChatModels()` with no argument at all. A non-`nil`
    /// argument that is not a JS object (a number, a string) is treated the
    /// same as "no constraints" rather than crashing on `forProperty`, which
    /// upstream's own type (`selector?: LanguageModelChatSelector`) does not
    /// contemplate an extension violating in a way this host needs to
    /// diagnose.
    static func make(from selector: JSValue?) -> LanguageModelChatSelectorCriteria {
        guard let selector, selector.isObject else {
            return LanguageModelChatSelectorCriteria(vendor: nil, family: nil, version: nil, id: nil)
        }
        return LanguageModelChatSelectorCriteria(
            vendor: stringOptionalField(selector.forProperty("vendor")),
            family: stringOptionalField(selector.forProperty("family")),
            version: stringOptionalField(selector.forProperty("version")),
            id: stringOptionalField(selector.forProperty("id")))
    }

    /// A conjunction, not a disjunction: every field this criteria value
    /// actually sets must equal `model`'s corresponding property, so a
    /// selector with two fields set where only one matches excludes the
    /// model — the mutation an all-fields-match fixture cannot see.
    func matches(_ model: LanguageModelChatDescriptor) -> Bool {
        if let vendor, vendor != model.vendor { return false }
        if let family, family != model.family { return false }
        if let version, version != model.version { return false }
        if let id, id != model.id { return false }
        return true
    }

    /// `nil` unless `value` is a JS string — an `undefined` property (a field
    /// the extension left unset) and a non-string value are both read as "no
    /// constraint on this field," never as an empty-string constraint.
    private static func stringOptionalField(_ value: JSValue?) -> String? {
        guard let value, value.isString, let string = value.toString() else { return nil }
        return string
    }
}

// MARK: - Logging

extension MainThreadLanguageModels: Loggable {
    public static nonisolated let logger = makeLogger()
}
