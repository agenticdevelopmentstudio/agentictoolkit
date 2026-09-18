import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A panel that records instead of rendering.
///
/// A double rather than the real `WebviewPanelViewController` on purpose: what
/// these tests pin is the JavaScript/Swift boundary — what the adaptor reads
/// out of a call, what it writes into the panel, what it hands back — and a
/// real `WKWebView` would put a web content process and a navigation on the
/// other side of every assertion. `ExtensionWebviewPanel` exists to be this
/// seam; `WebviewPanelViewController` conforming to it is what makes the
/// double honest.
@MainActor
private final class TestWebviewPanel: ExtensionWebviewPanel {
    let panelID: String
    var panelTitle: String
    var html: String = ""
    var localResourceRoots: [URL]
    private(set) var state: String?

    var onDidReceiveMessage: ((Any) -> Void)?
    var onDidDispose: (() -> Void)?

    private(set) var postedMessages: [Any] = []
    private(set) var revealCalls: [Bool] = []
    private(set) var disposeCount = 0

    init(panelID: String = "panel-1", title: String = "", roots: [URL] = []) {
        self.panelID = panelID
        self.panelTitle = title
        self.localResourceRoots = roots
    }

    func post(message: Any) {
        postedMessages.append(message)
    }

    func reveal(preserveFocus: Bool) {
        revealCalls.append(preserveFocus)
    }

    func dispose() {
        guard disposeCount == 0 else { return }
        disposeCount += 1
        onDidDispose?()
    }
}

/// A presenter that hands back a `TestWebviewPanel` and keeps what it was
/// asked for — or hands back `nil`, which is the "no window open" state.
@MainActor
private final class TestWebviewPresenter: ExtensionWebviewPresenting {
    private(set) var requests: [ExtensionWebviewPanelRequest] = []
    private(set) var panels: [TestWebviewPanel] = []

    /// When false, `presentWebviewPanel` answers `nil`.
    var canPresent = true

    func presentWebviewPanel(
        _ request: ExtensionWebviewPanelRequest
    ) -> (any ExtensionWebviewPanel)? {
        requests.append(request)
        guard canPresent else { return nil }
        let panel = TestWebviewPanel(
            panelID: "panel-\(panels.count + 1)",
            title: request.title,
            roots: request.localResourceRoots)
        panels.append(panel)
        return panel
    }
}

@MainActor
private final class TestWorkspaceRoots: ExtensionWorkspaceRoots {
    var workspaceDisplayName: String?
    var workspaceRootURLs: [URL]

    init(_ roots: [URL]) {
        self.workspaceRootURLs = roots
    }
}

