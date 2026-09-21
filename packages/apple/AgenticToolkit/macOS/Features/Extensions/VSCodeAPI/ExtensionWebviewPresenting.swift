//
//  ExtensionWebviewPresenting.swift
//  AgenticToolkit
//

import Foundation
import AgenticToolkitCore

/// One `vscode.window.createWebviewPanel` call, reduced to what a presenter
/// needs to put a panel on screen.
///
/// `localResourceRoots` arrives **already resolved** rather than as the option
/// the extension wrote. Resolving it needs the extension's install directory
/// and the open workspace folders — two facts `MainThreadWebviews` has and a
/// presenter has no business collecting — and leaving the default to the
/// presenter would mean every conformer, test doubles included, had to agree
/// on it (`dry`).
///
/// A value type and `Sendable` for `ExtensionStatusBarItemRequest`'s reason:
/// this is the snapshot a presenter carries, not a handle on a live model.
public struct ExtensionWebviewPanelRequest: Sendable, Equatable {

    /// `createWebviewPanel`'s first argument: the type this panel is created
    /// under, and the key a serializer is registered against.
    public let viewType: String

    /// What the pane's chrome calls it to begin with.
    public let title: String

    /// What the extension asked for, with the defaults applied.
    public let options: WebviewPanelOptions

    /// Every directory this panel may read files from, already resolved and
    /// deduplicated — see this type's own doc.
    public let localResourceRoots: [URL]

    /// `WebviewPanelOptions`' sibling out of `showOptions`: whether the panel
    /// should appear without taking focus from wherever the user is typing.
    ///
    /// The *column* half of `showOptions` is deliberately not here. A
    /// `ViewColumn` numbers an editor group in a row of them; this app's panes
    /// are a tree the user splits where they like, and there is no column for a
    /// number to select. A presenter puts the panel beside the focused pane
    /// whatever the extension asked for.
    public let preserveFocus: Bool

    /// Who asked, for the log line that a panel-less window produces.
    public let extensionIdentifier: String

    public init(
        viewType: String,
        title: String,
        options: WebviewPanelOptions,
        localResourceRoots: [URL],
        preserveFocus: Bool,
        extensionIdentifier: String
    ) {
        self.viewType = viewType
        self.title = title
        self.options = options
        self.localResourceRoots = localResourceRoots
        self.preserveFocus = preserveFocus
        self.extensionIdentifier = extensionIdentifier
    }
}

/// A panel that is on screen, as the adaptor that minted it talks to it.
///
/// Every member here is something the `vscode` API can reach: `webview.html`,
/// `webview.postMessage`, `panel.title`, `panel.reveal`, `panel.dispose`, and
/// the two callbacks behind `webview.onDidReceiveMessage` and
/// `panel.onDidDispose`. Nothing here is view-shaped — a conformer is free to
/// be a view controller, and the production one is, but this protocol is what
/// keeps `MainThreadWebviews` from importing WebKit to say so.
///
/// **`panelTitle` rather than `title`.** The production conformer is an
/// `NSViewController`, whose own `title` is `String?`; a protocol requirement
/// spelled `title: String` could not be satisfied by it at all. The rest of
/// the names match the conformer's existing members exactly.
@MainActor
public protocol ExtensionWebviewPanel: AnyObject {

    /// This panel's origin, and the authority half of every URL it may load.
    /// `asWebviewUri` and `cspSource` are both built from it.
    var panelID: String { get }

    /// What the pane's chrome calls it. `WebviewPanel.title`.
    var panelTitle: String { get set }

    /// `Webview.html`. Assigning reloads the page.
    var html: String { get set }

    /// `WebviewOptions.localResourceRoots`, re-narrowable at runtime.
    var localResourceRoots: [URL] { get set }

    /// The `WebviewOptions` the page is under *now*, not the ones it was
    /// built with. `Webview.options` (`vscode.d.ts:11667`) is a settable
    /// property upstream, and for a contributed webview view it is the only
    /// route there is: the host builds the view and the extension's
    /// `resolveWebviewView` turns scripts on inside it, because only the
    /// extension knows whether its page runs code.
    ///
    /// Resolved roots stay their own property. This one carries what the
    /// extension *declared*, and turning a declaration into directories needs
    /// the extension's install directory — see `ExtensionWebviewPanelRequest`'s
    /// doc for why that resolution never reaches a panel.
    var options: WebviewPanelOptions { get set }

    /// The JSON text the page last passed to `setState`, or `nil`. What a
    /// serializer writes down.
    var state: String? { get }

    /// Called when the page calls `vscode.postMessage(...)`.
    var onDidReceiveMessage: ((Any) -> Void)? { get set }

    /// Called once, when the panel goes — by the extension or by the user
    /// closing its pane.
    var onDidDispose: (() -> Void)? { get set }

    /// Whether this panel is already gone.
    ///
    /// `onDidDispose` says *when* a panel goes, which is only useful to
    /// something that was already holding it. A hand-over —
    /// `MainThreadWebviews.restore` and `resolveWebviewView` — arrives at a
    /// panel it has never seen, and a pane the user closed while its extension
    /// was still waking up has already fired that callback with nobody
    /// listening. So the state has to be *askable*, not only announced: a
    /// panel adopted after the fact would wire a disposal callback that can
    /// never fire again, and be held, with its page and its JavaScript object,
    /// until the extension is unloaded.
    var isDisposed: Bool { get }

    /// `Webview.postMessage`. Answers whether the message reached the page —
    /// `false` for a disposed panel, and for a value WebKit will not pass.
    @discardableResult
    func post(message: Any) -> Bool

    /// `WebviewPanel.reveal`. Brings the panel's pane to the front; with
    /// `preserveFocus` it does so without taking the keyboard.
    func reveal(preserveFocus: Bool)

    /// `WebviewPanel.dispose`. Idempotent — an extension disposing a panel the
    /// user already closed is the ordinary race, not an error.
    func dispose()
}

/// Where a `createWebviewPanel` call actually puts a panel on screen (or, in a
/// test, records what it was asked to show).
///
/// A fifth presenter beside the four `MainThreadWindow` already takes, for the
/// reason `ExtensionQuickPickPresenting`'s own doc gives for the second: the
/// conformer that opens a pane needs a window manager and a pane tree, and
/// nothing that presents a message, a picker, an input box or a status bar
/// item needs any of it.
@MainActor
public protocol ExtensionWebviewPresenting: AnyObject {

    /// Builds the panel and puts it on screen.
    ///
    /// - Returns: The live panel, or `nil` when there is nowhere to put one —
    ///   this app's windows are per project, and an extension can call this
    ///   while none is open. `nil` becomes a raised JavaScript error rather
    ///   than a panel object that answers nothing, so an extension finds out at
    ///   the call it wrote (`fail-fast`).
    func presentWebviewPanel(_ request: ExtensionWebviewPanelRequest) -> (any ExtensionWebviewPanel)?
}
