//
//  WebviewPanelViewController.swift
//  AgenticToolkit
//

import AppKit
import Foundation
import os
import WebKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// What an extension asked for when it called `createWebviewPanel`, and what
/// the pane shows.
///
/// One class rather than a panel model plus a view controller: the panel *is*
/// the pane's content, its title *is* the pane's title, and disposing it *is*
/// closing the pane. Splitting them would mean two objects with one lifetime
/// and a protocol between them that nothing else would ever implement
/// (`design-for-deletion`).
///
/// The extension never touches this. `MainThreadWindow` hands JavaScript an
/// object of `@convention(block)` properties that capture it weakly, the same
/// shape every other `vscode` object uses.
@MainActor
public final class WebviewPanelViewController: NSViewController {

    /// This panel's origin. A UUID rather than the view type, because two
    /// panels of the same view type must not share a WebKit origin — which is
    /// to say must not share `localStorage`, or the ability to read each
    /// other's DOM through a handle they were never given.
    public let panelID: String

    /// The view type it was created under, and the key its serializer is
    /// registered against.
    public let viewType: String

    /// What the pane's chrome calls it. Assigning re-titles the pane.
    ///
    /// `NSViewController`'s own property rather than one beside it: pane chrome
    /// already knows to ask a view controller its title, and a second title
    /// would be a second answer to the same question (`dry`).
    public override var title: String? {
        didSet {
            guard title != oldValue else { return }
            onTitleChanged?()
            onRestorationStateChanged?()
        }
    }

    /// `webview.html`. Assigning reloads the page, which is what VS Code does
    /// and what extensions rely on to re-render.
    public var html: String {
        didSet {
            guard html != oldValue else { return }
            loadHostDocument()
        }
    }

    /// The directories this panel may read files from.
    ///
    /// Read through to the scheme handler rather than copied into it, so a
    /// narrowing takes effect for requests already in flight (`fail-fast`).
    public var localResourceRoots: [URL] {
        get { schemeHandler.localResourceRoots }
        set { schemeHandler.localResourceRoots = newValue }
    }

    /// The JSON text the page last passed to `setState`, or `nil` if it never
    /// did. Carried as text — see `WebviewPanelState.state`.
    public private(set) var state: String?

    /// Called when the page calls `vscode.postMessage(...)`. The value is
    /// whatever the page passed, already bridged out of JavaScript.
    public var onDidReceiveMessage: ((Any) -> Void)?

    /// Called when the panel is disposed — by the extension, or by the pane
    /// being closed. Fires exactly once.
    public var onDidDispose: (() -> Void)?

    /// Called when `title` changes — the pane chrome's callback, claimed by
    /// `PaneViewController.wireContentCallbacks()` through
    /// `PaneTitleProviding.onPaneTitleChange`.
    public var onTitleChanged: (() -> Void)?

    /// Called whenever `restorationState` would answer differently — a retitle
    /// or a `setState` — for whoever has to write it down.
    ///
    /// A **second** callback rather than a second listener on
    /// `onTitleChanged`, because that one is already spoken for: the pane
    /// claims it the moment this panel becomes its content, and it does so in
    /// `viewDidLoad`, which runs *after* the factory that built this panel
    /// returned. Anything the factory installed there would be silently
    /// overwritten a moment later — so the serializer gets a callback of its
    /// own, and the two owners never contend (`explicit-over-implicit`).
    public var onRestorationStateChanged: (() -> Void)?

    /// Called when the extension asks for the panel to be brought forward, with
    /// `preserveFocus`.
    ///
    /// A closure installed by whoever put the panel on screen, rather than
    /// something this class does for itself: revealing means finding this
    /// panel's pane in a window's tree and selecting it, and the panel does not
    /// know which tree it was put in — only the presenter that put it there
    /// does. A second handle object to carry one verb would be a type with one
    /// implementation (`design-for-deletion`).
    public var onRevealRequested: ((Bool) -> Void)?

    /// Called once, from `dispose()`, when the panel's pane should be taken
    /// out of the window's tree.
    ///
    /// Installed by whoever placed the panel, for `onRevealRequested`'s reason:
    /// this class does not know which tree it is in. It is deliberately a
    /// *second* closure rather than a second listener on `onDidDispose` —
    /// that one belongs to the extension host, which forwards it to the
    /// extension's own `onDidDispose`, and one stored closure cannot have two
    /// owners.
    ///
    /// **It fires on the user's path too.** Closing the pane runs
    /// `paneContentWillBeDiscarded()`, which disposes, which lands here — so
    /// the closure must tolerate being asked to remove a pane that is already
    /// on its way out.
    public var onRemovalRequested: (() -> Void)?

    public private(set) var isDisposed = false

