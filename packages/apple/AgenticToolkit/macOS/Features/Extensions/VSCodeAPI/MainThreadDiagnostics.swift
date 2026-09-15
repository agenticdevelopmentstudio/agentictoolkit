//
//  MainThreadDiagnostics.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore
import OSLog
import AgenticToolkitCore

// MARK: - The seam (Ledger Ruling 5 — extension diagnostics get their own store)

/// Notified whenever an extension-visible diagnostic collection changes the
/// diagnostics for one or more `Uri`s — `set` (either overload), `delete`,
/// `clear`, and a collection's own `dispose()` each call this with the
/// `URL`s they actually touched. Never called for a read (`get`, `has`,
/// `forEach`, iteration).
///
/// No default value anywhere `MainThreadDiagnostics` is constructed with
/// one — a caller that forgot to pass the host's real sink would silently
/// get nothing, defeating the point of injecting it, matching
/// `MainThreadLanguages`'s own `store`/`vocabulary` parameters.
@MainActor
public protocol ExtensionDiagnosticSink: AnyObject {
    func diagnosticsChanged(for uris: [URL])
}

// MARK: - The store

/// **Not `DiagnosticStore`.** `Language/LSP/DiagnosticStore.swift` already
/// owns that name for a genuinely different component — LSP `Diagnostic`
/// values keyed by `DocumentUri`, fed by an `AsyncStream`, the *receiving*
/// end of a language server's own push. This type is the extension-facing
/// *authoring* side: what an extension's own `vscode.languages` calls
/// declare, keyed by a `DiagnosticCollection`'s uniquified `owner`. The
/// `Extension` prefix matches `ExtensionLanguageVocabulary`
/// (`MainThreadLanguages.swift:459`, commit 6c55bdb0) and
/// `ExtensionLanguageModelProviding` (`MainThreadLanguageModels.swift:79`,
/// commit 6c55bdb0) for the same reason: it names this
/// as the extension-authoring half of a pair, not a rename of the LSP type.
///
/// Holds only plain Swift values (`URL`, `VSCodeAPI.ExtensionDiagnostic`) —
/// no `JSValue`, no `JSContext` — so nothing here is subject to the
/// no-`JSValue`-capture rule, matching `LanguageConfigurationStore`'s own
/// reasoning.
///
/// `@MainActor`: every call into this store happens on the thread that made
/// the extension call, which for this host is always the main actor.
@MainActor
public final class ExtensionDiagnosticStore {

    /// One collection's own state: its declared `name` (which, per
    /// `extHostDiagnostics.ts:280-291`, can differ from the `owner` key this
    /// state is stored under when `name` collided at creation), and its
    /// diagnostics keyed by `Uri`, in insertion order — `order` is the
    /// source of truth `forEach` and `Symbol.iterator` both read from, so
    /// the two agree by construction (brief's Symbol.iterator/forEach
    /// ordering requirement, ledger Ruling 25).
    private struct CollectionState {
        var name: String
        var order: [URL] = []
        var diagnostics: [URL: [VSCodeAPI.ExtensionDiagnostic]] = [:]

        mutating func ensurePresent(_ uri: URL) {
            if diagnostics[uri] == nil {
                order.append(uri)
                diagnostics[uri] = []
            }
        }

        mutating func replace(_ uri: URL, with newDiagnostics: [VSCodeAPI.ExtensionDiagnostic]) {
            ensurePresent(uri)
            diagnostics[uri] = newDiagnostics
        }

        mutating func append(_ uri: URL, adding newDiagnostics: [VSCodeAPI.ExtensionDiagnostic]) {
            ensurePresent(uri)
            diagnostics[uri, default: []].append(contentsOf: newDiagnostics)
        }

        mutating func remove(_ uri: URL) {
            if diagnostics.removeValue(forKey: uri) != nil {
                order.removeAll { $0 == uri }
            }
        }

        /// Ports `extHostDiagnostics.ts`'s array-taking `set` overload
        /// (`vscode.d.ts:7199`'s doc: repeated same-Uri tuples merge, not
        /// last-wins) faithfully, including a real upstream quirk: tuples
        /// are stable-sorted by `uri.toString()`
        /// (`_compareIndexedTuplesByUri`), and on a transition to a new Uri
        /// the *previous* Uri is deleted from storage if it ended up empty
        /// — a cleanup that never runs for the final Uri in the sorted
        /// batch, because there is no following transition to trigger it.
        /// That asymmetry is upstream's own behavior, not a bug introduced
        /// here, and is kept rather than "fixed."
        mutating func applyEntries(
            _ entries: [(url: URL, diagnostics: [VSCodeAPI.ExtensionDiagnostic]?)]
        ) -> [URL] {
            let sorted = entries.enumerated().sorted { lhs, rhs in
                let left = lhs.element.url.absoluteString
                let right = rhs.element.url.absoluteString
                if left != right { return left < right }
                return lhs.offset < rhs.offset
            }.map { $0.element }

            var toSync: [URL] = []
            var lastUri: URL?
            for (uri, newDiagnostics) in sorted {
                if lastUri == nil || lastUri! != uri {
                    if let lastUri, diagnostics[lastUri]?.isEmpty == true {
                        remove(lastUri)
                    }
                    lastUri = uri
                    toSync.append(uri)
                    replace(uri, with: [])
                }
                if let newDiagnostics {
                    append(uri, adding: newDiagnostics)
                } else {
                    replace(uri, with: [])
                }
            }
            return toSync
        }
    }

    private var collections: [String: CollectionState] = [:]
    private var ownerOrder: [String] = []

    /// Shared by both the "no name given" and "name collided" branches of
    /// `createCollection(name:)`, exactly as `extHostDiagnostics.ts`'s
    /// single `_idPool` is shared across both — see that function's own
    /// doc for why a single counter (not one per branch) is load-bearing.
    private var idPool = 0

    public init() {}

    // MARK: - Collection lifecycle

