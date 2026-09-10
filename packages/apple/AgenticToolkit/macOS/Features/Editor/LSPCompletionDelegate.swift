//
//  LSPCompletionDelegate.swift
//  AgenticToolkit
//

import AgenticToolkitLanguage
import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol

/// Drives `CodeEditSourceEditor`'s completion window from a language server.
///
/// One instance **per open document**, not per pane and not per project: it has
/// to know which `TextDocument` it is completing, and that document is what
/// every offset↔`Position` conversion is resolved against. `FileEditorState.Slot`
/// owns it, because `SourceEditor` stores `completionDelegate` as a `weak var`
/// and something has to hold it strongly for the life of the editor.
@MainActor
final class LSPCompletionDelegate: CodeSuggestionDelegate {

    private let document: TextDocument
    private let registry: LanguageServerRegistry

    /// Extension-contributed snippets, or `nil` when no extension host is
    /// wired up. Their items carry `insertTextFormat == .snippet`, so they
    /// reach the text view through `insertionText(for:)` exactly as a
    /// server's own snippet completions do.
    private let snippets: SnippetStore?

    /// The entries the last request produced, and the UTF-16 offset the token
    /// they complete starts at. `completionOnCursorMove` filters this set by
    /// whatever has been typed since, which is what makes that method able to
    /// be synchronous.
    private var cachedEntries: [LSPCompletionEntry] = []
    private var cacheAnchorOffset: Int?

    /// The server's `completionProvider.triggerCharacters`, once resolved.
    ///
    /// `nil` means "not resolved yet", which is not the same as "the server
    /// declares none". `resolveTriggerCharacters()` fills this in eagerly when
    /// the document's editor slot opens, so the set is known before the user
    /// types anything.
    private var resolvedTriggerCharacters: Set<String>?

    /// Which session the resolved set came from.
    ///
    /// Kept because a session is not permanent: editing a server's command in
    /// settings retires the old session and creates a new one for the same
    /// language, and the retired server's trigger characters must not outlive
    /// it. A cached answer is only reused while the session it was read from is
    /// still the one serving this document **and** that session is still
    /// running — the same object can go on serving this document after it has
    /// died, since nothing removes a failed session from `registry.sessions`.
    ///
    /// A `weak` reference rather than an `ObjectIdentifier`, because an
    /// identifier is an address: once the session it named is deallocated the
    /// allocator may hand that address to the *next* session, and a stale key
    /// then compares equal to a session it was never read from. A weak
    /// reference cannot be address-confused — it nils out on deallocation, and
    /// a `nil` source is simply a cache miss. `LanguageServerSessionProtocol`
    /// refines `Actor`, so it is already class-bound and this costs nothing.
    private weak var resolvedTriggerCharacterSource: (any LanguageServerSessionProtocol)?

    /// Identifies the most recent completion request, so a superseded one
    /// cannot publish over the cache belonging to a newer one.
    ///
    /// `completionSuggestionsRequested` suspends twice, and the package does
    /// not save us: `SuggestionViewModel.showCompletions` cancels the previous
    /// request's task but only checks cancellation *after* `await
    /// delegate.completionSuggestionsRequested(...)` returns, so an abandoned
    /// request's continuation always runs to completion — cache writes and
    /// cache *wipes* included. Every write below is therefore gated on this
    /// still naming the request doing the writing.
    private var currentRequestGeneration = 0

    /// The trigger-character cache is ordered by these two, which between them
    /// hold an invariant with two halves:
    ///
    /// 1. A write must never overwrite one derived from newer information.
    /// 2. A call that writes nothing must not stop another call from writing.
    ///
    /// A claim-a-ticket counter buys the first half at the cost of the second,
    /// and that cost is the whole bug this shape replaced: a caller that took a
    /// ticket and then returned early — no session, no capabilities yet — left
    /// its ticket the newest one, so a resolution still suspended inside the
    /// server was refused when it resumed. Nothing wrote anything;
    /// `resolveTriggerCharacters` does not retry on its own and
    /// `registry.$sessions` does not re-emit, so the set stayed empty and `.`
    /// silently stopped opening the completion window.
    ///
    /// So these do not order *calls*, they order *information*.
    /// `triggerReadClock` stamps each read of the facts an answer is derived
    /// from, taken at entry before the first suspension, and
    /// `resolvedTriggerReadStamp` is the stamp of the read the cached answer
    /// came from. `storeTriggerCharacters` admits a write whose stamp is at
    /// least the cached one's — that is half 1 — and because the bar moves only
    /// when someone actually writes, a stamp nobody used blocks nobody, which
    /// is half 2.
    ///
    /// A clock of its own rather than a share of `currentRequestGeneration`,
    /// because the two caches have different lifetimes. `clearCache()` bumps
    /// the request generation on every window close and every applied
    /// completion — routine events that say nothing about which server serves
    /// this document — and a shared counter would make each of them discard a
    /// trigger resolution that is in flight and that nothing would re-ask for.
    private var triggerReadClock = 0
    private var resolvedTriggerReadStamp = 0