    private let schemeHandler: WebviewSchemeHandler
    private let relay = WebviewMessageRelay()
    private var webView: WKWebView?

    /// What the panel was created with. Held whole rather than unpicked into
    /// stored properties: `loadView()` is where most of it is read, and that
    /// runs long after this initialiser (`dry`).
    private let options: WebviewPanelOptions

    /// - Parameters:
    ///   - viewType: The type this panel was created under.
    ///   - title: What the pane's chrome calls it to begin with.
    ///   - options: What the extension asked for.
    ///   - localResourceRoots: The directories this panel may read, already
    ///     resolved. `WebviewPanelOptions.resourceRoots(extensionDirectory:workspaceRoots:)`
    ///     is what resolves them, and it needs to know where the extension is
    ///     installed — which a view controller has no business knowing.
    public init(
        viewType: String,
        title: String,
        options: WebviewPanelOptions,
        localResourceRoots: [URL]
    ) {
        let panelID = UUID().uuidString
        self.panelID = panelID
        self.viewType = viewType
        self.html = ""
        self.options = options
        self.schemeHandler = WebviewSchemeHandler(panelID: panelID)
        super.init(nibName: nil, bundle: nil)
        self.title = title
        schemeHandler.localResourceRoots = localResourceRoots
        schemeHandler.contentSecurityPolicy = options.contentSecurityPolicy
        relay.delegate = self
    }

    /// The panel a persisted pane comes back as, before its extension has seen
    /// it.
    ///
    /// The page's own `getState()` has to answer what the page last saved from
    /// the very first document load — that is the contract a webview author
    /// writes against — so the state is seeded here rather than assigned after
    /// the view exists. `loadView()` has not run at this point; by the time it
    /// does, `loadHostDocument()` reads this value as the document's
    /// `initialState`.
    ///
    /// - Parameters:
    ///   - state: What the pane stored, as `restorationState` wrote it.
    ///   - localResourceRoots: Resolved for the extension that claimed this
    ///     view type, exactly as at creation.
    public convenience init(restoring state: WebviewPanelState, localResourceRoots: [URL]) {
        self.init(
            viewType: state.viewType,
            title: state.title,
            options: state.options,
            localResourceRoots: localResourceRoots)
        self.state = state.state
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - The web view

    public override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: WebviewResourceURL.scheme)
        configuration.userContentController.add(
            relay, name: WebviewHostDocument.messageHandlerName)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = options.enableScripts
        // Nothing a panel stores in `localStorage` survives a quit, on purpose:
        // `setState` is the documented way for a webview to persist, it is the
        // one this app actually restores from, and a second persistence
        // mechanism that silently half-works is worse than none.
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 320), configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.observeTheme { view, palette in
            view.underPageBackgroundColor = palette.nsColor(.surface)
        }
        self.webView = webView
        view = webView
        loadHostDocument()
    }

    private func loadHostDocument() {
        guard let webView, !isDisposed else { return }
        schemeHandler.hostDocument = WebviewHostDocument.html(
            wrapping: html, initialState: state)
        webView.load(URLRequest(url: WebviewResourceURL.hostDocumentURL(panelID: panelID)))
    }

    // MARK: - Talking to the page

    /// Delivers `webview.postMessage(...)` to the page as a `message` event,
    /// which is where VS Code webviews listen.
    ///
    /// `callAsyncJavaScript` passes the value as a real argument rather than
    /// interpolating it into a script string, so there is no second escaper
    /// here to keep in step with `WebviewHostDocument`'s — and nothing an
    /// extension can put in a message that changes the shape of the script.
    public func post(message: Any) {
        guard let webView, !isDisposed else { return }
        webView.callAsyncJavaScript(
            "window.dispatchEvent(new MessageEvent('message', { data: payload }));",
            arguments: ["payload": message],
            in: nil,
            in: .page,
            completionHandler: nil)
    }

    // MARK: - Teardown

    /// Releases the page and tells whoever was waiting. Safe to call twice —
    /// the extension disposing a panel the user already closed is the ordinary
    /// race, not an error (`idempotency`).
    public func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: WebviewHostDocument.messageHandlerName)
        webView?.loadHTMLString("", baseURL: nil)
        onDidDispose?()
        onRemovalRequested?()
    }

    /// What the pane stores, and what `WebviewPanelSerializer` reads back.
    public var restorationState: WebviewPanelState {
        WebviewPanelState(viewType: viewType, title: title ?? "", state: state, options: options)
    }
}

// MARK: - The page's messages

extension WebviewPanelViewController: WebviewMessageReceiving {

    func webviewDidSend(kind: WebviewHostDocument.MessageKind, body: Any) {
        guard !isDisposed else { return }
        switch kind {
        case .postMessage:
            onDidReceiveMessage?(body)

        case .setState:
            state = Self.jsonText(of: body)
            onRestorationStateChanged?()
        }
    }