/// `vscode.window.createWebviewPanel` and the two objects it hands back, wired
/// onto a real `ExtensionHost` with a presenter double standing in for a pane
/// tree — the arrangement `MainThreadLanguageModelsTests` uses for its own
/// provider, for the same reason.
@MainActor
@Suite
struct MainThreadWebviewsTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("MainThreadWebviewsTests")
    }

    private func install(_ webviews: MainThreadWebviews, on host: ExtensionHost) throws {
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "createWebviewPanel",
            implementation: webviews.createWebviewPanel)
    }

    /// The whole arrangement in one call, because every test below needs all
    /// of it: a temporary extension directory, a presenter, a ledger, the
    /// adaptor, and a host running `source` with the member installed.
    ///
    /// The caller disposes the host; the directory is removed by the returned
    /// `cleanup`.
    private func makeFixture(
        source: String,
        extensionDirectory: URL,
        workspaceRoots: (any ExtensionWorkspaceRoots)? = nil
    ) throws -> (
        host: ExtensionHost,
        webviews: MainThreadWebviews,
        presenter: TestWebviewPresenter,
        ledger: NotImplementedLedger
    ) {
        let presenter = TestWebviewPresenter()
        let ledger = NotImplementedLedger()
        let webviews = MainThreadWebviews(
            presenter: presenter,
            notImplementedLedger: ledger,
            extensionIdentifier: "acme.alpha",
            extensionDirectory: extensionDirectory,
            workspaceRoots: workspaceRoots)
        let host = try makeHost(source: source, in: extensionDirectory, ledger: ledger)
        try install(webviews, on: host)
        return (host, webviews, presenter, ledger)
    }

    // MARK: - The call itself

    /// The three values an extension writes into the call reach the presenter
    /// unaltered. The first thing to break if argument order were read wrong,
    /// and the cheapest thing to be sure of before anything below.
    @Test
    func createWebviewPanelHandsTheViewTypeTitleAndPreserveFocusToThePresenter() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__panel = vscode.window.createWebviewPanel(
                    'markdown.preview', 'Preview', { preserveFocus: true });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let request = try #require(fixture.presenter.requests.first)
        #expect(fixture.presenter.requests.count == 1)
        #expect(request.viewType == "markdown.preview")
        #expect(request.title == "Preview")
        #expect(request.preserveFocus)
        #expect(request.extensionIdentifier == "acme.alpha")
    }

    /// `showOptions` is far more often a bare `ViewColumn` number than an
    /// object, and a number has no `preserveFocus` — so the absence has to
    /// read as `false` rather than as a parse failure that loses the call.
    @Test
    func createWebviewPanelWithAViewColumnNumberForShowOptionsStillCreatesThePanel() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__panel = vscode.window.createWebviewPanel('t', 'T', 1);
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let request = try #require(fixture.presenter.requests.first)
        #expect(request.preserveFocus == false)
    }

    /// A missing view type is a programming error in the extension, and a
    /// synchronous member's way of saying so is a throw the extension's own
    /// `try` can catch (`fail-fast`). Nothing must reach the presenter.
    @Test
    func createWebviewPanelWithoutAViewTypeStringThrowsAndPresentsNothing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                try {
                    vscode.window.createWebviewPanel(42, 'T', {});
                    globalThis.__outcome = 'returned';
                } catch (error) {
                    globalThis.__outcome = 'threw';
                }
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__outcome")?.toString() == "threw")
        #expect(fixture.presenter.requests.isEmpty)
    }

    /// Same rule, one argument along: a panel with no title would show a pane
    /// with no name, which is worse than a throw the author sees at once.
    @Test
    func createWebviewPanelWithoutATitleStringThrowsAndPresentsNothing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                try {
                    vscode.window.createWebviewPanel('t');
                    globalThis.__outcome = 'returned';
                } catch (error) {
                    globalThis.__outcome = 'threw';
                }
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__outcome")?.toString() == "threw")
        #expect(fixture.presenter.requests.isEmpty)
    }

    /// No project window open is a real state, not a malformed call — but it
    /// still cannot answer with a panel object, because every member on one
    /// would be a lie. The extension gets an exception naming the reason.
    @Test
    func createWebviewPanelWithNowhereToPutThePanelThrows() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = TestWebviewPresenter()
        presenter.canPresent = false
        let webviews = MainThreadWebviews(
            presenter: presenter,
            notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "acme.alpha",
            extensionDirectory: directory,
            workspaceRoots: nil)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                try {
                    vscode.window.createWebviewPanel('t', 'T', {});
                    globalThis.__outcome = 'returned';
                } catch (error) {
                    globalThis.__outcome = 'threw';
                }
            };
            """,
            in: directory)
        defer { host.dispose() }
        try install(webviews, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__outcome")?.toString() == "threw")
        #expect(presenter.requests.count == 1)
    }

    // MARK: - The resource roots

    /// Nothing declared takes upstream's default: the extension's own
    /// directory plus every open workspace folder. The presenter must be
    /// handed the *resolved* list — resolving it needs the extension's
    /// install path, which nothing downstream of here knows.
    @Test
    func createWebviewPanelWithNoDeclaredRootsResolvesToTheExtensionDirectoryAndWorkspace() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = URL(fileURLWithPath: "/tmp/mtw-workspace", isDirectory: true)
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.window.createWebviewPanel('t', 'T', {}, { enableScripts: true });
            };
            """,
            extensionDirectory: directory,
            workspaceRoots: TestWorkspaceRoots([workspace]))
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let request = try #require(fixture.presenter.requests.first)
        #expect(request.localResourceRoots.contains(directory))
        #expect(request.localResourceRoots.contains(workspace))
        #expect(request.options.enableScripts)
    }

    /// An explicitly empty `localResourceRoots` is a panel renouncing file
    /// access, and honouring it as written is the difference between a
    /// sandbox and a suggestion. The empty array must not fall through to the
    /// default the test above pins.
    @Test
    func createWebviewPanelWithAnEmptyLocalResourceRootsArrayGrantsNothing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = URL(fileURLWithPath: "/tmp/mtw-workspace", isDirectory: true)
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.window.createWebviewPanel(
                    't', 'T', {}, { localResourceRoots: [] });
            };
            """,
            extensionDirectory: directory,
            workspaceRoots: TestWorkspaceRoots([workspace]))
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let request = try #require(fixture.presenter.requests.first)
        #expect(request.localResourceRoots.isEmpty)
    }

    /// A declared list is used as declared — and the `Uri` objects in it have
    /// to survive the crossing, which is the half a plain array copy would
    /// silently get wrong.
    @Test
    func createWebviewPanelWithDeclaredRootsPassesThemThrough() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.window.createWebviewPanel('t', 'T', {}, {
                    localResourceRoots: [vscode.Uri.file('/tmp/mtw-media')]
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let request = try #require(fixture.presenter.requests.first)
        #expect(request.localResourceRoots.map(\.path) == ["/tmp/mtw-media"])
    }

    // MARK: - The panel object

    /// `panel.title = …` has to reach the panel — it is what the pane's tab
    /// shows — and reading it back has to answer the panel, not a copy the
    /// adaptor kept.
    @Test
    func panelTitleIsAnAccessorPairOverThePanel() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var panel = vscode.window.createWebviewPanel('t', 'First', {});
                globalThis.__before = panel.title;
                panel.title = 'Second';
                globalThis.__after = panel.title;
                globalThis.__viewType = panel.viewType;
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let context = try #require(fixture.host.javaScriptContext)
        let panel = try #require(fixture.presenter.panels.first)
        #expect(context.evaluateScript("globalThis.__before")?.toString() == "First")
        #expect(context.evaluateScript("globalThis.__after")?.toString() == "Second")
        #expect(context.evaluateScript("globalThis.__viewType")?.toString() == "t")
        #expect(panel.panelTitle == "Second")
    }

    /// `reveal(viewColumn, preserveFocus)` reads its *second* argument, and a
    /// caller that omits the column passes `undefined` in its place rather
    /// than shifting the list. Reading the first would make every reveal
    /// preserve focus or none of them.
    @Test
    func panelRevealPassesItsSecondArgumentAsPreserveFocus() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var panel = vscode.window.createWebviewPanel('t', 'T', {});
                panel.reveal(undefined, true);
                panel.reveal();
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let panel = try #require(fixture.presenter.panels.first)
        #expect(panel.revealCalls == [true, false])
    }

    /// `panel.dispose()` runs the panel's own teardown — the same path the
    /// user closing the pane takes — so there is one way a panel goes away.
    @Test
    func panelDisposeDisposesThePanel() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__panel = vscode.window.createWebviewPanel('t', 'T', {});
                globalThis.__panel.dispose();
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let panel = try #require(fixture.presenter.panels.first)
        #expect(panel.disposeCount == 1)
    }

    /// The extension's `onDidDispose` listener has to run when the panel goes
    /// — including when the *user* closed the pane, which is the case an
    /// adaptor that only fired from its own `dispose` member would miss.
    @Test
    func panelOnDidDisposeFiresWhenThePanelIsClosedFromOutsideJavaScript() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__disposed = 0;
                var panel = vscode.window.createWebviewPanel('t', 'T', {});
                panel.onDidDispose(function () { globalThis.__disposed += 1; });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let panel = try #require(fixture.presenter.panels.first)
        panel.dispose()

        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__disposed")?.toInt32() == 1)
    }

    // MARK: - The webview object

    /// The page's own CSP names where its resources come from, and a wrong
    /// `cspSource` blocks every one of them with a console message that
    /// blames the page. Scheme and authority, no trailing path.
    @Test
    func webviewCspSourceIsTheSchemeAndThePanelIdentifier() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var panel = vscode.window.createWebviewPanel('t', 'T', {});
                globalThis.__csp = panel.webview.cspSource;
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let context = try #require(fixture.host.javaScriptContext)
        let panel = try #require(fixture.presenter.panels.first)
        #expect(
            context.evaluateScript("globalThis.__csp")?.toString()
                == "\(WebviewResourceURL.scheme)://\(panel.panelID)")
    }

    /// `panel.webview.html = …` is how every webview extension puts its page
    /// on screen; it has to reach the panel through the freshly built wrapper
    /// rather than landing on a JavaScript object nobody reads.
    @Test
    func webviewHtmlAssignmentReachesThePanelThroughAFreshWrapper() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var panel = vscode.window.createWebviewPanel('t', 'T', {});
                panel.webview.html = '<h1>hi</h1>';
                globalThis.__readBack = panel.webview.html;
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let context = try #require(fixture.host.javaScriptContext)
        let panel = try #require(fixture.presenter.panels.first)
        #expect(panel.html == "<h1>hi</h1>")
        // Read back through a *second* wrapper — the getter builds one per
        // access — which is the point: the state lives on the panel, so two
        // wrappers answer the same thing.
        #expect(context.evaluateScript("globalThis.__readBack")?.toString() == "<h1>hi</h1>")
    }

    /// `asWebviewUri` is what an extension runs every file path through before
    /// putting it in its HTML. Naming a file is not permission to read it —
    /// the scheme handler decides that — so this maps unconditionally.
    @Test
    func webviewAsWebviewUriRewritesAFileUriIntoTheWebviewScheme() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var panel = vscode.window.createWebviewPanel('t', 'T', {});
                globalThis.__uri = panel.webview
                    .asWebviewUri(vscode.Uri.file('/tmp/mtw-media/app.css')).toString();
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let context = try #require(fixture.host.javaScriptContext)
        let panel = try #require(fixture.presenter.panels.first)
        let expected = WebviewResourceURL.url(
            forFile: URL(fileURLWithPath: "/tmp/mtw-media/app.css"), panelID: panel.panelID)
        #expect(context.evaluateScript("globalThis.__uri")?.toString() == expected.absoluteString)
    }

    /// `postMessage` is the extension half of the request/response every
    /// webview extension builds on. It delivers to the page and answers a
    /// promise resolving `true`.
    @Test
    func webviewPostMessageDeliversToThePanelAndResolvesTrue() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var panel = vscode.window.createWebviewPanel('t', 'T', {});
                panel.webview.postMessage({ kind: 'update' }).then(function (ok) {
                    globalThis.__posted = ok ? 'true' : 'false';
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let panel = try #require(fixture.presenter.panels.first)
        #expect(panel.postedMessages.count == 1)
        let message = try #require(panel.postedMessages.first as? [String: Any])
        #expect(message["kind"] as? String == "update")

        let context = try #require(fixture.host.javaScriptContext)
        let posted = try #require(await waitForGlobal(context, "globalThis.__posted"))
        #expect(posted.toString() == "true")
    }

    /// Posting to a panel that is gone resolves `false` rather than rejecting
    /// — upstream's own answer, and the one that does not turn a late reply
    /// into an unhandled rejection in an extension that never expected one.
    @Test
    func webviewPostMessageAfterDisposalResolvesFalse() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__webview = vscode.window
                    .createWebviewPanel('t', 'T', {}).webview;
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let panel = try #require(fixture.presenter.panels.first)
        panel.dispose()

        let context = try #require(fixture.host.javaScriptContext)
        context.evaluateScript("""
            globalThis.__webview.postMessage({}).then(function (ok) {
                globalThis.__posted = ok ? 'true' : 'false';
            });
            """)
        let posted = try #require(await waitForGlobal(context, "globalThis.__posted"))
        #expect(posted.toString() == "false")
        #expect(panel.postedMessages.isEmpty)
    }

    /// A message from the page reaches the extension **in the same turn** the
    /// page sent it. That synchrony is what `postMessage`-based request and
    /// response between an extension and its page assumes, and it is the whole
    /// reason `ExtensionEventImmediateWindow` exists rather than the timer
    /// window every other emitter uses.
    @Test
    func webviewOnDidReceiveMessageDeliversSynchronously() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__received = [];
                var panel = vscode.window.createWebviewPanel('t', 'T', {});
                panel.webview.onDidReceiveMessage(function (message) {
                    globalThis.__received.push(message.kind);
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let panel = try #require(fixture.presenter.panels.first)
        panel.onDidReceiveMessage?(["kind": "ready"])

        // No polling: an `await` here would hide exactly the defect this test
        // is for.
        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__received.join(',')")?.toString() == "ready")
    }

    /// A listener registered before disposal must not run afterwards — the
    /// registry entry going away is what makes every block on the panel's
    /// JavaScript surface inert, and this is the observable consequence.
    @Test
    func webviewOnDidReceiveMessageIsSilentAfterDisposal() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__received = 0;
                var panel = vscode.window.createWebviewPanel('t', 'T', {});
                panel.webview.onDidReceiveMessage(function () { globalThis.__received += 1; });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let panel = try #require(fixture.presenter.panels.first)
        let deliver = try #require(panel.onDidReceiveMessage)
        deliver(["kind": "first"])
        panel.dispose()
        deliver(["kind": "second"])

        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__received")?.toInt32() == 1)
    }

    // MARK: - The ledger

    /// Three shapes this host takes only part of, each recorded so the
    /// extension report can name what an extension is quietly missing —
    /// `vscode.StatusBarItem.tooltip: MarkdownString`'s precedent.
    @Test
    func optionsAndMembersThisHostDoesNotHonourAreRecordedInTheLedger() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var panel = vscode.window.createWebviewPanel('t', 'T', {}, {
                    enableCommandUris: true,
                    portMapping: [{ webviewPort: 3000, extensionHostPort: 3000 }]
                });
                panel.iconPath = vscode.Uri.file('/tmp/mtw-icon.png');
                panel.onDidChangeViewState(function () {});
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let paths = Set(fixture.ledger.accesses(for: "acme.alpha").map(\.memberPath))
        #expect(paths.contains("vscode.WebviewOptions.enableCommandUris"))
        #expect(paths.contains("vscode.WebviewOptions.portMapping"))
        #expect(paths.contains("vscode.WebviewPanel.iconPath"))
        #expect(paths.contains("vscode.WebviewPanel.onDidChangeViewState"))
    }

    /// An option the extension explicitly declined is not a reach for
    /// something missing. Recording it would tell a user their extension wants
    /// a capability it went out of its way to turn off.
    @Test
    func anExplicitlyFalseEnableCommandUrisRecordsNothing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.window.createWebviewPanel('t', 'T', {}, {
                    enableCommandUris: false, portMapping: []
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        #expect(fixture.ledger.accesses(for: "acme.alpha").isEmpty)
    }

    // MARK: - Teardown

    /// A webview holds a whole web content process, so an extension's panels
    /// cannot outlive its host by waiting for the last reference to drop.
    @Test
    func disposingTheAdaptorDisposesEveryLivePanel() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.window.createWebviewPanel('a', 'A', {});
                vscode.window.createWebviewPanel('b', 'B', {});
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()
        #expect(fixture.presenter.panels.count == 2)

        fixture.webviews.dispose()

        #expect(fixture.presenter.panels.allSatisfy { $0.disposeCount == 1 })
    }

    /// After teardown the member raises rather than presenting a panel into a
    /// host that is gone — `.raisedException`, because `createWebviewPanel`
    /// is synchronous and a rejected promise would be a thenable nothing
    /// awaits.
    @Test
    func createWebviewPanelAfterDisposalThrowsAndPresentsNothing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__create = function () {
                    try {
                        vscode.window.createWebviewPanel('t', 'T', {});
                        return 'returned';
                    } catch (error) {
                        return 'threw';
                    }
                };
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        fixture.webviews.dispose()

        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__create()")?.toString() == "threw")
        #expect(fixture.presenter.requests.isEmpty)
    }

    // MARK: - Helpers

    /// Polls until `expression` is neither `null` nor `undefined`, for the
    /// promise-settling assertions above — a `.then()` reaction is a
    /// microtask, never invoked synchronously however settled the promise
    /// already is. The same helper `MainThreadLanguageModelsTests` carries.
    private func waitForGlobal(_ context: JSContext, _ expression: String) async throws -> JSValue? {
        for _ in 0..<200 {
            if let value = context.evaluateScript(expression), !value.isNull, !value.isUndefined {
                return value
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }
}