    /// `snippets` is optional and defaults to absent because an editor is
    /// perfectly usable with no extensions installed, and nothing in this
    /// class should behave differently when there are none: with no store the
    /// completion list is exactly what the server sent, as it was before
    /// extension snippets existed. Injected rather than reached for — the
    /// store belongs to whoever owns the `ExtensionRegistry`, not to a
    /// per-document delegate.
    init(
        document: TextDocument,
        registry: LanguageServerRegistry,
        snippets: SnippetStore? = nil
    ) {
        self.document = document
        self.registry = registry
        self.snippets = snippets
    }

    // MARK: - CodeSuggestionDelegate

    /// **This package never calls this method.** It is a `CodeSuggestionDelegate`
    /// requirement with a default implementation, and grepping the whole of
    /// `CodeEditSourceEditor` finds only the declaration and that default — no
    /// call site. The live path is
    /// `SourceEditorConfiguration.peripherals.codeSuggestionTriggerCharacters`,
    /// which `SuggestionTriggerCharacterModel` reads off the controller's
    /// configuration; `FileEditorState` publishes the resolved set and
    /// `FileEditorContentView.makeEditor` feeds it into that field, and the
    /// configuration is diffed, so a set that arrives after the editor was
    /// built still reaches the controller.
    ///
    /// Kept because it is where the next reader looks first, and answering it
    /// honestly costs nothing.
    func completionTriggerCharacters() -> Set<String> {
        resolvedTriggerCharacters ?? []
    }

