import Foundation
import Testing
@testable import AgenticToolkitCore

/// The webview scheme's two jobs: naming a file so a `WKWebView` can ask for
/// it, and deciding whether it may have it.
///
/// The second is the security boundary of the whole webview feature. A webview
/// runs an extension's own HTML and JavaScript, so the page is hostile by
/// assumption; `localResourceRoots` is the only thing standing between it and
/// the user's disk, and it is enforced here rather than in the page. Every
/// refusal case below is a real attack shape, not a validation nicety.
@Suite
struct WebviewResourceURLTests {

    private func makeTemporaryDirectory(_ name: String = "root") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebviewResourceURLTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private let panel = "panel-1"

    // MARK: - Naming a file

    /// The extension-facing direction — VS Code spells it `asWebviewUri`. A
    /// page cannot load `file:` URLs, so every resource an extension wants to
    /// show has to be re-spelled into the scheme the handler answers on.
    @Test("a file URL round-trips through the webview scheme")
    func fileURLRoundTrips() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("media/style.css")

        let webviewURL = WebviewResourceURL.url(forFile: file, panelID: panel)
        #expect(webviewURL.scheme == WebviewResourceURL.scheme)

        let target = try WebviewResourceURL.target(
            of: webviewURL, panelID: panel, localResourceRoots: [root])
        #expect(target == .file(file.resolvingSymlinksInPath().standardizedFileURL))
    }

    /// A path with characters that must be percent-encoded to survive a URL is
    /// the ordinary case, not the exotic one — extensions ship folders called
    /// `node_modules` and files called `my style.css`, and a user's project
    /// lives under a home directory whose name we do not choose.
    @Test(
        "a path needing percent-encoding survives the round trip",
        arguments: ["media/my style.css", "media/a#b.css", "media/100%.css", "média/ü.css"]
    )
    func awkwardPathsRoundTrip(_ relative: String) throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(relative)

        let webviewURL = WebviewResourceURL.url(forFile: file, panelID: panel)
        let target = try WebviewResourceURL.target(
            of: webviewURL, panelID: panel, localResourceRoots: [root])

        #expect(target == .file(file.resolvingSymlinksInPath().standardizedFileURL))
    }

    // MARK: - The host document

    /// The page itself is not a file. `webview.html` is a string the extension
    /// assigns, so the document is served from memory — but it still needs a
    /// real URL, because a document loaded without one gets an opaque origin
    /// and loses both storage and any hope of a coherent CSP.
    @Test("the panel's own URL names the host document, not a file")
    func hostDocumentIsDistinctFromAFile() throws {
        let url = WebviewResourceURL.hostDocumentURL(panelID: panel)
        let target = try WebviewResourceURL.target(
            of: url, panelID: panel, localResourceRoots: [])
        #expect(target == .hostDocument)
    }

    /// The host document is reachable with no roots configured at all — it is
    /// the extension's own markup, not a file the roots gate.
    @Test("the host document does not depend on localResourceRoots")
    func hostDocumentNeedsNoRoots() throws {
        let url = WebviewResourceURL.hostDocumentURL(panelID: panel)
        #expect(try WebviewResourceURL.target(
            of: url, panelID: panel, localResourceRoots: []) == .hostDocument)
    }

    // MARK: - Refusals

    /// The default posture. An extension that declares no roots has asked for
    /// no file access, and gets none.
    @Test("with no roots declared, every file is refused")
    func noRootsRefusesEveryFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = WebviewResourceURL.url(
            forFile: root.appendingPathComponent("style.css"), panelID: panel)

        #expect(throws: WebviewResourceURLError.self) {
            try WebviewResourceURL.target(of: url, panelID: panel, localResourceRoots: [])
        }
    }

    @Test("a file outside every declared root is refused")
    func outsideEveryRootIsRefused() throws {
        let root = try makeTemporaryDirectory("allowed")
        let elsewhere = try makeTemporaryDirectory("elsewhere")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: elsewhere)
        }
        let url = WebviewResourceURL.url(
            forFile: elsewhere.appendingPathComponent("secrets.txt"), panelID: panel)

        #expect(throws: WebviewResourceURLError.self) {
            try WebviewResourceURL.target(of: url, panelID: panel, localResourceRoots: [root])
        }
    }

    /// An extension may declare several roots — typically its own folder plus
    /// a workspace subfolder — and a file inside any one of them is allowed.
    @Test("a file inside the second of several roots is allowed")
    func anyDeclaredRootAllows() throws {
        let first = try makeTemporaryDirectory("first")
        let second = try makeTemporaryDirectory("second")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let file = second.appendingPathComponent("media/style.css")
        let url = WebviewResourceURL.url(forFile: file, panelID: panel)

        let target = try WebviewResourceURL.target(
            of: url, panelID: panel, localResourceRoots: [first, second])
        #expect(target == .file(file.resolvingSymlinksInPath().standardizedFileURL))
    }

    /// The traversal the page writes by hand rather than through
    /// `asWebviewUri`. The handler is given a URL, not a promise about how it
    /// was built, so it must re-derive containment from the URL alone.
    @Test("a ../ traversal out of the root is refused")
    func traversalOutOfTheRootIsRefused() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let escaping = root.appendingPathComponent("../../../etc/passwd")
        let url = WebviewResourceURL.url(forFile: escaping, panelID: panel)

        #expect(throws: WebviewResourceURLError.self) {
            try WebviewResourceURL.target(of: url, panelID: panel, localResourceRoots: [root])
        }
    }

    /// The attack a string-prefix containment check misses: a sibling whose
    /// name *starts with* the root's name. `ExtensionResourcePath` compares
    /// path components for exactly this reason, and this proves the webview
    /// path inherits that rather than re-deriving a weaker check.
    @Test("a sibling directory sharing the root's name prefix is refused")
    func siblingNamePrefixIsRefused() throws {
        let parent = try makeTemporaryDirectory("parent")
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("ext", isDirectory: true)
        let sibling = parent.appendingPathComponent("ext-evil", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)

        let url = WebviewResourceURL.url(
            forFile: sibling.appendingPathComponent("payload.js"), panelID: panel)

        #expect(throws: WebviewResourceURLError.self) {
            try WebviewResourceURL.target(of: url, panelID: panel, localResourceRoots: [root])
        }
    }

    /// The root itself is a directory, not a resource. Serving it would mean
    /// answering a request with a directory listing of the extension's folder.
    @Test("the root directory itself is not a servable file")
    func theRootItselfIsRefused() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = WebviewResourceURL.url(forFile: root, panelID: panel)

        #expect(throws: WebviewResourceURLError.self) {
            try WebviewResourceURL.target(of: url, panelID: panel, localResourceRoots: [root])
        }
    }

    /// One panel must not be able to name another's resources. The panel id is
    /// the URL's authority, which is what makes two panels two origins as far
    /// as WebKit is concerned; the handler still checks it, because an origin
    /// boundary the server does not enforce is a convention, not a boundary.
    @Test("a URL naming a different panel is refused")
    func anotherPanelsURLIsRefused() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = WebviewResourceURL.url(
            forFile: root.appendingPathComponent("style.css"), panelID: "panel-2")

        #expect(throws: WebviewResourceURLError.self) {
            try WebviewResourceURL.target(of: url, panelID: panel, localResourceRoots: [root])
        }
    }

    @Test(
        "a URL in another scheme is refused",
        arguments: ["file:///etc/passwd", "https://example.com/x.js", "data:text/html,<b>x</b>"]
    )
    func anotherSchemeIsRefused(_ raw: String) throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try #require(URL(string: raw))

        #expect(throws: WebviewResourceURLError.self) {
            try WebviewResourceURL.target(of: url, panelID: panel, localResourceRoots: [root])
        }
    }

    // MARK: - The scheme name

    /// The scheme is a storage format: an extension that persists a resource
    /// URI through `setState` writes this string into the pane state database,
    /// and a restored panel hands it straight back. Renaming it orphans that
    /// state silently, which is why the name is asserted rather than merely
    /// spelled once in the implementation.
    ///
    /// It is named after the framework that owns it, not the product that
    /// ships it. The plan proposed `whippet-webview`, which was already stale
    /// when Stage 6 started — the app had been renamed twice by then — and a
    /// storage format that has to be renamed is a storage format that breaks.
    @Test("the scheme is named, stable, and registrable")
    func schemeIsStable() {
        #expect(WebviewResourceURL.scheme == "agentic-webview")

        // WebKit refuses to hand a custom handler any scheme it handles
        // itself, so a name that collides is a feature that silently never
        // loads a single resource.
        let reserved = ["http", "https", "file", "data", "blob", "about", "ws", "wss", "ftp", "javascript"]
        #expect(!reserved.contains(WebviewResourceURL.scheme))

        // RFC 3986: a scheme starts with a letter, then letters, digits, or
        // `+`, `-`, `.`.
        #expect(WebviewResourceURL.scheme.first?.isLetter == true)
        #expect(WebviewResourceURL.scheme.allSatisfy {
            $0.isLowercase || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "."
        })
    }
}
