import Foundation
import Testing
@testable import AgenticToolkitCore

/// The page a webview panel actually loads: the extension's own markup with
/// one script injected ahead of it.
///
/// Two things have to be true of that injection, and both are security
/// properties rather than conveniences. The bootstrap must run *before* any
/// script the extension ships, or `acquireVsCodeApi` is undefined at the moment
/// the page reaches for it. And the state embedded into it — which came out of
/// the pane-state database, which an extension wrote — must not be able to
/// leave the script element it is embedded in.
@Suite
struct WebviewHostDocumentTests {

    // MARK: - Where the bootstrap goes

    @Test("the bootstrap is injected inside the document's head")
    func bootstrapGoesInsideHead() throws {
        let rendered = WebviewHostDocument.html(
            wrapping: "<html><head><title>x</title></head><body>hi</body></html>",
            initialState: nil)

        let head = try #require(rendered.range(of: "<head>"))
        let headEnd = try #require(rendered.range(of: "</head>"))
        let bootstrap = try #require(rendered.range(of: WebviewHostDocument.messageHandlerName))
        #expect(bootstrap.lowerBound > head.upperBound)
        #expect(bootstrap.upperBound < headEnd.lowerBound)
    }

    /// The ordering that matters. An extension whose first `<script>` calls
    /// `acquireVsCodeApi()` — which is most of them, since that is how a
    /// webview gets its state back — runs before anything we could inject
    /// later, so injecting after the document's own scripts is the same as not
    /// injecting at all.
    @Test("the bootstrap precedes every script the extension ships")
    func bootstrapPrecedesTheExtensionsScripts() throws {
        let rendered = WebviewHostDocument.html(
            wrapping: "<html><head><script>acquireVsCodeApi()</script></head><body></body></html>",
            initialState: nil)

        let bootstrap = try #require(rendered.range(of: WebviewHostDocument.messageHandlerName))
        let theirs = try #require(rendered.range(of: "acquireVsCodeApi()"))
        #expect(bootstrap.lowerBound < theirs.lowerBound)
    }

    /// `webview.html` is a string an extension assigns, not a file a validator
    /// ever saw. A fragment, a document with no `<head>`, and an empty string
    /// are all things extensions really assign — none of them may lose the
    /// bootstrap.
    @Test(
        "a document with no head still gets the bootstrap first",
        arguments: ["<p>hi</p>", "<html><body>hi</body></html>", ""]
    )
    func bootstrapSurvivesAMissingHead(_ markup: String) throws {
        let rendered = WebviewHostDocument.html(wrapping: markup, initialState: nil)

        let bootstrap = try #require(rendered.range(of: WebviewHostDocument.messageHandlerName))
        if !markup.isEmpty {
            let theirs = try #require(rendered.range(of: markup))
            #expect(bootstrap.lowerBound < theirs.lowerBound)
        }
    }

    /// HTML tag names are case-insensitive, and hand-written webview markup is
    /// where `<HEAD>` still turns up. Matching only the lowercase spelling
    /// would silently fall back to the no-head path — which still works, so the
    /// bug would never announce itself.
    @Test("the head is matched case-insensitively")
    func headIsMatchedCaseInsensitively() throws {
        let rendered = WebviewHostDocument.html(
            wrapping: "<HTML><HEAD></HEAD><BODY>hi</BODY></HTML>", initialState: nil)

        let head = try #require(rendered.range(of: "<HEAD>"))
        let headEnd = try #require(rendered.range(of: "</HEAD>"))
        let bootstrap = try #require(rendered.range(of: WebviewHostDocument.messageHandlerName))
        #expect(bootstrap.lowerBound > head.upperBound)
        #expect(bootstrap.upperBound < headEnd.lowerBound)
    }

    @Test("the extension's own markup is carried through unchanged")
    func markupIsCarriedThroughUnchanged() {
        let body = "<body><p>café &amp; crème</p><img src=\"a#b.png\"></body>"
        let rendered = WebviewHostDocument.html(
            wrapping: "<html><head></head>\(body)</html>", initialState: nil)

        #expect(rendered.contains(body))
    }

    // MARK: - Embedding state

    @Test("state survives the round trip into the document")
    func stateIsEmbedded() {
        let rendered = WebviewHostDocument.html(
            wrapping: "<html><head></head><body></body></html>",
            initialState: #"{"scrollTop":42}"#)

        #expect(rendered.contains("42"))
    }

    /// The break-out. `setState` takes anything JSON-serializable, the value is
    /// persisted verbatim, and a restored panel embeds it into a `<script>`
    /// element — so a string containing `</script>` ends that element early and
    /// everything after it is markup. The state came from an extension, which
    /// is exactly the party this boundary exists to contain.
    @Test("state cannot close the script element it is embedded in")
    func stateCannotBreakOutOfTheScriptElement() {
        let payload = "</script><script>alert(1)</script>"
        let rendered = WebviewHostDocument.html(
            wrapping: "<html><head></head><body></body></html>",
            initialState: "{\"note\":\"\(payload)\"}")

        #expect(!rendered.contains("<script>alert(1)"))
        #expect(!rendered.contains(payload))
    }

    /// The same break-out by the other door. `<!--` inside a script element
    /// starts a comment that swallows the rest of the bootstrap, including the
    /// `acquireVsCodeApi` definition — so this one disables the bridge rather
    /// than running code, which is a quieter failure and no less a bug.
    @Test(
        "state cannot open an HTML comment or a tag",
        arguments: ["<!--", "-->", "<!--<script>", "</SCRIPT >"]
    )
    func stateCannotOpenAComment(_ payload: String) {
        let rendered = WebviewHostDocument.html(
            wrapping: "<html><head></head><body></body></html>",
            initialState: "{\"note\":\"\(payload)\"}")

        #expect(!rendered.contains(payload))
    }

    /// A panel with nothing saved must be distinguishable from one that saved
    /// a null: VS Code's `getState()` returns `undefined` before the first
    /// `setState`, and extensions branch on it to decide whether this is a
    /// restore or a first run.
    @Test("a panel with no saved state is undefined, not null")
    func absentStateIsUndefined() {
        let rendered = WebviewHostDocument.html(
            wrapping: "<html><head></head><body></body></html>", initialState: nil)

        #expect(rendered.contains("undefined"))
    }

    // MARK: - The names both sides share

    /// The handler name appears in two places that cannot see each other: the
    /// JavaScript this file generates, and the `WKUserContentController` the
    /// macOS half registers. It is declared once here so the macOS half reads
    /// it rather than spelling it again — a mismatch is a bridge that silently
    /// delivers nothing.
    @Test("the message handler name is declared once and is a valid JS identifier")
    func messageHandlerNameIsStable() {
        #expect(WebviewHostDocument.messageHandlerName == "agenticWebview")
        #expect(WebviewHostDocument.messageHandlerName.first?.isLetter == true)
        #expect(WebviewHostDocument.messageHandlerName.allSatisfy { $0.isLetter || $0.isNumber })
    }

    /// Every kind the page can send, so the macOS handler decodes a case rather
    /// than comparing strings it restated.
    @Test("the bootstrap sends only kinds the host decodes")
    func messageKindsAreClosed() {
        let rendered = WebviewHostDocument.html(
            wrapping: "<html><head></head><body></body></html>", initialState: nil)

        for kind in WebviewHostDocument.MessageKind.allCases {
            #expect(rendered.contains(kind.rawValue))
        }
    }
}