    /// Asks the server what characters should open the completion window, and
    /// caches the answer.
    ///
    /// Called when the document's editor slot opens rather than lazily on the
    /// first completion request, because the request path is not reached until
    /// the window is *already* open — a set resolved there is resolved too late
    /// to have opened it. `start()` is joined first, not initiated: the registry
    /// starts every session in its own `Task`, and a session that is still
    /// initialising answers `capabilities()` with `nil`. `start()` on a running
    /// session returns immediately and on a starting one awaits the same task
    /// the registry is awaiting, so this waits exactly as long as it must.
    ///
    /// Returns the empty set when no session serves this document's language,
    /// when the server declares no `completionProvider`, and when it declares
    /// one with no trigger characters.
    ///
    /// **This method never retries on its own.** It is safe to call repeatedly
    /// — an answer already read from the session still serving this document,
    /// while that session is still running, is returned without touching the
    /// server — and `FileEditorState` calls it again whenever
    /// `registry.$sessions` **or** `registry.$sessionStates` changes, which is
    /// what turns the "no session yet" empty answer into the real one once a
    /// server appears, and what turns a stale answer back to empty once a
    /// server that served it dies. A caller without that subscription gets one
    /// answer and keeps it.
    ///
    /// **Overlapping calls are ordered by this method, not by its caller.** The
    /// `$sessions` subscription makes them reachable — a server disabled and
    /// re-enabled publishes twice while the first resolution is still suspended
    /// — so a superseded call neither writes the cache nor hands its own answer
    /// back to be published. Ordering is by the age of the information, not by
    /// who started last, so a call that overtakes this one and then returns
    /// without an answer does not stop this one from landing its own; see
    /// `triggerReadClock`.
    @discardableResult
    func resolveTriggerCharacters() async -> Set<String> {
        // Stamped before the session is read, so the stamp dates the oldest
        // fact this call could write from.
        let stamp = nextTriggerReadStamp()
        guard let session = registry.session(forLanguageId: document.languageId) else {
            // The server was removed or disabled. Its trigger set goes with it
            // rather than being answered on behalf of a session that is gone —
            // recorded through the same guard as any other answer, so a
            // resolution still suspended against the retired session cannot
            // undo it, and so a caller this write supersedes falls back to
            // "none" instead of to the set it was about to publish.
            return storeTriggerCharacters(nil, from: nil, readAt: stamp)
        }
        // `case .running = ...` rather than `== .running`:
        // `LanguageServerSessionState` is deliberately not `Equatable` — its
        // `.failed` case carries `any Error` by way of `LanguageServerFailure`
        // — so a pattern match is what is available, and it reads the same as
        // the equality this cache hit needs. Stated positively, as "the one
        // state that hits", rather than by listing every terminal state that
        // should miss: a state added to the enum tomorrow then defaults to
        // re-asking the server, not to trusting a cache that has never seen it.
        //
        // The identity test still runs first, but not because it is what makes
        // the key meaningful: `session` was just read out of
        // `registry.session(forLanguageId:)`, i.e. `sessions[configuration.id]`,
        // and `sessions[k].id == k` holds for every key in that dictionary
        // regardless of what the `===` test decides — so `session.id` is
        // always a meaningful key into `registry.sessionStates`. The `===`
        // test answers a different question, asked first because it is
        // cheaper to rule out: *which* session the cached answer came from,
        // so a predecessor's stale cache is not credited to its successor.
        if let resolvedTriggerCharacters,
           resolvedTriggerCharacterSource === session,
           case .running = registry.sessionStates[session.id] {
            return resolvedTriggerCharacters
        }
        try? await session.start()
        guard let capabilities = await session.capabilities(),
              let completionProvider = capabilities.completionProvider else {
            // `capabilities()` answers `nil` on both sides of `.running`, not
            // only on the way up: before the handshake finishes (`server` is
            // set but not yet `.running`), and — since
            // `LanguageServerSession.capabilities()` gates on `.running`
            // itself — after the session has died, whether by `stop()` or by
            // a crash it never asked for. So this guard is what turns a dead
            // session's stale capabilities into "unresolved" instead of
            // silently re-caching them; the alternative is the server
            // declaring no completion support at all. Recorded as
            // *unresolved* rather than as an empty answer either way, because
            // the cache hit above must not start handing back `[]` for a
            // server that is merely starting; the next `registry.$sessions`
            // or `registry.$sessionStates` change is what asks again.
            return storeTriggerCharacters(nil, from: nil, readAt: stamp)
        }
        return storeTriggerCharacters(
            Set(completionProvider.triggerCharacters ?? []),
            from: session,
            readAt: stamp
        )
    }

    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        // Everything the request needs is read before the first `await`: the
        // cursor offset, the URI, the language id, the snippets for it and
        // the session. After a suspension the document may have been edited
        // underneath us, and a request built from a mixture of pre- and
        // post-edit facts is exactly the desynchronisation
        // `DocumentSyncPipeline` exists to avoid.
        let generation = beginRequest()
        let triggerStamp = nextTriggerReadStamp()
        // The caret first, and alone: an offset that cannot be located is the
        // one failure with no window to show. There is no `prefixStart` to
        // anchor one at and no range to insert into, so nothing below can run.
        guard let offset = utf16Offset(of: cursorPosition) else {
            clearCache(ifCurrent: generation)
            return nil
        }
        let uri = document.uri
        let languageId = document.languageId
        let prefixStart = identifierStart(before: offset)
        let position = document.position(forUTF16Offset: offset)
        let defaultRange = LSPRange(
            start: document.position(forUTF16Offset: prefixStart),
            end: position
        )
        // Read here, above every server guard, because a snippet needs no
        // server. The languages snippet packs target — HTML, Markdown, YAML, a
        // plain config format — are exactly the ones least likely to have a
        // language server installed, and a window that never opens for them
        // would make the feature invisible where it matters most.
        let snippetItems = snippets?.snippets(forLanguage: languageId).map { $0.completionItem() } ?? []

        // No server for this language. Everything below is about talking to
        // one, so the snippets are the whole answer.
        guard let session = registry.session(forLanguageId: languageId) else {
            return publish(
                items: [],
                snippetItems: snippetItems,
                defaultRange: defaultRange,
                prefixStart: prefixStart,
                generation: generation
            )
        }

