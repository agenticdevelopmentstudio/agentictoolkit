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

    /// How much time has to pass between one external open and the next.
    ///
    /// Settable so a test can say "and again" without spending the interval;
    /// production never changes it.
    var externalOpenInterval: TimeInterval = 0.5

    /// Hands a link to the user's browser. Injected so a test can watch the
    /// rate without the machine acquiring fifty browser windows.
    var openExternalURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// When the last link was handed over, on the monotonic clock.
    private var lastExternalOpen: TimeInterval = -.greatestFiniteMagnitude

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
    ///
    /// **A reveal that arrives before this is installed is kept, not lost.**
    /// The restoration path builds the panel by handing the stored state to
    /// the extension's own `deserializeWebviewPanel`, and that call is where
    /// an extension does its setting up — including `panel.reveal()`. It runs
    /// to completion *before* the serializer has anything to install the verbs
    /// on, because the panel it installs them on is the one that call returns.
    /// See `deferredReveal`.
    public var onRevealRequested: ((Bool) -> Void)? {
        didSet {
            guard let onRevealRequested else { return }
            hasBeenPlaced = true
            guard let preserveFocus = deferredReveal else { return }
            deferredReveal = nil
            onRevealRequested(preserveFocus)
        }
    }

    /// A `reveal` made before anything was listening, with the
    /// `preserveFocus` it was made with, replayed by the first installation.
    ///
    /// Only ever filled *before* a first installation — see `hasBeenPlaced`.
    /// A panel whose presenter has since gone away still reveals into silence,
    /// which is what VS Code does for a panel in a closed window group and is
    /// the behaviour this deliberately does not change.
    private var deferredReveal: Bool?

    /// Whether the placement verbs have ever been installed.
    ///
    /// The whole distinction between "not wired up yet" and "not wired up any
    /// more". The first is a message owed; the second is a panel nobody is
    /// showing, and replaying into it would reveal or close a pane on the
    /// strength of something an extension asked for before the pane existed.
    private var hasBeenPlaced = false

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
    ///
    /// **A dispose that arrives before this is installed is kept**, for
    /// `onRevealRequested`'s reason and with the same one-shot rule: an
    /// extension's `deserializeWebviewPanel` may decide, on reading the state
    /// it is given, that the panel refers to nothing any more and dispose it
    /// on the spot. Dropped, that left a pane on screen holding a disposed
    /// panel — inert, unremovable, and written straight back into the
    /// project's pane state to be rebuilt tomorrow.
    public var onRemovalRequested: (() -> Void)? {
        didSet {
            guard let onRemovalRequested else { return }
            hasBeenPlaced = true
            guard deferredRemoval else { return }
            deferredRemoval = false
            onRemovalRequested()
        }
    }

    /// Whether `dispose()` ran with nobody listening for the removal, and
    /// before anybody ever had been. See `deferredReveal`.
    private var deferredRemoval = false

    public private(set) var isDisposed = false

    private let schemeHandler: WebviewSchemeHandler
    private let relay = WebviewMessageRelay()
    private var webView: WKWebView?

    /// What the panel is under now. Held whole rather than unpicked into
    /// stored properties: `loadView()` is where most of it is read, and that
    /// runs long after this initialiser (`dry`).
    ///
    /// Assignable, because `webview.options = …` is — see
    /// `ExtensionWebviewPanel.options`. Two of the three effects the
    /// initialiser applies have to be re-applied here, and they are not the
    /// same kind of thing. The content security policy is the scheme handler's,
    /// and it serves the *next* request, so assigning it is enough. Scripts are
    /// decided per navigation, by `navigationPreferences(basedOn:)` — so the
    /// page is reloaded, which is what makes the new answer take effect and is
    /// also what upstream does for the same reason (`mainThreadWebviews.ts`
    /// reloads a webview whose options changed). Reloading is free before
    /// `loadView()` has run, which is the case a view provider is in.
    ///
    /// This used to write `webView.configuration.defaultWebpagePreferences`
    /// here instead. `WKWebView.configuration` is `@NSCopying` — the getter
    /// hands back a copy — so the write landed on a throwaway and WebKit was
    /// never told. Taking scripts away from a running panel therefore did
    /// nothing at all, which is the fail-open direction.
    ///
    /// The third effect — the roots — is deliberately *not* here:
    /// `declaredLocalResourceRoots` is what the extension wrote and
    /// `localResourceRoots` is where that resolves to, and resolving needs the
    /// extension's install directory, which a view controller has no business
    /// knowing. `MainThreadWebviews` sets both, in that order.
    public var options: WebviewPanelOptions {
        didSet {
            guard options != oldValue else { return }
            schemeHandler.contentSecurityPolicy = options.contentSecurityPolicy
            // `restorationState` carries the options, so a write here is a
            // write to what the pane stores — and it was the one change to
            // that value nothing announced. The direction it failed in is the
            // wrong one: an extension that *tightens* its options (revokes
            // `enableScripts`, narrows `localResourceRoots`) had the tightening
            // apply to the running page and then vanish at quit, so the panel
            // came back tomorrow under the looser options it was created with.
            onRestorationStateChanged?()
            guard webView != nil, !isDisposed else { return }
            loadHostDocument()
        }
    }

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
        // The floor, not the mechanism: this configuration is the real one
        // (it has not been through `WKWebView.configuration`'s copying getter
        // yet), so it is what a navigation the delegate never sees would get.
        // `navigationPreferences(basedOn:)` is what answers for the
        // navigations that do reach the delegate, which is all of them while
        // `navigationDelegate` is set. Keeping both means the unasked case
        // fails closed rather than inheriting WebKit's default of "allowed".
        configuration.defaultWebpagePreferences.allowsContentJavaScript = options.enableScripts
        // Nothing a panel stores in `localStorage` survives a quit, on purpose:
        // `setState` is the documented way for a webview to persist, it is the
        // one this app actually restores from, and a second persistence
        // mechanism that silently half-works is worse than none.
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 320), configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.keepPaintingUnderQuietPresentation()
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
    /// which is where VS Code webviews listen. Answers whether it went.
    ///
    /// `callAsyncJavaScript` passes the value as a real argument rather than
    /// interpolating it into a script string, so there is no second escaper
    /// here to keep in step with `WebviewHostDocument`'s — and nothing an
    /// extension can put in a message that changes the shape of the script.
    ///
    /// **It does insist on the types it accepts, and not politely.** A value
    /// outside them raises `NSInvalidArgumentException`, which is an
    /// Objective-C exception: `try?` does not catch it and the app goes down.
    /// The argument here is `JSValue.toObject()` of whatever the extension
    /// passed, so nothing exotic is needed to get there — a `vscode.Uri`
    /// bridges to an `NSURL`, and an `NSURL` is not on the list. `isPostable`
    /// is the check that turns that crash into a dropped message and a `false`,
    /// which is what upstream's own `postMessage` answers when the message does
    /// not arrive *(fail-fast, at the boundary that knows the rule)*.
    @discardableResult
    public func post(message: Any) -> Bool {
        guard Self.isPostable(message) else {
            Self.logger.error(
                "A webview message held a value WebKit cannot pass to a page; dropping it")
            return false
        }
        guard let webView, !isDisposed else { return false }
        webView.callAsyncJavaScript(
            "window.dispatchEvent(new MessageEvent('message', { data: payload }));",
            arguments: ["payload": message],
            in: nil,
            in: .page,
            completionHandler: nil)
        return true
    }

    /// `true` when `callAsyncJavaScript` will take `value` as an argument.
    ///
    /// The accepted set is `NSNumber`, `NSNull`, `NSString`, `NSDate`,
    /// `NSArray` and `NSDictionary`, recursively, with string keys — WebKit's
    /// documented list, restated because the framework offers no way to ask.
    ///
    /// **Deliberately not `JSONSerialization.isValidJSONObject`**, which is the
    /// near-miss: the two sets are different in both directions. JSON refuses a
    /// `Date` and a non-finite number, both of which WebKit passes happily and
    /// a page may legitimately be sent — so borrowing the JSON rule would drop
    /// `{ openedAt: new Date() }` to prevent a crash it never causes. That the
    /// same file *does* use the JSON rule a few lines down, for `setState`, is
    /// not an inconsistency: that value is going to storage as text, and this
    /// one is going to a JavaScript engine.
    nonisolated static func isPostable(_ value: Any) -> Bool {
        switch value {
        case is NSNull, is NSNumber, is NSString, is NSDate:
            return true
        case let dictionary as NSDictionary:
            // Before `NSArray`, because the key rule is the one a check of the
            // values alone never sees and JavaScript has no object to turn a
            // non-string key into.
            return dictionary.allSatisfy { key, element in
                key is NSString && isPostable(element)
            }
        case let array as NSArray:
            return array.allSatisfy { isPostable($0) }
        default:
            return false
        }
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
        guard let onRemovalRequested else {
            deferredRemoval = !hasBeenPlaced
            return
        }
        onRemovalRequested()
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
            // A value this host cannot encode is a *message* dropped, never a
            // state erased. Assigning the failure would throw away whatever the
            // page last saved successfully, and the announcement immediately
            // after would write that erasure into the project — so a panel that
            // had a scroll position an hour ago comes back blank because of one
            // message that never stored anything.
            guard let text = Self.jsonText(of: body) else { return }
            state = text
            onRestorationStateChanged?()
        }
    }

    /// The page's state as the text `WebviewPanelState` carries, or `nil` for
    /// a value this host cannot encode.
    ///
    /// `.fragmentsAllowed` because `setState(42)` and `setState(null)` are both
    /// things a page may do, and refusing them would lose a panel's state to a
    /// shape the API permits.
    ///
    /// The validity check ahead of the encode is not belt and braces:
    /// `data(withJSONObject:)` does not *throw* on a value it cannot encode, it
    /// raises an Objective-C exception, which `try?` does not catch and which
    /// takes the whole app down with it. A page needs nothing exotic to get
    /// there — WebKit hands a JavaScript `Date` over as an `NSDate`, and `NaN`
    /// and `Infinity` are as unencodable as that — so `setState(new Date())`
    /// from any extension's page was a crash.
    ///
    /// Wrapped in an array because the two rules disagree at exactly one point:
    /// `isValidJSONObject` refuses a bare number, string or null at the top
    /// level, which is the whole of what `.fragmentsAllowed` exists to permit.
    /// Validating the value as an array's element is that same recursive check
    /// without the top-level rule.
    private static func jsonText(of body: Any) -> String? {
        guard JSONSerialization.isValidJSONObject([body]),
              let data = try? JSONSerialization.data(
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

    /// Answers both questions WebKit asks before a navigation: whether it
    /// may happen at all, and what the page is allowed to do if it does.
    ///
    /// The two are one delegate method because WebKit picks **one** of the
    /// `decidePolicyFor` overloads — implementing this one means the shorter
    /// one is never called, so the URL rules have to live here or stop running.
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        (policy(for: navigationAction), navigationPreferences(basedOn: preferences))
    }

    /// Whether the page about to load may run JavaScript.
    ///
    /// **Per navigation, and read straight off `options` each time.** That is
    /// the whole reason this is a function rather than a value computed at
    /// construction: `webview.options = { enableScripts: false }` is a thing an
    /// extension may do at any moment, and the reload that follows it has to
    /// get the new answer.
    ///
    /// `enableScripts` is the one option here that is a security boundary and
    /// not a preference — a page that runs scripts can reach the host over the
    /// message handler — so it is off unless the extension asked for it, which
    /// `WebviewPanelOptions` decides.
    func navigationPreferences(
        basedOn preferences: WKWebpagePreferences = WKWebpagePreferences()
    ) -> WKWebpagePreferences {
        preferences.allowsContentJavaScript = options.enableScripts
        return preferences
    }

    /// A panel may load its own document and nothing else.
    ///
    /// A link to `https://…` is not blocked but *redirected* — out of the
    /// webview and into the user's browser, which is both what VS Code does
    /// and the only reading of a click on a link that a user would recognise.
    /// Letting it navigate in place would replace the extension's page with a
    /// web page holding the panel's origin, which is a far larger thing than a
    /// broken link.
    ///
    /// **`.linkActivated` is not a promise that a user clicked anything.**
    /// WebKit reports it for `anchor.click()` from script exactly as it does
    /// for a real click, and there is no public flag that separates the two —
    /// so a loop in a page was a loop of browser windows, with no prompt, no
    /// permission and nothing the user could do but force-quit. The rate is
    /// therefore capped here, at the one place that knows a navigation is
    /// about to leave the app. A human clicking links is nowhere near this
    /// limit; a script is past it on its second iteration.
    ///
    /// The cap is per panel, which is where the state can live without
    /// inventing a shared one — an extension that wanted more could open more
    /// panels, but a panel opening is itself something the user sees.
    func policy(for navigationAction: WKNavigationAction) -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if url.scheme == WebviewResourceURL.scheme { return .allow }
        guard navigationAction.navigationType == .linkActivated,
              let scheme = url.scheme, scheme == "http" || scheme == "https"
        else { return .cancel }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastExternalOpen >= externalOpenInterval else {
            Self.logger.notice(
                "A webview asked to open links faster than a person can click; dropping one")
            return .cancel
        }
        lastExternalOpen = now
        openExternalURL(url)
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
        guard let onRevealRequested else {
            if !hasBeenPlaced { deferredReveal = preserveFocus }
            return
        }
        onRevealRequested(preserveFocus)
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

private extension WKWebView {

    /// Keeps the page painting while the app's windows are sunk behind the
    /// desktop picture.
    ///
    /// WebKit stops drawing into a window the window server reports occluded —
    /// it logs `window occluded 1`, `isViewVisible()` goes false, and what a
    /// screenshot picks up is whatever was last painted, which for a page that
    /// was never on screen is nothing at all. Quiet presentation sinks every
    /// window below the desktop *on purpose*, so under automation every webview
    /// is occluded by definition. JavaScript keeps running throughout — the
    /// page loads, `acquireVsCodeApi()` works, `setState` persists — which is
    /// why this stayed invisible until something had to be photographed.
    ///
    /// Debug-only, and SPI: `_setWindowOcclusionDetectionEnabled:` is not API,
    /// so it is asked for by name and skipped where this WebKit has no such
    /// selector. A shipping binary does not carry it at all — there is no
    /// automation driving a released app, and a real user's occluded window
    /// *should* stop painting rather than burn the battery drawing frames
    /// nobody can see.
    func keepPaintingUnderQuietPresentation() {
        #if DEBUG
        guard QuietWindowPresentation.isEnabled else { return }
        let selector = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        guard responds(to: selector) else { return }
        // Called through the implementation rather than `perform(_:with:)`,
        // which takes an object: the parameter is a `BOOL`, and the only way to
        // pass a false one through `perform` is a nil argument that reads as
        // zero by accident (`explicit-over-implicit`).
        typealias Setter = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
        let implementation = unsafeBitCast(method(for: selector), to: Setter.self)
        implementation(self, selector, false)
        #endif
    }
}