    /// Registers a new collection and returns the key to store it under
    /// (`owner`) and the name it reports through `.name` (`resolvedName`).
    ///
    /// Ports `extHostDiagnostics.ts:280-291` exactly: a colliding `name`
    /// keeps `.name` (`resolvedName == name`) while uniquifying only
    /// `owner`, so two `createDiagnosticCollection("eslint")` calls both
    /// answer `.name === "eslint"` yet are distinct collections.
    public func createCollection(name: String?) -> (owner: String, name: String) {
        let owner: String
        let resolvedName: String
        if let name, !name.isEmpty {
            if collections[name] == nil {
                owner = name
                resolvedName = name
            } else {
                resolvedName = name
                var candidate: String
                repeat {
                    candidate = name + String(idPool)
                    idPool += 1
                } while collections[candidate] != nil
                owner = candidate
            }
        } else {
            let generated = "_generated_diagnostic_collection_name_#\(idPool)"
            idPool += 1
            owner = generated
            resolvedName = generated
        }
        collections[owner] = CollectionState(name: resolvedName)
        ownerOrder.append(owner)
        return (owner, resolvedName)
    }

    /// Removes `owner` entirely, freeing the name it held (mutation 9) and
    /// returning every `Uri` it carried, for the sink.
    @discardableResult
    public func removeCollection(owner: String) -> [URL] {
        guard let state = collections.removeValue(forKey: owner) else { return [] }
        ownerOrder.removeAll { $0 == owner }
        return state.order
    }

    public func containsOwner(_ owner: String) -> Bool {
        collections[owner] != nil
    }

    public func name(ownedBy owner: String) -> String? {
        collections[owner]?.name
    }

    // MARK: - Per-collection mutations

    /// The single-Uri `set` overload. `diagnostics == nil` is a removal
    /// (`extHostDiagnostics.ts:77-81`), not a stored empty array — a no-op
    /// on an already-gone `owner`.
    @discardableResult
    public func set(owner: String, uri: URL, diagnostics: [VSCodeAPI.ExtensionDiagnostic]?) -> [URL] {
        guard collections[owner] != nil else { return [] }
        if let diagnostics {
            collections[owner]!.replace(uri, with: diagnostics)
        } else {
            collections[owner]!.remove(uri)
        }
        return [uri]
    }

    /// The array-taking `set` overload — see `CollectionState.applyEntries`.
    @discardableResult
    public func setEntries(
        owner: String, entries: [(url: URL, diagnostics: [VSCodeAPI.ExtensionDiagnostic]?)]
    ) -> [URL] {
        guard collections[owner] != nil else { return [] }
        return collections[owner]!.applyEntries(entries)
    }

    @discardableResult
    public func delete(owner: String, uri: URL) -> [URL] {
        guard collections[owner] != nil else { return [] }
        collections[owner]!.remove(uri)
        return [uri]
    }

    @discardableResult
    public func clear(owner: String) -> [URL] {
        guard let state = collections[owner] else { return [] }
        let affected = state.order
        collections[owner]!.order = []
        collections[owner]!.diagnostics = [:]
        return affected
    }

    /// `nil` for an absent `Uri` — `vscode.d.ts:7230`'s declared
    /// `readonly Diagnostic[] | undefined`, which is what the exposed
    /// `DiagnosticCollection.get` must honor (mutation 4), distinct from
    /// `extHostDiagnostics.ts`'s own raw `#data`-backed `get`, which returns
    /// `[]` for the same case — that raw accessor is upstream's internal
    /// storage layer, not the interface contract this store's own exposed
    /// behavior must match.
    public func get(owner: String, uri: URL) -> [VSCodeAPI.ExtensionDiagnostic]? {
        collections[owner]?.diagnostics[uri]
    }

    public func has(owner: String, uri: URL) -> Bool {
        collections[owner]?.diagnostics[uri] != nil
    }

    /// Every `(Uri, diagnostics)` pair currently in `owner`, in the order
    /// `forEach` and `Symbol.iterator` must agree on.
    public func pairs(owner: String) -> [(url: URL, diagnostics: [VSCodeAPI.ExtensionDiagnostic])] {
        guard let state = collections[owner] else { return [] }
        return state.order.compactMap { uri in
            guard let diagnostics = state.diagnostics[uri] else { return nil }
            return (uri, diagnostics)
        }
    }

    // MARK: - Cross-collection reads, for `vscode.languages.getDiagnostics`

    /// `getDiagnostics(resource)` (`vscode.d.ts:14807`): every collection's
    /// diagnostics for `uri`, concatenated in collection-creation order —
    /// `extHostDiagnostics.ts:337-344`'s `_getDiagnostics`.
    public func diagnostics(for uri: URL) -> [VSCodeAPI.ExtensionDiagnostic] {
        var result: [VSCodeAPI.ExtensionDiagnostic] = []
        for owner in ownerOrder {
            guard let forUri = collections[owner]?.diagnostics[uri] else { continue }
            result.append(contentsOf: forUri)
        }
        return result
    }

    /// `getDiagnostics()` (`vscode.d.ts:14814`): every `Uri` across every
    /// collection, first-seen order, each paired with its diagnostics
    /// merged across every collection that has any —
    /// `extHostDiagnostics.ts:320-333`'s no-argument branch.
    public func allDiagnostics() -> [(url: URL, diagnostics: [VSCodeAPI.ExtensionDiagnostic])] {
        var index: [URL: Int] = [:]
        var result: [(url: URL, diagnostics: [VSCodeAPI.ExtensionDiagnostic])] = []
        for owner in ownerOrder {
            guard let state = collections[owner] else { continue }
            for uri in state.order {
                guard let diagnostics = state.diagnostics[uri] else { continue }
                if let existingIndex = index[uri] {
                    result[existingIndex].diagnostics.append(contentsOf: diagnostics)
                } else {
                    index[uri] = result.count
                    result.append((uri, diagnostics))
                }
            }
        }
        return result
    }
}

// MARK: - The adaptor