        guard let capabilities = await session.capabilities(),
              let completionProvider = capabilities.completionProvider else {
            // A server that does not complete — or has not finished its
            // handshake — is not a reason to withhold the user's snippets.
            return publish(
                items: [],
                snippetItems: snippetItems,
                defaultRange: defaultRange,
                prefixStart: prefixStart,
                generation: generation
            )
        }
        // The trigger set is on its way past, so it is taken — through the
        // same guard `resolveTriggerCharacters` writes under, because this
        // write also lands after a suspension and a request superseded by a
        // fresher resolution must not undo it.
        //
        // This path is opportunistic, not authoritative: it writes only when it
        // has a real answer, and the early returns above deliberately
        // record nothing about trigger characters. Under the stamps that costs
        // no other caller anything — an unused stamp is not a claim.
        //
        // No liveness check is added here on purpose, even though this write
        // has none of its own: it does not need one, because the guard above
        // already stops it from being reached for a dead session, courtesy of
        // `LanguageServerSession.capabilities()` gating on `.running`. The
        // division of labour, deliberately kept to one enforcement point
        // rather than duplicated at every write site: `resolveTriggerCharacters`'s
        // cache-hit guard stops a dead session's *cached* answer from being
        // returned; `capabilities()` returning `nil` for a dead session stops
        // a dead session's answer from being *cached again*, here and
        // anywhere else that reaches this method. Neither subsumes the
        // other, and a second liveness guard at this call site would only
        // teach the next reader that liveness is checked ad hoc rather than
        // once, at the source.
        _ = storeTriggerCharacters(
            Set(completionProvider.triggerCharacters ?? []),
            from: session,
            readAt: triggerStamp
        )

        let response: CompletionResponse
        do {
            response = try await session.completion(
                CompletionParams(
                    uri: uri,
                    position: position,
                    triggerKind: .invoked,
                    triggerCharacter: nil
                )
            )
        } catch {
            // A failed request says nothing about the snippets: they were read
            // from disk at install time and are just as valid now.
            return publish(
                items: [],
                snippetItems: snippetItems,
                defaultRange: defaultRange,
                prefixStart: prefixStart,
                generation: generation
            )
        }

