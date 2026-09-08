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

    /// Resolved from the server's `completionProvider.triggerCharacters` on the
    /// first completion request and cached from then on.
    ///
    /// It cannot be resolved eagerly: `completionTriggerCharacters()` is
    /// synchronous by protocol and `capabilities()` is `async` on the session
    /// actor, so there is nowhere to await. **This is therefore empty until the
    /// first request has come back**, which is acceptable — the package also
    /// triggers on any letter or digit (see `SuggestionTriggerCharacterModel`),
    /// so completion still works before the set is filled in; only a leading
    /// `.` or `(` fails to open the window on the very first attempt.
    private var cachedTriggerCharacters: Set<String> = []

    init(document: TextDocument, registry: LanguageServerRegistry) {
        self.document = document
        self.registry = registry
    }

    // MARK: - CodeSuggestionDelegate

    func completionTriggerCharacters() -> Set<String> {
        cachedTriggerCharacters
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
        guard let session = registry.session(forLanguageId: document.languageId),
              let offset = utf16Offset(of: cursorPosition) else {
            clearCache()
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
            clearCache()
            return nil
        }
        // Assigned after an await on purpose, and safe to be: it is a pure
        // cache of a value that does not change over a session's life, so two
        // interleaved requests write the same thing and no invariant spans the
        // suspension.
        cachedTriggerCharacters = Set(completionProvider.triggerCharacters ?? [])

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
            clearCache()
            return nil
        }

        let items = response?.items ?? []
        guard !items.isEmpty else {
            clearCache()
            return nil
        }

        let entries = items.map { item in
            LSPCompletionEntry(item: item, requestRange: Self.range(of: item) ?? defaultRange)
        }
        cachedEntries = entries
        cacheAnchorOffset = prefixStart

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

    private func clearCache() {
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