/// The `vscode.languages` diagnostics slice: `createDiagnosticCollection`
/// and `getDiagnostics` (task 5.6a-iii, ledger Ruling 23's third slice), plus
/// `onDidChangeDiagnostics` (task 5.6b).
///
/// **The event's two halves are deliberately on opposite sides of the sink.**
/// This adaptor only *reads* `events` — it publishes the callable
/// `Event<DiagnosticChangeEvent>` and nothing else. The *writes* happen in
/// `HostDiagnosticSink.diagnosticsChanged(for:)`, which is what every
/// mutation below already reports to. Routing the event through the sink
/// rather than firing it from these eight call sites reuses the seam 5.6a-iii
/// built instead of laying a second notification path beside it, and it means
/// a future host-side source of diagnostics — the analogue of upstream's
/// `$acceptMarkersChange` (`extHostDiagnostics.ts:349-370`), whose mirror
/// collection is handed `this._onDidChangeDiagnostics` at
/// `extHostDiagnostics.ts:357` so that markers which did not come from an
/// extension fire the very same emitter — reaches extensions for free by
/// calling the sink.
///
/// **Divergence from upstream:** `extHostDiagnostics.ts`'s
/// `_checkDisposed()` makes every method of a disposed collection *throw*.
/// This adaptor instead makes them inert no-ops (`get` answers `undefined`,
/// `has` answers `false`, `set`/`delete`/`clear` do nothing and notify no
/// one) — the brief's own three prose-only behaviors to port are the
/// undefined-removal, the array-overload merge, and `get`'s
/// absent-is-`undefined` contract; a disposed-collection throw is not among
/// them, and `MainThreadWindow.showStatusBarItem`'s own "a disposed item
/// ignores this call" is the precedent for choosing quiet inertness over
/// inventing a new throw this task was not asked for. Inertness holds even
/// after the disposed collection's own name has been reused by a later
/// `createDiagnosticCollection` call: the `disposed` flag each method below
/// consults first is checked before the closure's captured `owner` ever
/// reaches the store again, so a stale `set`/`delete`/`clear`/`get` cannot
/// reach the collection now registered under the same key.
///
/// A second divergence: an empty `clear()` and an empty `dispose()` notify
/// the sink of nothing (the `if !affected.isEmpty` guards below), where
/// upstream fires both unconditionally (`extHostDiagnostics.ts:182`,
/// `extHostDiagnostics.ts:48`). Kept rather than matched: 5.6b's emitter is
/// keyed by `Uri`, so an empty affected set contributes nothing to it
/// either way, and the cost if this is wrong is a hypothetical consumer
/// that counts `clear()`/`dispose()` *calls* rather than changed Uris
/// under-counting — nothing in Stage 5 does that.
@MainActor
public final class MainThreadDiagnostics {

    /// Where every collection this adaptor creates actually lives. Not
    /// defaulted, matching `MainThreadLanguages.store`'s own reasoning.
    private let store: ExtensionDiagnosticStore

    /// Notified of every mutation, on every collection this adaptor
    /// creates. Not defaulted, for the same reason `store` is not.
    private let sink: ExtensionDiagnosticSink

    /// The owners this adaptor itself created — the ownership record
    /// `dispose()` walks, so a shared `store` is torn down only for this
    /// adaptor's own collections, matching `MainThreadLanguages.ownedHandles`.
    private var ownedOwners: Set<String> = []

    /// The emitter behind `vscode.languages.onDidChangeDiagnostics`, read
    /// from here and written from the sink (see this type's own doc). Not
    /// defaulted, for the same reason `store` and `sink` are not — and
    /// because it is meant to be *shared*: upstream has one
    /// `_onDidChangeDiagnostics` per extension host
    /// (`extHostDiagnostics.ts:240`), not one per extension, so one
    /// extension's change is visible to another's listener. Handing the same
    /// emitter to every `MainThreadDiagnostics` and to the sink is how that
    /// is spelled here; a privately constructed one would silently give each
    /// extension its own island.
    private let events: ExtensionEventEmitter<[URL]>

    public init(
        store: ExtensionDiagnosticStore,
        sink: ExtensionDiagnosticSink,
        events: ExtensionEventEmitter<[URL]>
    ) {
        self.store = store
        self.sink = sink
        self.events = events
    }

    // MARK: - vscode.languages.onDidChangeDiagnostics

    /// `extHostDiagnostics.ts:240`'s window width, in seconds.
    public static let onDidChangeDiagnosticsDelay: TimeInterval = 0.050

    /// The shared emitter `HostDiagnosticSink` fires and every
    /// `MainThreadDiagnostics` publishes — upstream's
    /// `new DebounceEmitter<readonly vscode.Uri[]>({ merge: all => all.flat(),
    /// delay: 50 })` (`extHostDiagnostics.ts:240`) composed with
    /// `Event.map(…, ExtHostDiagnostics._mapper)`
    /// (`extHostDiagnostics.ts:250`).
    ///
    /// `window` has **no default**: see
    /// `ExtensionEventEmitter.window`'s own doc for why a seam with a default
    /// stops being a seam. Production passes `ExtensionEventTimerWindow()`.
    public static func makeOnDidChangeDiagnosticsEmitter(
        window: ExtensionEventWindowScheduling
    ) -> ExtensionEventEmitter<[URL]> {
        ExtensionEventEmitter(
            path: "vscode.languages.onDidChangeDiagnostics",
            delay: onDidChangeDiagnosticsDelay,
            window: window,
            // `merge: all => all.flat()` — flatten only. Dedup is the
            // mapper's job, and the order of the two is testable: flatten
            // first, dedup second.
            merge: { $0.flatMap { $0 } },
            map: { uris, context in
                MainThreadDiagnostics.diagnosticChangeEventValue(for: uris, in: context)
            })
    }

    /// `vscode.d.ts:14799`'s `Event<DiagnosticChangeEvent>`, published as a
    /// member whose *value* is the callable subscribe function —
    /// `vscode.d.ts:1766` declares `Event<T>` as a call signature, so
    /// `vscode.languages.onDidChangeDiagnostics(fn)` is a call, not a
    /// property read followed by `addListener`.
    ///
    /// Raises rather than rejects on a torn-down adaptor: the member answers
    /// a `Disposable` synchronously, not a `Thenable`, and
    /// `VSCodeAPI.TeardownResponse`'s own doc
    /// (`VSCodeAPI.swift:89-96`, whose rule alone is `:92-96`) makes that the
    /// deciding question. The same choice
    /// `createDiagnosticCollection` above makes.
    public private(set) lazy var onDidChangeDiagnostics: Any = VSCodeAPI.member(
        "vscode.languages.onDidChangeDiagnostics", of: self, whenTornDown: .raisedException
    ) { $0.handleOnDidChangeDiagnostics() }