        return publish(
            items: response?.items ?? [],
            snippetItems: snippetItems,
            defaultRange: defaultRange,
            prefixStart: prefixStart,
            generation: generation
        )
    }

    /// The window for a completed request: the server's items first, snippets
    /// after, everything anchored at `prefixStart`.
    ///
    /// The single exit for all four ways `completionSuggestionsRequested` can
    /// finish — no server, no completion capability, a request that threw, and
    /// a request that answered. Each of those differs only in how many server
    /// items it has, which is a value, not a control path; funnelling them
    /// through here is what stops the merge, the cache write and the anchoring
    /// from being repeated four times and drifting.
    ///
    /// `nil`, with the cache cleared, when there is nothing at all to show —
    /// the only condition under which the package should not open a window.
    private func publish(
        items: [CompletionItem],
        snippetItems: [CompletionItem],
        defaultRange: LSPRange,
        prefixStart: Int,
        generation: Int
    ) -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        // Snippets come after the server's items, at equal relevance rather
        // than interleaved by it: the server knows this document and a snippet
        // file does not, so anything it has to say outranks a snippet that
        // merely matches the prefix. Not pre-filtered by what has been typed
        // either — `completionOnCursorMove` filters the whole cached set on
        // `filterKey`, and a second filter here would only be a different one.
        //
        // Snippets count towards there being a window at all. A server that
        // answers with nothing — mid-keyword, or one that only completes after
        // a `.` — must not silence snippets the user installed for exactly
        // those places, and neither must a server that is absent, mute or
        // broken.
        guard !items.isEmpty || !snippetItems.isEmpty else {
            clearCache(ifCurrent: generation)
            return nil
        }

        // Snippet items carry no `textEdit` — a snippet file has no document
        // range to name — so `range(of:)` answers `nil` for them and they take
        // the same `defaultRange` the server's rangeless items take.
        let entries = (items + snippetItems).map { item in
            LSPCompletionEntry(item: item, requestRange: Self.range(of: item) ?? defaultRange)
        }
        // The window itself is still returned when this request has been
        // superseded — the package decides what to do with a returned value —
        // but the cache `completionOnCursorMove` filters is left alone, because
        // it now describes a newer caret than this request was made at.
        if isCurrent(generation) {
            cachedEntries = entries
            cacheAnchorOffset = prefixStart
        }

        // The window is anchored at the start of the token being completed, not
        // at the caret, so it stays put as the user keeps typing.
        return (
            windowPosition: CursorPosition(range: NSRange(location: prefixStart, length: 0)),
            items: entries
        )
    }

    func completionOnCursorMove(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> [CodeSuggestionEntry]? {
        guard let anchor = cacheAnchorOffset,
              let offset = utf16Offset(of: cursorPosition),
              offset >= anchor else {
            // Moved before the token the cached set was requested for. `nil`,
            // not `[]`: the package closes the window on either, but `nil` says
            // "this cache does not apply here" rather than "the server had
            // nothing", and only the first is true.
            return nil
        }

        let text = document.text as NSString
        guard anchor <= text.length, offset <= text.length else { return nil }

        let typed = text.substring(with: NSRange(location: anchor, length: offset - anchor))
        // Any whitespace means the caret has left the identifier entirely.
        guard !typed.contains(where: { $0.isWhitespace }) else { return nil }
        guard !typed.isEmpty else { return cachedEntries }

        let prefix = typed.lowercased()
        return cachedEntries.filter { $0.filterKey.lowercased().hasPrefix(prefix) }
    }

    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        // The protocol hands over `CodeSuggestionEntry`, and the package puts
        // its own `JumpToDefinitionLink`s through the same window. An entry this
        // delegate did not create is not ours to apply.
        guard let entry = item as? LSPCompletionEntry else { return }

        // `cursorPosition` is the *live* caret at the moment of the click or
        // Return — `SuggestionViewModel.applySelectedItem` passes
        // `activeTextView.cursorPositions.first` — not the position the request
        // was made at. Whatever was typed while the window was open lies between
        // the entry's request range and here, so the replacement has to swallow
        // it or it is left duplicated after the inserted text.
        var range = document.nsRange(for: entry.requestRange)
        if let cursorPosition, let liveOffset = utf16Offset(of: cursorPosition) {
            let end = max(range.location + range.length, liveOffset)
            range = NSRange(location: range.location, length: max(0, end - range.location))
        }

        textView.textView.replaceCharacters(in: range, with: Self.insertionText(for: entry.item))
        clearCache()
    }

    func completionWindowDidClose() {
        clearCache()
    }

    // MARK: - Cursor conversion

    /// The UTF-16 offset a `CursorPosition` names, or `nil` if it names none.
    ///
    /// Both shapes of `CursorPosition` reach this delegate, and neither is
    /// optional to handle. The trigger path builds `CursorPosition(range:)`
    /// (`SuggestionTriggerCharacterModel.textView(_:didReplaceContentsIn:with:)`),
    /// whose `start` is the placeholder `(-1, -1)`; the selection path passes a
    /// position out of `TextViewController.cursorPositions`, which
    /// `updateCursorPosition()` fills in completely. So the range is preferred
    /// where it is real, and the 1-indexed line/column is converted otherwise —
    /// through `TextDocument`, which is the only place offset↔`Position`
    /// conversion lives.
    private func utf16Offset(of position: CursorPosition) -> Int? {
        if position.range.location != NSNotFound {
            return position.range.location
        }
        guard position.start.line > 0, position.start.column > 0 else { return nil }
        return document.utf16Offset(
            for: Position(line: position.start.line - 1, character: position.start.column - 1)
        )
    }

    /// Walks back from `offset` over identifier characters to find where the
    /// token being completed starts — the fallback replacement range for a
    /// server that sent no `textEdit`.
    private func identifierStart(before offset: Int) -> Int {
        let text = document.text as NSString
        var start = min(max(0, offset), text.length)
        let identifierCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        while start > 0 {
            guard let scalar = Unicode.Scalar(text.character(at: start - 1)),
                  identifierCharacters.contains(scalar) else { break }
            start -= 1
        }
        return start
    }

    // MARK: - Request generations

    /// Claims the next generation for a request that is about to suspend.
    /// Called before the first `await`, so a later request always wins.
    private func beginRequest() -> Int {
        currentRequestGeneration += 1
        return currentRequestGeneration
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == currentRequestGeneration
    }

    /// Stamps a read of the facts a trigger answer will be derived from. Taken
    /// before the first `await`, so the stamp dates the information rather than
    /// the moment the answer happens to come back.
    ///
    /// Taking one commits the caller to nothing. An unused stamp never becomes
    /// the bar `storeTriggerCharacters` compares against, so a call that takes
    /// a stamp and then returns without an answer leaves every other call
    /// exactly as free to write as it was.
    private func nextTriggerReadStamp() -> Int {
        triggerReadClock += 1
        return triggerReadClock
    }

    /// Records a trigger answer read at `stamp` unless the cache already holds
    /// one derived from newer information, and returns the answer that is
    /// authoritative afterwards.
    ///
    /// `nil` characters — with a `nil` session — record *unresolved*: no server
    /// serves this document, or the one that does has not said yet. Every path
    /// that reaches a verdict about trigger characters goes through here, so
    /// nothing writes those properties behind this comparison's back.
    ///
    /// The comparison and all three writes are one synchronous statement on the
    /// main actor, so nothing can interleave between deciding to write and
    /// writing. A stamp is never issued twice, so `>=` only ever admits
    /// strictly newer information.
    ///
    /// The *return* value is guarded for the same reason as the write. A
    /// superseded call still runs to completion — neither `await` in
    /// `resolveTriggerCharacters` is a cancellation point — and its caller
    /// publishes whatever comes back, so handing back an answer this delegate
    /// has just refused to cache would put the stale set on screen and merely
    /// keep it out of the cache. Refusal here means a newer answer has already
    /// landed, so the cache is exactly what to hand back — including when that
    /// newer answer was "no session", which is why the fallback is `[]` and not
    /// the caller's own set.
    /// `FileEditorState` does happen to drop a cancelled task's result, but
    /// that is the caller's discipline, not an invariant this class can lean
    /// on.
    private func storeTriggerCharacters(
        _ characters: Set<String>?,
        from session: (any LanguageServerSessionProtocol)?,
        readAt stamp: Int
    ) -> Set<String> {
        guard stamp >= resolvedTriggerReadStamp else { return resolvedTriggerCharacters ?? [] }
        resolvedTriggerCharacters = characters
        resolvedTriggerCharacterSource = session
        resolvedTriggerReadStamp = stamp
        return characters ?? []
    }

    /// Empties the cache and invalidates every in-flight request, so a response
    /// that is still on its way cannot repopulate a cache the user has already
    /// dismissed. Only the synchronous paths — apply and window-close — may
    /// clear this unconditionally.
    private func clearCache() {
        currentRequestGeneration += 1
        cachedEntries = []
        cacheAnchorOffset = nil
    }

    /// Empties the cache only if `generation` is still the newest request.
    /// Used by every failure path in `completionSuggestionsRequested`: a stale
    /// request wiping a newer one's entries is the same defect as overwriting
    /// them, and empty or thrown responses are exactly what a superseded
    /// one-character prefix tends to produce.
    private func clearCache(ifCurrent generation: Int) {
        guard isCurrent(generation) else { return }
        cachedEntries = []
        cacheAnchorOffset = nil
    }

    // MARK: - Item text

    /// The range the server itself wants replaced, if it named one. An
    /// `InsertReplaceEdit` offers two: `replace` is the one that matches this
    /// delegate's own behaviour of overwriting the token being completed.
    private static func range(of item: CompletionItem) -> LSPRange? {
        switch item.textEdit {
        case .optionA(let edit): return edit.range
        case .optionB(let edit): return edit.replace
        case nil: return nil
        }
    }

    /// What to insert: the `textEdit`'s text, else `insertText`, else the label.
    private static func insertionText(for item: CompletionItem) -> String {
        let raw: String
        switch item.textEdit {
        case .optionA(let edit): raw = edit.newText
        case .optionB(let edit): raw = edit.newText
        case nil: raw = item.insertText ?? item.label
        }
        guard item.insertTextFormat == .snippet else { return raw }
        return plainText(ofSnippet: raw)
    }

    /// A snippet's text with its placeholder syntax removed.
    ///
    /// **Limitation, deliberate:** tabstop navigation is not implemented. Doing
    /// it properly needs editor support that does not exist here — a stack of
    /// pending tabstop ranges surviving edits, and a key handler to move between
    /// them — so a snippet is inserted as flat text with its placeholder
    /// *defaults* kept (`${1:name}` becomes `name`) and its bare tabstops
    /// (`$0`, `$1`) dropped. The caret lands after the inserted text.
    ///
    /// Built from `Snippet`'s element structure rather than a regex over
    /// `.value`: `.value` is the raw markup and the type exposes no plain-text
    /// accessor, but `enumerateElements` already does the parsing.
    private static func plainText(ofSnippet value: String) -> String {
        var result = ""
        Snippet(value: value).enumerateElements { element in
            switch element {
            case .text(let text):
                result += text
            case .placeholder(_, let text):
                result += text
            case .tabstop:
                break
            // The parser in this version of `LanguageServerProtocol` produces
            // only `.text`, `.tabstop` and `.placeholder`; the three below are
            // declared on `Snippet.Element` but never constructed. Handled
            // anyway so a future parser that does emit them degrades to
            // something readable rather than failing to compile.
            case .choice(_, let options):
                result += options.first ?? ""
            case .variable(_, let defaultValue):
                result += defaultValue
            case .variableTransform:
                break
            }
        }
        return result
    }
}
