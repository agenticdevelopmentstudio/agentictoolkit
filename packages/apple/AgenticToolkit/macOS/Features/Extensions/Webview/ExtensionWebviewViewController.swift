//
//  ExtensionWebviewViewController.swift
//  AgenticToolkit
//

import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import Foundation

/// Builds the live webview a contributed view of `kind == .webview` should
/// hold, and says when the extension's provider has actually taken it.
///
/// The seam between `ViewsContributionPoint`, which knows what the manifest
/// declared, and `ExtensionHostInstaller`, which knows who is installed and
/// whether they are awake. A closure rather than a protocol for
/// `WebviewPanelSerializer`'s reason, one file over: this is one verb with one
/// production implementation, wired late because the installer does not exist
/// when the contribution point is built.
///
/// - Parameters:
///   - view: The declaration, including the extension that made it.
///   - didResolve: Called when the extension's `resolveWebviewView` has run —
///     **synchronously if it is already awake**, and a turn or two later if it
///     had to be activated first. Not called at all if it never resolves, which
///     is what leaves the pane showing its explanation.
/// - Returns: The panel, un-loaded, or `nil` when there is nobody to draw it.
///   Un-loaded matters: a provider's first act is to assign `options` and
///   `html`, and both are free until `loadView()` has run.
public typealias ContributedWebviewResolving = @MainActor (
    _ view: ContributedView,
    _ didResolve: @escaping () -> Void
) -> WebviewPanelViewController?

/// The pane a contributed **webview** view gets: its extension's page once the
/// extension draws one, and the same explanation a tree view shows until then.
///
/// **A wrapper rather than the webview itself**, for one reason that is worth
/// the class: a `WKWebView` with nothing loaded is a blank white rectangle, and
/// a pane that shows one says nothing about why. An extension that declares a
/// view and registers no provider for it is ordinary — the provider may be
/// behind an activation event that has not happened, or behind a `when` clause
/// nothing has satisfied — so the state has to be *legible*, not merely empty
/// (`principle-of-least-astonishment`). The same wrapper is then what lets the
/// pane go back to saying so when the extension is disabled.
///
/// The swap runs at most twice and in one direction each time, which is why
/// there is no state machine here: placeholder → webview when the provider
/// resolves, webview → placeholder if that webview is later disposed.
@MainActor
public final class ExtensionWebviewViewController: NSViewController {

    private let contributedView: ContributedView
    private let extensionDisplayName: String
    private let resolve: ContributedWebviewResolving

    /// The panel, from the moment it is built — which is before the provider
    /// has been asked, and so before it is shown. Held rather than only added
    /// as a child because `adoptPanel()` may run inside `resolve`, before the
    /// return value has been assigned to anything.
    private var panel: WebviewPanelViewController?

    /// Set by the `didResolve` callback. A flag rather than a direct swap
    /// because of that same synchronous case: the callback can fire while
    /// `resolve` is still on the stack and `panel` is still `nil`, and the
    /// alternative — resolving before building — is not available, since the
    /// panel is what gets resolved.
    private var isResolved = false

    /// What is on screen now. `nil` until `loadView()`.
    private var content: NSViewController?

    /// Stops the teardown path from putting a placeholder back into a pane
    /// that is being discarded: closing the pane disposes the panel, and
    /// disposing fires the very callback that reverts.
    private var isBeingDiscarded = false

    /// `PaneTitleProviding.onPaneTitleChange`, held here and forwarded, because
    /// the pane claims it before any panel exists and must keep hearing about
    /// retitles across a swap.
    private var onTitleChange: (() -> Void)?

    public init(
        view: ContributedView,
        extensionDisplayName: String,
        resolve: @escaping ContributedWebviewResolving
    ) {
        self.contributedView = view
        self.extensionDisplayName = extensionDisplayName
        self.resolve = resolve
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        container.wantsLayer = true
        container.observeTheme { view, palette in
            view.layer?.backgroundColor = palette.nsColor(.surface).cgColor
        }
        view = container
        show(ExtensionViewPlaceholderViewController(
            view: contributedView, extensionDisplayName: extensionDisplayName))
    }

    /// Asks for the panel here rather than in `loadView()` because a
    /// synchronous resolve swaps the content, and swapping content while
    /// `view` is still being assigned is how a view controller ends up asking
    /// for its own view from inside `loadView`.
    public override func viewDidLoad() {
        super.viewDidLoad()
        let panel = resolve(contributedView) { [weak self] in
            guard let self else { return }
            self.isResolved = true
            self.adoptPanelIfResolved()
        }
        self.panel = panel
        // Disposal is the extension going away — unloaded, reloaded, disabled.
        // The pane is the manifest's, not the panel's, so it stays and goes
        // back to explaining itself. `onRemovalRequested` rather than
        // `onDidDispose`, which the extension host has already claimed to
        // forward to the extension's own listeners.
        panel?.onRemovalRequested = { [weak self] in
            self?.revertToPlaceholder()
        }
        adoptPanelIfResolved()
    }

    private func adoptPanelIfResolved() {
        guard isResolved, !isBeingDiscarded, let panel, content !== panel else { return }
        show(panel)
    }

    private func revertToPlaceholder() {
        guard !isBeingDiscarded, content is WebviewPanelViewController else { return }
        panel = nil
        show(ExtensionViewPlaceholderViewController(
            view: contributedView, extensionDisplayName: extensionDisplayName))
    }

    /// Replaces whatever is on screen, wiring the pane's title callback to
    /// whichever child holds it now.
    private func show(_ child: NSViewController) {
        if let current = content {
            (current as? PaneTitleProviding)?.onPaneTitleChange = nil
            current.removeFromParent()
            current.view.removeFromSuperview()
        }
        content = child
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        (child as? PaneTitleProviding)?.onPaneTitleChange = { [weak self] in
            self?.onTitleChange?()
        }
        // The title moved by definition: the new child answers `paneTitle`
        // differently from the old one, and nothing else will say so.
        onTitleChange?()
    }
}

// MARK: - Being a pane

extension ExtensionWebviewViewController: PaneTitleProviding {

    /// The panel's title once there is one, and the manifest's name until then
    /// — which is also what the placeholder is showing, so the chrome and the
    /// pane never disagree.
    public var paneTitle: String {
        (content as? PaneTitleProviding)?.paneTitle ?? contributedView.name
    }

    /// Stored here and forwarded, rather than handed straight to the panel:
    /// `PaneViewController.wireContentCallbacks()` sets this in `viewDidLoad`,
    /// which for this controller is the same turn the panel is built, and a
    /// swap must not drop the pane's only route to a retitle.
    public var onPaneTitleChange: (() -> Void)? {
        get { onTitleChange }
        set { onTitleChange = newValue }
    }
}

extension ExtensionWebviewViewController: PaneContentTeardown {

    /// Forwards to the panel, which is what releases the web content process —
    /// `WebviewPanelViewController.paneContentWillBeDiscarded()`'s own reason
    /// for existing. The flag is set first: disposing fires
    /// `onRemovalRequested`, which would otherwise build a placeholder into a
    /// pane on its way out.
    public func paneContentWillBeDiscarded() {
        isBeingDiscarded = true
        // The panel, not `content`: a panel that was built and never resolved
        // holds the same web content process as one that is on screen, and it
        // is the one thing here with something to release.
        panel?.paneContentWillBeDiscarded()
    }
}