    private func handleOnDidChangeDiagnostics() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        return events.subscribe(arguments: VSCodeAPI.currentArguments(), in: context, owner: self)
    }

    /// `ExtHostDiagnostics._mapper` (`extHostDiagnostics.ts:242-248`), which
    /// runs only after the window's queue has been flattened.
    ///
    /// Three behaviours, all of them testable and none of them visible in
    /// `vscode.d.ts:7013-7019`'s two-line declaration:
    ///
    /// - **Dedup is by Uri identity, not object identity.** Upstream keys a
    ///   `ResourceMap`, whose default key is `uri.toString()`; two distinct
    ///   `Uri` objects for one path collapse to one entry. `absoluteString`
    ///   is this host's `toString()`.
    /// - **First-insertion order survives.** `map.set` on an existing key
    ///   replaces the value but does not move it, and
    ///   `Array.from(map.values())` walks insertion order — so `a, b, a`
    ///   yields `[a, b]`. (Upstream's *value* for a repeated key is the last
    ///   `set`; here the value under a key is the `URL` that key was derived
    ///   from, so first and last are indistinguishable and the choice is not
    ///   observable.)
    /// - **The array is frozen.** `Object.freeze` at
    ///   `extHostDiagnostics.ts:247` — an extension cannot mutate the `uris`
    ///   it is handed, so it cannot corrupt what a second listener, or the
    ///   next window, sees.
    ///
    /// Refuses the whole event — `nil` — if any `Uri` fails to build, rather
    /// than handing an extension a short `uris` array that silently omits a
    /// file it changed, the same refuse-the-whole-array contract
    /// `diagnosticValues(_:in:)` already enforces.
    static func diagnosticChangeEventValue(for uris: [URL], in context: JSContext) -> JSValue? {
        var seen: Set<String> = []
        var uriValues: [JSValue] = []
        for uri in uris where seen.insert(uri.absoluteString).inserted {
            guard let uriValue = VSCodeAPI.uriValue(for: uri, in: context) else { return nil }
            uriValues.append(uriValue)
        }
        guard let urisValue = arrayValue(of: uriValues, in: context),
              let objectConstructor = context.objectForKeyedSubscript("Object"),
              !objectConstructor.isUndefined,
              let frozen = objectConstructor.invokeMethod("freeze", withArguments: [urisValue]),
              let event = JSValue(newObjectIn: context) else {
            return nil
        }
        event.setObject(frozen, forKeyedSubscript: "uris" as NSString)
        return event
    }

    // MARK: - vscode.languages.createDiagnosticCollection

    public private(set) lazy var createDiagnosticCollection: Any = VSCodeAPI.member(
        "vscode.languages.createDiagnosticCollection", of: self, whenTornDown: .raisedException
    ) { $0.handleCreateDiagnosticCollection() }

    private func handleCreateDiagnosticCollection() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        var name: String?
        if let first = arguments.first, !first.isUndefined, !first.isNull {
            guard first.isString, let decoded = first.toString() else {
                return VSCodeAPI.raise(
                    "createDiagnosticCollection requires a string name, or no argument.", in: context)
            }
            name = decoded
        }
        let created = store.createCollection(name: name)
        ownedOwners.insert(created.owner)
        return MainThreadDiagnostics.makeDiagnosticCollectionObject(owner: created.owner, of: self, in: context)
    }

    // MARK: - vscode.languages.getDiagnostics

    public private(set) lazy var getDiagnostics: Any = VSCodeAPI.member(
        "vscode.languages.getDiagnostics", of: self, whenTornDown: .raisedException
    ) { $0.handleGetDiagnostics() }

    private func handleGetDiagnostics() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        // `null` is falsy under `extHostDiagnostics.ts:317`'s `if (resource)`
        // dispatch, so it must fall through to the no-argument branch below
        // exactly as an omitted argument does — matching
        // `handleCreateDiagnosticCollection`'s own `isUndefined`/`isNull`
        // check above.
        if let first = arguments.first, !first.isUndefined, !first.isNull {
            guard let url = VSCodeAPI.url(from: first, in: context) else {
                return VSCodeAPI.raise("getDiagnostics requires a Uri, or no argument.", in: context)
            }
            // Refuses the whole call rather than silently shortening the
            // returned array — the store may hold more diagnostics for
            // `url` than `VSCodeAPI.diagnosticValue(for:in:)` can decode;
            // propagates the same refuse-the-whole-array contract
            // `DiagnosticTypes.swift:483-486`/`:572-582` already enforces
            // one level down.
            guard let values = MainThreadDiagnostics.diagnosticValues(
                store.diagnostics(for: url), in: context
            ) else {
                return VSCodeAPI.raise("Could not decode a diagnostic for this Uri.", in: context)
            }
            return MainThreadDiagnostics.arrayValue(of: values, in: context)
        }
        // Refuses the whole call rather than silently shortening the returned
        // array, exactly as the resource branch above does — see
        // `pairValues(_:in:)`.
        guard let pairValues = MainThreadDiagnostics.pairValues(
            store.allDiagnostics(), in: context
        ) else {
            return VSCodeAPI.raise("Could not decode a diagnostic entry.", in: context)
        }
        return MainThreadDiagnostics.arrayValue(of: pairValues, in: context)
    }

    // MARK: - The collection object's own methods

    private func handleCollectionSet(owner: String) -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()

        // extHostDiagnostics.ts:64-68 — a falsy first argument clears the
        // whole collection, whichever overload was otherwise intended.
        guard let first = arguments.first, !MainThreadDiagnostics.isFalsy(first) else {
            let affected = store.clear(owner: owner)
            if !affected.isEmpty { sink.diagnosticsChanged(for: affected) }
            return MainThreadDiagnostics.undefinedValue(in: context)
        }

        if first.isArray {
            guard let entries = MainThreadDiagnostics.setEntriesArray(from: first, in: context) else {
                return VSCodeAPI.raise("Invalid entries passed to DiagnosticCollection.set.", in: context)
            }
            let affected = store.setEntries(owner: owner, entries: entries)
            if !affected.isEmpty { sink.diagnosticsChanged(for: affected) }
            return MainThreadDiagnostics.undefinedValue(in: context)
        }

        guard let url = VSCodeAPI.url(from: first, in: context) else {
            return VSCodeAPI.raise(
                "DiagnosticCollection.set requires a Uri, an entries array, or no argument.", in: context)
        }
        let second = arguments.count > 1 ? arguments[1] : nil
        switch MainThreadDiagnostics.decodeDiagnosticsArgument(second, in: context) {
        case .removal:
            let affected = store.set(owner: owner, uri: url, diagnostics: nil)
            if !affected.isEmpty { sink.diagnosticsChanged(for: affected) }
        case .diagnostics(let diagnostics):
            let affected = store.set(owner: owner, uri: url, diagnostics: diagnostics)
            if !affected.isEmpty { sink.diagnosticsChanged(for: affected) }
        case .invalid:
            return VSCodeAPI.raise("Invalid diagnostics array passed to DiagnosticCollection.set.", in: context)
        }
        return MainThreadDiagnostics.undefinedValue(in: context)
    }

    private func handleCollectionDelete(owner: String) -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        guard let first = arguments.first, let url = VSCodeAPI.url(from: first, in: context) else {
            return VSCodeAPI.raise("DiagnosticCollection.delete requires a Uri.", in: context)
        }
        let affected = store.delete(owner: owner, uri: url)
        if !affected.isEmpty { sink.diagnosticsChanged(for: affected) }
        return MainThreadDiagnostics.undefinedValue(in: context)
    }

    private func handleCollectionClear(owner: String) -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let affected = store.clear(owner: owner)
        if !affected.isEmpty { sink.diagnosticsChanged(for: affected) }
        return MainThreadDiagnostics.undefinedValue(in: context)
    }

    private func handleCollectionGet(owner: String) -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        guard let first = arguments.first, let url = VSCodeAPI.url(from: first, in: context) else {
            return VSCodeAPI.raise("DiagnosticCollection.get requires a Uri.", in: context)
        }
        guard let existing = store.get(owner: owner, uri: url) else {
            return MainThreadDiagnostics.undefinedValue(in: context)
        }
        // Raises rather than shortening the array on an undecodable
        // diagnostic, matching `getDiagnostics(resource)`'s own choice —
        // this site can raise, so it does.
        guard let values = MainThreadDiagnostics.diagnosticValues(existing, in: context) else {
            return VSCodeAPI.raise("Could not decode a diagnostic for this Uri.", in: context)
        }
        return MainThreadDiagnostics.arrayValue(of: values, in: context)
    }

    private func handleCollectionHas(owner: String) -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        guard let first = arguments.first, let url = VSCodeAPI.url(from: first, in: context) else {
            return VSCodeAPI.raise("DiagnosticCollection.has requires a Uri.", in: context)
        }
        return JSValue(bool: store.has(owner: owner, uri: url), in: context)
    }

    /// `extHostDiagnostics.ts:187-190`: a plain loop that lets a thrown
    /// callback exception propagate straight out, stopping iteration —
    /// mirrored here via `VSCodeAPI.call`'s `.threw` case setting
    /// `context.exception` directly and returning, rather than swallowing
    /// or continuing.
    private func handleCollectionForEach(owner: String) -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        // The collection the callback receives as its third argument
        // (`vscode.d.ts:7221`) is the receiver of this very call, read at
        // callback time from the same family of accessors `currentArguments()`
        // belongs to — never captured. `VSCodeAPI.settlement(of:in:)`'s doc
        // sets out why a block exported to JavaScript may not hold a `JSValue`
        // (`JSManagedValue.h:49`), and holding one *weakly* to sidestep that
        // is worse than the cycle it avoids: `JSValue(newObjectIn:)` is
        // autoreleased, so the Swift wrapper is gone by the next drain and
        // every later `forEach` then iterates nothing at all, silently.
        guard let collection = JSContext.currentThis() else { return nil }
        let arguments = VSCodeAPI.currentArguments()
        // `callback instanceof Function` — `isObject` is true of `{}` too, and
        // "requires a callback function" has to mean callable or it means
        // nothing. `MainThreadCommands.swift:130-141` is the precedent, and
        // its `:134-137` is why the one-realm reading is safe here.
        let functionConstructor = context.objectForKeyedSubscript("Function")
        guard let callback = arguments.first,
              let functionConstructor,
              callback.isInstance(of: functionConstructor) else {
            return VSCodeAPI.raise(
                "DiagnosticCollection.forEach requires a callback function.",
                in: context)
        }
        let thisArg = arguments.count > 1 ? arguments[1] : nil
        for entry in store.pairs(owner: owner) {
            guard let uriValue = VSCodeAPI.uriValue(for: entry.url, in: context) else { continue }
            // `forEach`'s existing failure unit is the whole entry (the
            // `uriValue` guard above already skips one on a bad Uri) — an
            // undecodable diagnostic must fail the same entry, never
            // silently shorten its diagnostics array.
            guard let diagnosticsValues = MainThreadDiagnostics.diagnosticValues(entry.diagnostics, in: context),
                  let diagnosticsArrayValue = MainThreadDiagnostics.arrayValue(of: diagnosticsValues, in: context)
            else { continue }
            let callArguments = [uriValue, diagnosticsArrayValue, collection]
            switch VSCodeAPI.call(callback, thisArg: thisArg, arguments: callArguments) {
            case .returned:
                continue
            case .threw(let exception):
                context.exception = exception
                return nil
            case .unavailable:
                return VSCodeAPI.raise("DiagnosticCollection.forEach could not invoke its callback.", in: context)
            }
        }
        return MainThreadDiagnostics.undefinedValue(in: context)
    }

    private func handleCollectionDispose(owner: String) {
        let affected = store.removeCollection(owner: owner)
        ownedOwners.remove(owner)
        if !affected.isEmpty { sink.diagnosticsChanged(for: affected) }
    }

    /// The array of `[uri, diagnostics]` pairs `Symbol.iterator` delegates
    /// to — see `installSymbolIterator(on:getPairs:in:)`. Built from the
    /// same `store.pairs(owner:)` order `forEach` reads, so the two agree
    /// (mutation 8).
    ///
    /// Raises rather than shortening the array when an entry will not decode,
    /// the same refusal `getDiagnostics()`'s two branches make — see
    /// `pairValues(_:in:)`. That is what makes `for…of` fail the way `forEach`
    /// does on the same collection, instead of iterating a quietly shorter
    /// sequence.
    private func pairsArrayValue(owner: String) -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        guard let pairValues = MainThreadDiagnostics.pairValues(
            store.pairs(owner: owner), in: context
        ) else {
            return VSCodeAPI.raise("Could not decode a diagnostic entry.", in: context)
        }
        return MainThreadDiagnostics.arrayValue(of: pairValues, in: context)
    }

    // MARK: - The collection object factory

    /// Builds the JS-visible `DiagnosticCollection` object for `owner`:
    /// a readonly `name` getter (via `MainThreadWindow.installReadonlyGetter`,
    /// promoted from `private` to `internal` for exactly this reuse — see
    /// that function's own doc for why promoting rather than duplicating its
    /// body), `set`/`delete`/`clear`/`get`/`has`/`forEach`/`dispose` method
    /// blocks via `setObject(_:forKeyedSubscript:)`, and a `Symbol.iterator`
    /// installed through a small evaluated JS snippet — this file's own
    /// `symbolIteratorInstallerSource`, on the `URLSearchParams.prototype
    /// [Symbol.iterator] = ...entries` idiom already used in
    /// `extension-runtime.js:1045-1056` (commit 6c55bdb0), itself delegating
    /// to a real JS array's own `[Symbol.iterator]()` rather than
    /// hand-writing a generator.
    ///
    /// **No-capture evidence:** every block below captures `diagnostics`
    /// (this adaptor) weakly and nothing else, on `MainThreadWindow
    /// .makeStatusBarItemObject`'s own pattern. None of them captures
    /// `object`, not even weakly. `forEach` needs the collection itself —
    /// `vscode.d.ts:7221`'s declared `(uri, diagnostics, collection) => any`
    /// third argument — and reads it from `JSContext.currentThis()` when it
    /// runs instead. A weak capture looks like the safe way to hand an
    /// object its own `JSValue`, and it is not: `JSValue(newObjectIn:)`
    /// returns an autoreleased wrapper, and the strong references that keep
    /// the *JavaScript* object alive (this context, and `object` holding
    /// these blocks) hold nothing at all in Swift. The wrapper dies at the
    /// next drain while the JS object lives on, and `forEach` then iterates
    /// nothing, silently, forever after.
    private static func makeDiagnosticCollectionObject(
        owner: String,
        of diagnostics: MainThreadDiagnostics,
        in context: JSContext
    ) -> JSValue? {
        guard let object = JSValue(newObjectIn: context) else { return nil }

        // Hoisted above every method block below, and consulted first by
        // each of them: once `dispose()` frees `owner`, a *different*
        // collection can be registered under that same key, and every block
        // here still closes over the same
        // `owner` string. Without this check, a disposed object's stale
        // `set`/`delete`/`clear`/`get` would reach the new collection
        // rather than staying inert — see the divergence paragraph above
        // this type. `capturedName` is frozen here rather than re-read
        // from the store post-dispose for the same reason: a collection's
        // `.name` never changes across its own lifetime (only a collision
        // at *creation* affects it), so freezing it is both correct before
        // disposal and immune to a later collection's name after it.
        var disposed = false
        let capturedName = diagnostics.store.name(ownedBy: owner)

        MainThreadWindow.installReadonlyGetter(on: object, name: "name") { [weak diagnostics] in
            disposed ? capturedName : diagnostics?.store.name(ownedBy: owner)
        }

        let setMethod: @convention(block) () -> JSValue? = { [weak diagnostics] in
            MainActor.assumeIsolated {
                guard let diagnostics else {
                    return UncheckedJSValueBox(value: nil)
                }
                guard !disposed else {
                    return UncheckedJSValueBox(
                        value: MainThreadDiagnostics.disposedUndefinedValue())
                }
                return UncheckedJSValueBox(
                    value: diagnostics.handleCollectionSet(owner: owner))
            }.value
        }
        object.setObject(setMethod, forKeyedSubscript: "set" as NSString)

        let deleteMethod: @convention(block) () -> JSValue? = { [weak diagnostics] in
            MainActor.assumeIsolated {
                guard let diagnostics else {
                    return UncheckedJSValueBox(value: nil)
                }
                guard !disposed else {
                    return UncheckedJSValueBox(
                        value: MainThreadDiagnostics.disposedUndefinedValue())
                }
                return UncheckedJSValueBox(
                    value: diagnostics.handleCollectionDelete(owner: owner))
            }.value
        }
        object.setObject(deleteMethod, forKeyedSubscript: "delete" as NSString)

        let clearMethod: @convention(block) () -> JSValue? = { [weak diagnostics] in
            MainActor.assumeIsolated {
                guard let diagnostics else {
                    return UncheckedJSValueBox(value: nil)
                }
                guard !disposed else {
                    return UncheckedJSValueBox(
                        value: MainThreadDiagnostics.disposedUndefinedValue())
                }
                return UncheckedJSValueBox(
                    value: diagnostics.handleCollectionClear(owner: owner))
            }.value
        }
        object.setObject(clearMethod, forKeyedSubscript: "clear" as NSString)

        let getMethod: @convention(block) () -> JSValue? = { [weak diagnostics] in
            MainActor.assumeIsolated {
                guard let diagnostics else {
                    return UncheckedJSValueBox(value: nil)
                }
                guard !disposed else {
                    return UncheckedJSValueBox(
                        value: MainThreadDiagnostics.disposedUndefinedValue())
                }
                return UncheckedJSValueBox(
                    value: diagnostics.handleCollectionGet(owner: owner))
            }.value
        }
        object.setObject(getMethod, forKeyedSubscript: "get" as NSString)

        let hasMethod: @convention(block) () -> JSValue? = { [weak diagnostics] in
            MainActor.assumeIsolated {
                guard let diagnostics else {
                    return UncheckedJSValueBox(value: nil)
                }
                guard !disposed else {
                    return UncheckedJSValueBox(
                        value: MainThreadDiagnostics.disposedFalseValue())
                }
                return UncheckedJSValueBox(
                    value: diagnostics.handleCollectionHas(owner: owner))
            }.value
        }
        object.setObject(hasMethod, forKeyedSubscript: "has" as NSString)

        let forEachMethod: @convention(block) () -> JSValue? = { [weak diagnostics] in
            MainActor.assumeIsolated {
                guard let diagnostics else {
                    return UncheckedJSValueBox(value: nil)
                }
                guard !disposed else {
                    return UncheckedJSValueBox(
                        value: MainThreadDiagnostics.disposedUndefinedValue())
                }
                return UncheckedJSValueBox(
                    value: diagnostics.handleCollectionForEach(owner: owner))
            }.value
        }
        object.setObject(forEachMethod, forKeyedSubscript: "forEach" as NSString)

        let disposeMethod: @convention(block) () -> Void = { [weak diagnostics] in
            MainActor.assumeIsolated {
                guard !disposed else { return }
                disposed = true
                diagnostics?.handleCollectionDispose(owner: owner)
            }
        }
        object.setObject(disposeMethod, forKeyedSubscript: "dispose" as NSString)

        let getPairs: @convention(block) () -> JSValue? = { [weak diagnostics] in
            MainActor.assumeIsolated {
                guard let diagnostics, !disposed else {
                    return UncheckedJSValueBox(value: nil)
                }
                return UncheckedJSValueBox(
                    value: diagnostics.pairsArrayValue(owner: owner))
            }.value
        }
        installSymbolIterator(on: object, getPairs: getPairs, in: context)

        return object
    }

    // MARK: - Teardown

    /// Removes every collection this adaptor created from `store`, and
    /// clears `ownedOwners`. Does not touch any other adaptor's collections
    /// — `store` may be shared, matching `MainThreadLanguages.dispose()`'s
    /// own boundary (mutation 16).
    ///
    /// Also drops this adaptor's `onDidChangeDiagnostics` listeners, and only
    /// this adaptor's: `events` is shared across adaptors on purpose, and a
    /// registration holds its listener's `JSValue`, which holds that
    /// extension's `JSContext`. Leaving them behind would keep a torn-down
    /// extension's context alive inside an emitter that outlives it.
    public func dispose() {
        for owner in ownedOwners {
            let affected = store.removeCollection(owner: owner)
            if !affected.isEmpty { sink.diagnosticsChanged(for: affected) }
        }
        ownedOwners.removeAll()
        events.removeListeners(ownedBy: self)
    }

    // MARK: - Small bridging helpers, local to this file

    /// JS truthiness for the raw first argument to `set` —
    /// `extHostDiagnostics.ts:64`'s `if (!first)`. Only the falsy JS
    /// primitives are `true` here; every object (a `Uri`, an array) is
    /// truthy regardless of contents, including an empty array.
    ///
    /// Not `private`: `ExtensionEvent.swift` needs the same JavaScript
    /// truthiness for `event.ts:1286`'s `if (thisArgs)`, and a second copy of
    /// this one function is worse than widening it by one access level —
    /// `MainThreadWindow.installReadonlyGetter`'s own promotion, for the same
    /// reason.
    static func isFalsy(_ value: JSValue?) -> Bool {
        guard let value else { return true }
        if value.isUndefined || value.isNull { return true }
        if value.isBoolean { return !value.toBool() }
        if value.isNumber {
            let number = value.toDouble()
            return number == 0 || number.isNaN
        }
        if value.isString { return value.toString() == "" }
        return false
    }

    private enum DecodedDiagnosticsArgument {
        case removal
        case diagnostics([VSCodeAPI.ExtensionDiagnostic])
        case invalid
    }

    /// Decodes the `Diagnostic[] | undefined` shape used both by the
    /// single-Uri `set` overload's second argument and by each tuple's
    /// second slot in the array-taking overload. `.removal` for a
    /// genuinely absent/undefined/null value
    /// (`extHostDiagnostics.ts:77-81`'s `if (!diagnostics)`), `.invalid`
    /// for a present value that is not array-shaped or contains an
    /// undecodable element.
    private static func decodeDiagnosticsArgument(
        _ value: JSValue?, in context: JSContext
    ) -> DecodedDiagnosticsArgument {
        guard let value, !value.isUndefined, !value.isNull else { return .removal }
        guard value.isObject, let array = diagnosticArray(from: value, in: context) else { return .invalid }
        return .diagnostics(array)
    }

    /// Reads a JS array of `Diagnostic` values, skipping `null`/`undefined`
    /// elements (`coalesce()`, `extHostDiagnostics.ts:84,114`) but refusing
    /// the whole array — `nil`, not a partial result — on any other
    /// undecodable element, matching `DiagnosticTypes.swift`'s own
    /// `diagnosticRelatedInformationArray` contract.
    private static func diagnosticArray(
        from value: JSValue, in context: JSContext
    ) -> [VSCodeAPI.ExtensionDiagnostic]? {
        guard let lengthValue = value.forProperty("length"), lengthValue.isNumber else { return nil }
        let count = Int(lengthValue.toInt32())
        var result: [VSCodeAPI.ExtensionDiagnostic] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            guard let element = value.atIndex(index) else { return nil }
            if element.isUndefined || element.isNull { continue }
            guard let decoded = VSCodeAPI.diagnostic(from: element, in: context) else { return nil }
            result.append(decoded)
        }
        return result
    }

    /// Reads the array-taking `set` overload's argument: an array of
    /// `[Uri, Diagnostic[] | undefined]` tuples. `nil` — refusing the whole
    /// call — if any tuple's Uri slot or diagnostics slot fails to decode.
    private static func setEntriesArray(
        from value: JSValue, in context: JSContext
    ) -> [(url: URL, diagnostics: [VSCodeAPI.ExtensionDiagnostic]?)]? {
        guard let lengthValue = value.forProperty("length"), lengthValue.isNumber else { return nil }
        let count = Int(lengthValue.toInt32())
        var result: [(url: URL, diagnostics: [VSCodeAPI.ExtensionDiagnostic]?)] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            guard let tuple = value.atIndex(index), tuple.isObject,
                  let uriElement = tuple.atIndex(0),
                  let url = VSCodeAPI.url(from: uriElement, in: context) else {
                return nil
            }
            switch decodeDiagnosticsArgument(tuple.atIndex(1), in: context) {
            case .removal:
                result.append((url, nil))
            case .diagnostics(let diagnostics):
                result.append((url, diagnostics))
            case .invalid:
                return nil
            }
        }
        return result
    }

    /// A genuine JS `undefined` — a small local copy of
    /// `MainThreadWindow.undefinedValue(in:)`'s idea, returning `JSValue?`
    /// directly rather than `Any`: every call site here is a synchronous
    /// method result, never a promise-settlement argument, so there is no
    /// `NSNull()` fallback to widen into. Licensed as a third independent
    /// copy of this one-line idea by
    /// `MainThreadLanguageModels.swift:666-672`'s own precedent for
    /// `arrayValue(of:in:)` ("not a shared helper").
    private static func undefinedValue(in context: JSContext) -> JSValue? {
        JSValue(undefinedIn: context)
    }

    /// The disposed-collection return value for `set`/`delete`/`clear`/
    /// `get`/`forEach`, each contractually inert once disposed —
    /// `undefined`, resolved via `JSContext.current()` the
    /// same way every handler above resolves its own context, since these
    /// blocks run outside any handler method.
    private static func disposedUndefinedValue() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        return undefinedValue(in: context)
    }

    /// The disposed-collection return value for `has` — `false`, per the
    /// same inert-once-disposed contract `disposedUndefinedValue()` documents.
    private static func disposedFalseValue() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        return JSValue(bool: false, in: context)
    }

    /// A JS array holding `values`, `JSValue?`-returning for the same
    /// reason `undefinedValue(in:)` is — see that method's own doc.
    private static func arrayValue(of values: [JSValue], in context: JSContext) -> JSValue? {
        JSValue(object: values, in: context)
    }

    /// Decodes every diagnostic in `diagnostics` via
    /// `VSCodeAPI.diagnosticValue(for:in:)`, refusing the whole array —
    /// `nil`, not a partial one — the instant a single element fails,
    /// rather than a bare `compactMap`, which would silently hand the
    /// extension fewer diagnostics than the store actually holds for that
    /// Uri. Propagates the same contract `DiagnosticTypes.swift:483-486`
    /// (also `DiagnosticTypes.swift:572-582`) already enforces one level
    /// down; every call site below shares this one implementation rather
    /// than re-deciding it per site — only what a
    /// site does with a `nil` result (raise, or fail the one entry it
    /// belongs to) differs.
    private static func diagnosticValues(
        _ diagnostics: [VSCodeAPI.ExtensionDiagnostic], in context: JSContext
    ) -> [JSValue]? {
        var result: [JSValue] = []
        result.reserveCapacity(diagnostics.count)
        for diagnostic in diagnostics {
            guard let value = VSCodeAPI.diagnosticValue(for: diagnostic, in: context) else { return nil }
            result.append(value)
        }
        return result
    }

    /// One `[uri, diagnostics]` pair, as `forEach`'s callback receives it
    /// and as `Symbol.iterator` yields it — shared by `getDiagnostics()`'s
    /// no-argument branch and `pairsArrayValue(owner:)`.
    private static func pairValue(
        url: URL, diagnostics: [VSCodeAPI.ExtensionDiagnostic], in context: JSContext
    ) -> JSValue? {
        guard let uriValue = VSCodeAPI.uriValue(for: url, in: context) else { return nil }
        // Fails the whole pair — `nil` — on an undecodable diagnostic, the
        // same as the `uriValue` guard above already does for a bad Uri,
        // never shortening the diagnostics array within a pair that is
        // returned.
        guard let diagnosticsValues = diagnosticValues(diagnostics, in: context),
              let diagnosticsArrayValue = arrayValue(of: diagnosticsValues, in: context)
        else { return nil }
        return arrayValue(of: [uriValue, diagnosticsArrayValue], in: context)
    }

    /// Every entry in `entries` as a `[uri, diagnostics]` pair, refusing the
    /// whole array — `nil`, not a partial one — the instant a single entry
    /// fails to decode.
    ///
    /// The same contract `diagnosticValues(_:in:)` enforces one level down,
    /// applied one level up: an `if let` that appended only the pairs that
    /// decoded would hand the extension a shorter array that looks like a
    /// complete answer, and upstream (`extHostDiagnostics.ts:317-334`) never
    /// drops an entry.
    private static func pairValues(
        _ entries: [(url: URL, diagnostics: [VSCodeAPI.ExtensionDiagnostic])], in context: JSContext
    ) -> [JSValue]? {
        var result: [JSValue] = []
        result.reserveCapacity(entries.count)
        for entry in entries {
            guard let value = pairValue(
                url: entry.url, diagnostics: entry.diagnostics, in: context
            ) else { return nil }
            result.append(value)
        }
        return result
    }

    /// A small IIFE that assigns `target[Symbol.iterator]`, delegating to
    /// `getPairs()`'s own JS array's `[Symbol.iterator]()` — the same
    /// "build a real array, then borrow its own iterator" idiom
    /// `extension-runtime.js`'s `URLSearchParams.prototype.entries`
    /// (`:1045`) uses, rather than hand-writing a generator's `next()`
    /// protocol. No existing Swift call site in this codebase installs a
    /// `Symbol.iterator` (confirmed via a repository-wide search before
    /// writing this), so this is a fresh, minimal mechanism rather than a
    /// reused one — evaluated once per collection object, never cached,
    /// since a collection is created rarely compared to how often its
    /// members are read.
    private static let symbolIteratorInstallerSource = """
    (function (target, getPairs) {
        target[Symbol.iterator] = function () {
            var pairs = getPairs() || [];
            return pairs[Symbol.iterator]();
        };
    })
    """

    private static func installSymbolIterator(
        on object: JSValue,
        getPairs: @escaping @convention(block) () -> JSValue?,
        in context: JSContext
    ) {
        guard let installer = context.evaluateScript(symbolIteratorInstallerSource) else { return }
        installer.call(withArguments: [object, getPairs])
    }
}

extension MainThreadDiagnostics: Loggable {
    public static nonisolated let logger = makeLogger()
}
