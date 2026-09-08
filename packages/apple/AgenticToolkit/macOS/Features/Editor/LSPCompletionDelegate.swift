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
    /// still the one serving this document.
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

    /// The same discipline, for the trigger-character cache: identifies the
    /// most recent resolution so a superseded one cannot write over a newer
    /// one's answer.
    ///
    /// A counter of its own rather than a share of `currentRequestGeneration`,
    /// because the two caches have different lifetimes. `clearCache()` bumps
    /// the request generation on every window close and every applied
    /// completion — routine events that say nothing about which server serves
    /// this document — and a shared counter would make each of them throw away
    /// a trigger resolution that is in flight. Since `resolveTriggerCharacters`
    /// never retries on its own, a discarded write there is not re-asked for.
    private var currentTriggerGeneration = 0

    init(document: TextDocument, registry: LanguageServerRegistry) {
        self.document = document
        self.registry = registry
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
    /// — an answer already read from the session still serving this document is
    /// returned without touching the server — and `FileEditorState` calls it
    /// again whenever `registry.$sessions` changes, which is what turns the
    /// "no session yet" empty answer into the real one once a server appears.
    /// A caller without that subscription gets one answer and keeps it.
    ///
    /// **Overlapping calls are ordered by this method, not by its caller.** The
    /// `$sessions` subscription makes them reachable — a server disabled and
    /// re-enabled publishes twice while the first resolution is still suspended
    /// — so a superseded call neither writes the cache nor hands its own answer
    /// back to be published.
    @discardableResult
    func resolveTriggerCharacters() async -> Set<String> {
        // Claimed before the guard, not merely before the first `await`: the
        // clear below is a cache write too, and it has to supersede whatever is
        // already in flight rather than be undone by it.
        let generation = beginTriggerResolution()
        guard let session = registry.session(forLanguageId: document.languageId) else {
            // The server was removed or disabled. Its trigger set goes with it
            // rather than being answered on behalf of a session that is gone.
            resolvedTriggerCharacters = nil
            resolvedTriggerCharacterSource = nil
            return []
        }
        if let resolvedTriggerCharacters, resolvedTriggerCharacterSource === session {
            return resolvedTriggerCharacters
        }
        try? await session.start()
        guard let capabilities = await session.capabilities(),
              let completionProvider = capabilities.completionProvider else { return [] }
        return storeTriggerCharacters(
            Set(completionProvider.triggerCharacters ?? []),
            from: session,
            ifCurrent: generation
        )
    }

    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        // Everything the request needs is read before the first `await`: the
        // session, the URI, the language id and the cursor offset. After a
        // suspension the document may have been edited underneath us, and a
        // request built from a mixture of pre- and post-edit facts is exactly
        // the desynchronisation `DocumentSyncPipeline` exists to avoid.
        let generation = beginRequest()
        let triggerGeneration = beginTriggerResolution()
        guard let session = registry.session(forLanguageId: document.languageId),
              let offset = utf16Offset(of: cursorPosition) else {
            clearCache(ifCurrent: generation)
            return nil
        }
        let uri = document.uri
        let prefixStart = identifierStart(before: offset)
        let position = document.position(forUTF16Offset: offset)
        let defaultRange = LSPRange(
            start: document.position(forUTF16Offset: prefixStart),
            end: position
        )

        guard let capabilities = await session.capabilities(),
              let completionProvider = capabilities.completionProvider else {
            clearCache(ifCurrent: generation)
            return nil
        }
        // The trigger set is on its way past, so it is taken — through the
        // same guard `resolveTriggerCharacters` writes under, because this
        // write also lands after a suspension and a request superseded by a
        // fresher resolution must not undo it.
        _ = storeTriggerCharacters(
            Set(completionProvider.triggerCharacters ?? []),
            from: session,
            ifCurrent: triggerGeneration
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
            clearCache(ifCurrent: generation)
            return nil
        }

        let items = response?.items ?? []
        guard !items.isEmpty else {
            clearCache(ifCurrent: generation)
            return nil
        }

        let entries = items.map { item in
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

    /// Claims the next trigger-resolution generation, so a later resolution
    /// always wins over one that is still suspended.
    private func beginTriggerResolution() -> Int {
        currentTriggerGeneration += 1
        return currentTriggerGeneration
    }

    /// Stores a resolved trigger set unless a newer resolution has superseded
    /// this one, and returns the set that is authoritative afterwards.
    ///
    /// The check and both writes are one synchronous statement on the main
    /// actor, so nothing can interleave between deciding to write and writing.
    ///
    /// The *return* value is guarded for the same reason as the write. A
    /// superseded call still runs to completion — neither `await` here is a
    /// cancellation point — and its caller publishes whatever comes back, so
    /// handing back an answer this delegate has just refused to cache would put
    /// the stale set on screen and merely keep it out of the cache.
    /// `FileEditorState` does happen to drop a cancelled task's result, but
    /// that is the caller's discipline, not an invariant this class can lean
    /// on.
    private func storeTriggerCharacters(
        _ characters: Set<String>,
        from session: any LanguageServerSessionProtocol,
        ifCurrent generation: Int
    ) -> Set<String> {
        guard generation == currentTriggerGeneration else {
            // Superseded: the newer resolution's answer, or — if it has not
            // landed yet — this one, which it is about to replace.
            return resolvedTriggerCharacters ?? characters
        }
        resolvedTriggerCharacters = characters
        resolvedTriggerCharacterSource = session
        return characters
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