    /// The page's state as the text `WebviewPanelState` carries.
    ///
    /// `.fragmentsAllowed` because `setState(42)` and `setState(null)` are both
    /// things a page may do, and refusing them would lose a panel's state to a
    /// shape the API permits.
    private static func jsonText(of body: Any) -> String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: body, options: [.fragmentsAllowed, .sortedKeys]),
              let text = String(bytes: data, encoding: .utf8)
        else {
            Self.logger.error("A webview's setState value was not JSON; dropping it")
            return nil
        }
        return text
    }
}

// MARK: - Navigation

extension WebviewPanelViewController: WKNavigationDelegate {

    /// A panel may load its own document and nothing else.
    ///
    /// A link to `https://…` is not blocked but *redirected* — out of the
    /// webview and into the user's browser, which is both what VS Code does
    /// and the only reading of a click on a link that a user would recognise.
    /// Letting it navigate in place would replace the extension's page with a
    /// web page holding the panel's origin, which is a far larger thing than a
    /// broken link.
    public func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if url.scheme == WebviewResourceURL.scheme { return .allow }
        if navigationAction.navigationType == .linkActivated,
           let scheme = url.scheme, scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }
}

// MARK: - Being a panel an extension holds

extension WebviewPanelViewController: ExtensionWebviewPanel {

    /// `NSViewController.title` is `String?`, which no protocol requirement
    /// spelled `title: String` can be satisfied by — so the protocol asks for
    /// this name instead, and it reads and writes the same storage. The empty
    /// string stands in for `nil`, which this class never has once its
    /// initialiser has run.
    public var panelTitle: String {
        get { title ?? "" }
        set { title = newValue }
    }

    /// Asks whoever put this panel on screen to bring it forward. A panel with
    /// nobody listening — one whose presenter is gone — silently does nothing,
    /// which is what VS Code does for a panel in a closed window group too.
    public func reveal(preserveFocus: Bool) {
        guard !isDisposed else { return }
        onRevealRequested?(preserveFocus)
    }
}

// MARK: - Being a pane

extension WebviewPanelViewController: PaneTitleProviding {

    public var paneTitle: String { title ?? viewType }

    /// The same storage `onTitleChanged` writes through, on purpose: a panel
    /// has one title and one moment at which it changes, so there is one
    /// callback.
    ///
    /// `PaneViewController.wireContentCallbacks()` claims this the moment the
    /// panel becomes a pane's content — in `viewDidLoad`, after the factory
    /// that built the panel has returned. Anything else that wants to hear
    /// about a retitle listens to `onRestorationStateChanged` instead; that is
    /// what it is for, and it is why the serializer does not have to chain
    /// onto this the way `DocumentTabsViewController.wireTitles(in:tabID:)`
    /// does. Overwriting this one silently stops the pane's title bar from
    /// updating.
    public var onPaneTitleChange: (() -> Void)? {
        get { onTitleChanged }
        set { onTitleChanged = newValue }
    }
}

extension WebviewPanelViewController: PaneContentTeardown {

    /// Closing the pane disposes the panel, which is what fires
    /// `onDidDispose` and so what tells the extension its panel is gone. A
    /// webview holds a whole web content process, so waiting for the last
    /// reference to drop is not good enough.
    public func paneContentWillBeDiscarded() {
        dispose()
    }
}

extension WebviewPanelViewController: Loggable {
    public static nonisolated let logger = makeLogger()
}

// MARK: - The bridge

/// What a `WebviewMessageRelay` hands its panel.
@MainActor
protocol WebviewMessageReceiving: AnyObject {
    func webviewDidSend(kind: WebviewHostDocument.MessageKind, body: Any)
}

/// Stands between `WKUserContentController` and the panel, holding the panel
/// weakly.
///
/// Not a convenience: the controller retains its message handlers, the
/// configuration retains the controller, the web view retains the
/// configuration, and the panel retains the web view. A panel registered as
/// its own handler is a panel that never deallocates — and a webview panel
/// that outlives its pane keeps a whole web content process with it.
private final class WebviewMessageRelay: NSObject, WKScriptMessageHandler {

    weak var delegate: (any WebviewMessageReceiving)?

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        MainActor.assumeIsolated {
            guard let payload = message.body as? [String: Any],
                  let rawKind = payload["kind"] as? String,
                  let kind = WebviewHostDocument.MessageKind(rawValue: rawKind)
            else {
                // Only the bootstrap this app injects posts to this handler, so
                // anything else is a page that found the handler and made up a
                // message. Dropped rather than decoded leniently.
                return
            }
            delegate?.webviewDidSend(kind: kind, body: payload["body"] ?? NSNull())
        }
    }
}
