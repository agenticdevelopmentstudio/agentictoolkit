//
//  PaneWebviewPresenter.swift
//  AgenticToolkit
//

import AppKit
import Foundation
import AgenticToolkitCore

/// What placing a panel in a window's pane tree gives back: the two verbs the
/// panel itself cannot perform.
///
/// A struct of closures rather than a protocol with one conformer: the pane
/// tree lives in the app, the panel lives here, and the only things that cross
/// are "bring this forward" and "take this out" (`yagni`,
/// `design-for-deletion`). `WindowFooterStatusBarPresenter`'s `onCommand` is
/// the same shape for the same reason.
@MainActor
public struct ExtensionWebviewPlacement {

    /// Selects the panel's pane, honouring `preserveFocus`.
    public let reveal: (Bool) -> Void

    /// Takes the panel's pane out of the tree.
    ///
    /// Called from `WebviewPanelViewController.dispose()`, which the user
    /// closing the pane also reaches — so this must tolerate a pane that is
    /// already going away. See `onRemovalRequested`.
    public let remove: () -> Void

    public init(reveal: @escaping (Bool) -> Void, remove: @escaping () -> Void) {
        self.reveal = reveal
        self.remove = remove
    }
}

/// Builds the panel `vscode.window.createWebviewPanel` asked for, and hands it
/// to the app to put in a pane.
///
/// The division is the one `NSAlertMessagePresenter` draws with
/// `ExtensionHostSeams.frontWindow`: everything about *what a webview panel is*
/// is here, in the framework that owns `WebviewPanelViewController`, and
/// everything about *where a view goes in a window* is a closure the app
/// supplies, because `ProjectWindowManager` and the pane tree are the app's
/// (`manage-complexity-through-boundaries`).
///
/// Shared by every extension, like the other presenters: a panel is a panel
/// whichever extension asked for one. The per-extension facts —
/// which directories it may read, who to blame in the ledger — arrive on the
/// `ExtensionWebviewPanelRequest`, already resolved by `MainThreadWebviews`.
@MainActor
public final class PaneWebviewPresenter: ExtensionWebviewPresenting {

    /// Puts a freshly built panel in a pane, or answers `nil` when there is
    /// nowhere to put it — no project window open, most usually.
    ///
    /// The panel arrives fully configured and **not yet disposed**; the
    /// closure's whole job is placement.
    public typealias Place = (WebviewPanelViewController) -> ExtensionWebviewPlacement?

    private let place: Place

    public init(place: @escaping Place) {
        self.place = place
    }

    public func presentWebviewPanel(
        _ request: ExtensionWebviewPanelRequest
    ) -> (any ExtensionWebviewPanel)? {
        let panel = WebviewPanelViewController(
            viewType: request.viewType,
            title: request.title,
            options: request.options,
            localResourceRoots: request.localResourceRoots)

        guard let placement = place(panel) else { return nil }

        panel.onRevealRequested = placement.reveal
        panel.onRemovalRequested = placement.remove

        // `preserveFocus` is honoured by revealing straight away rather than
        // by passing it down into placement: a panel is created *and* shown by
        // one `createWebviewPanel` call (`vscode.d.ts:12525`), so the two would
        // be the same act expressed twice (`dry`). The app's `place` closure
        // puts the pane in the tree; this line is what decides whether the
        // user's caret goes with it.
        panel.reveal(preserveFocus: request.preserveFocus)

        return panel
    }
}
