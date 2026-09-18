//
//  WebviewHostDocument.swift
//  AgenticToolkit
//

import Foundation

/// The page a webview panel loads: the extension's own markup, with one script
/// injected ahead of it.
///
/// `webview.html` is a string an extension assigns, never a file anything
/// validated, so this makes no assumptions about it being a well-formed
/// document — a fragment, a document with no `<head>`, and an empty string are
/// all things extensions really assign, and all of them have to come back with
/// a working bridge.
///
/// **The bootstrap goes first, deliberately.** It is injected immediately after
/// the opening `<head>` tag, which puts it *before* the extension's own
/// `<meta http-equiv="Content-Security-Policy">` — and a meta policy governs
/// only what is parsed after it. So an extension's CSP constrains the
/// extension's scripts, exactly as it is meant to, and cannot switch off the
/// bridge it is talking through. Ordering is not a convenience here: an
/// extension whose first script calls `acquireVsCodeApi()` is the normal case,
/// because that is how a restored panel gets its state back.
///
/// Foundation only: the whole of it is string assembly, and the escaping below
/// is the kind of thing that should be provable without a browser.
public enum WebviewHostDocument {

    /// The `WKUserContentController` handler the injected script posts to.
    ///
    /// Declared here rather than beside the `WKScriptMessageHandler` because
    /// the two spellings cannot see each other — this file *generates* one of
    /// them into JavaScript — and a mismatch is a bridge that silently
    /// delivers nothing rather than one that fails to build (`dry`).
    public static let messageHandlerName = "agenticWebview"

    /// Everything the page can send. The host decodes a case rather than
    /// comparing strings it restated.
    public enum MessageKind: String, Sendable, CaseIterable {
        /// `vscode.postMessage(...)` — for the extension.
        case postMessage
        /// `vscode.setState(...)` — for the pane-state database.
        case setState
    }

    /// The document to load, wrapping the extension's markup.
    ///
    /// - Parameters:
    ///   - extensionHTML: `webview.html`, exactly as the extension assigned it.
    ///     It is carried through unchanged; this only inserts.
    ///   - initialState: The JSON text of whatever the panel last passed to
    ///     `setState`, or `nil` if it never did. `nil` becomes `undefined`
    ///     rather than `null`, because extensions branch on that to tell a
    ///     restore from a first run.
    public static func html(wrapping extensionHTML: String, initialState: String?) -> String {
        let bootstrap = "<script>\n\(bootstrapScript(initialState: initialState))\n</script>"

        guard let insertion = headStartTagEnd(in: extensionHTML) else {
            // No head to put it in — before everything, then. A script token
            // ahead of `<html>` is reprocessed into the head by any HTML
            // parser, and prepending is the one placement that cannot land in
            // the middle of markup we do not otherwise touch.
            return bootstrap + extensionHTML
        }
        var document = extensionHTML
        document.insert(contentsOf: bootstrap, at: insertion)
        return document
    }

    // MARK: - The injected script

    private static func bootstrapScript(initialState: String?) -> String {
        let state = initialState.map { "JSON.parse(\"\(escapedForScriptElement($0))\")" }
            ?? "undefined"

        return """
        (function () {
            var state = \(state);
            var acquired = false;
            function send(kind, body) {
                var handlers = window.webkit && window.webkit.messageHandlers;
                var handler = handlers && handlers.\(messageHandlerName);
                if (handler) { handler.postMessage({ kind: kind, body: body }); }
            }
            window.acquireVsCodeApi = function () {
                if (acquired) {
                    throw new Error('An instance of the VS Code API has already been acquired');
                }
                acquired = true;
                return Object.freeze({
                    postMessage: function (message) {
                        send('\(MessageKind.postMessage.rawValue)', message);
                    },
                    getState: function () { return state; },
                    setState: function (newState) {
                        state = newState;
                        send('\(MessageKind.setState.rawValue)', newState);
                        return newState;
                    }
                });
            };
        }());
        """
    }

    /// Escapes text for a JavaScript string literal that lives inside a
    /// `<script>` element.
    ///
    /// The state this embeds came out of the pane-state database, which means
    /// an extension wrote it — the party this boundary exists to contain. Two
    /// break-outs matter and neither is closed by JSON encoding alone, because
    /// the HTML parser reads the script element's contents before JavaScript
    /// ever sees them:
    ///
    ///   * `</script>` ends the element early and everything after it is
    ///     markup, which is script injection.
    ///   * `<!--` opens a comment that swallows the rest of the bootstrap,
    ///     including `acquireVsCodeApi` — a quieter failure and no less a bug.
    ///
    /// So `<`, `>` and `&` go out as `\u00XX` escapes: they are then invisible
    /// to the HTML parser and identical to JavaScript, which is what makes the
    /// round trip lossless rather than sanitising. U+2028 and U+2029 follow
    /// because JavaScript treats them as line terminators inside a literal.
    private static func escapedForScriptElement(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text.unicodeScalars {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            case "<", ">", "&", "\u{2028}", "\u{2029}":
                escaped += String(format: "\\u%04X", character.value)
            default:
                if character.value < 0x20 {
                    escaped += String(format: "\\u%04X", character.value)
                } else {
                    escaped.unicodeScalars.append(character)
                }
            }
        }
        return escaped
    }

    // MARK: - Finding the head

    /// The index just past the opening `<head>` tag, or `nil` if there is no
    /// head this can place a script inside with certainty.
    ///
    /// Certainty is the whole point of the `nil`s below. `<header>` starts with
    /// `<head` and is not a head; a start tag carrying a quoted attribute could
    /// hold a `>` inside the quotes, and splitting at that one would cut the
    /// extension's markup in half. Both fall back to prepending, which is
    /// always correct and merely less tidy — a wrong insertion point would
    /// corrupt a document we promised only to insert into.
    private static func headStartTagEnd(in html: String) -> String.Index? {
        var searchStart = html.startIndex
        while let match = html.range(
            of: "<head", options: .caseInsensitive, range: searchStart..<html.endIndex) {
            guard match.upperBound < html.endIndex else { return nil }

            if html[match.upperBound] == ">" {
                return html.index(after: match.upperBound)
            }
            if html[match.upperBound].isWhitespace {
                for index in html.indices[match.upperBound...] {
                    if html[index] == "\"" || html[index] == "'" { return nil }
                    if html[index] == ">" { return html.index(after: index) }
                }
                return nil
            }
            // `<header>`, `<heading>` — not a head. Keep looking.
            searchStart = match.upperBound
        }
        return nil
    }
}
