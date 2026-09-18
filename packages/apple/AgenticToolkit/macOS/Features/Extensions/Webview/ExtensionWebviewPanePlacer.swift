//
//  ExtensionWebviewPanePlacer.swift
//  AgenticToolkit
//

import AppKit
import Foundation
import os
import AgenticToolkitCore

/// Puts an extension's webview panel in the front project window, beside the
/// pane the user is already looking at.
///
/// This is the app-facing half of `PaneWebviewPresenter` — what
/// `ExtensionHostSeams.placeWebviewPanel` is wired to in production. It is
/// here rather than in the app because everything it touches is this
/// framework's: `ProjectWindowManager`, the pane tree, and the view registry
/// the tree resolves content through. The app supplies it as a one-line
/// closure, exactly as it supplies `frontWindow` and `footers`.
///
/// ### The one-off view identifier
///
/// A pane never holds a view controller directly — it holds a
/// `ComposableTabsViewID` and asks the registry to build the content. So a
/// panel that already exists is placed by registering an identifier unique to
/// it (`extension.webview.<panelID>`) whose factory hands back that very
/// instance, splitting a pane on it, and unregistering when the panel is
/// disposed. Handing back one instance rather than building a fresh one per
/// call is deliberate: a webview holds page state, and a tab switch that
/// rebuilt the pane's content would silently reload the extension's page.
///
/// **Honest limit, and where it is fixed:** the layout the window persists
/// records that identifier, and nothing re-registers it at the next launch, so
/// a panel left open at quit comes back as a placeholder pane. Restoring it
/// properly is `WebviewPanelSerializer`'s job — `vscode.window.registerWebviewPanelSerializer`
/// exists precisely because upstream has the same problem — and this comment is
/// the note that the two belong together.
@MainActor
public enum ExtensionWebviewPanePlacer {

    /// The `PaneWebviewPresenter.Place` the app installs.
    ///
    /// `nil` when there is no project window open — which is a real state, not
    /// a failure: this app's windows belong to projects, and an extension can
    /// activate (on `*`, on a command) with none open. `MainThreadWebviews`
    /// turns that `nil` into a JavaScript exception naming the reason.
    public static func place(
        _ panel: WebviewPanelViewController
    ) -> ExtensionWebviewPlacement? {
        guard let controller = ProjectWindowManager.shared.frontWindowController else {
            return nil
        }
        // The anchor is the pane the user is working in, falling back to the
        // window's first. `split(_:adding:direction:)` puts the new pane beside
        // the one it is given, so this is what decides where the panel appears
        // — and beside what they are looking at is the least astonishing
        // answer (`principle-of-least-astonishment`).
        let panes = controller.allPanes()
        let activeNodeID = ComposableTabsActivePane.shared.activeNodeID(in: controller.window)
        guard let anchor = panes.first(where: { $0.nodeID == activeNodeID }) ?? panes.first,
              let split = anchor.host as? ComposableTabsViewController
        else { return nil }

        let registry = controller.project.layout.registry
        let viewID = ComposableTabsViewID("extension.webview.\(panel.panelID)")
        registry.register(
            viewID,
            descriptor: ComposableTabsViewDescriptor(
                displayName: panel.paneTitle,
                symbolName: "globe",
                isCollapsible: true)
        ) { _ in
            // Strongly captured, and that is the ownership: between this
            // registration and the split below, the registry is the only thing
            // holding the panel. `remove` unregisters, which is what lets it
            // go.
            panel
        }

        // The pane the split just made, found by difference, exactly as
        // `DocumentTabsViewController.openToTheSide(_:)` finds its editor: the
        // split lands beside the *anchor*, so "the last pane" would be the
        // wrong pane as soon as the anchor is not the last one.
        let before = Set(panes.map(ObjectIdentifier.init))
        split.split(anchor, adding: viewID, direction: .right)
        guard let pane = controller.allPanes().first(where: {
            !before.contains(ObjectIdentifier($0))
        }) else {
            registry.unregister(viewID)
            Self.logger.error(
                """
                A webview panel was registered as \(viewID.rawValue, privacy: .public) but the \
                split produced no pane to put it in
                """)
            return nil
        }

        return ExtensionWebviewPlacement(
            reveal: { [weak pane] preserveFocus in
                guard let pane, let window = pane.view.window else { return }
                ComposableTabsActivePane.shared.activate(nodeID: pane.nodeID, in: window)
                // Never `makeKeyAndOrderFront` — revealing a pane is a change
                // *within* a window, and a window that came forward on an
                // extension's say-so would take the user's next keystrokes.
                // See the project's "never take the screen" rule.
                if !preserveFocus {
                    window.makeFirstResponder(pane.view)
                }
            },
            remove: { [weak pane] in
                // Unregistering first: it is the half that must happen whether
                // or not the pane is still findable, and it is what releases
                // the panel this closure's sibling captured.
                registry.unregister(viewID)
                guard let pane, let host = pane.host as? ComposableTabsViewController else {
                    return
                }
                // `remove(_:)` is a no-op for a pane this split no longer
                // holds, so the user's own close — which reaches here through
                // `paneContentWillBeDiscarded()` → `dispose()` — costs a
                // failed lookup rather than a second removal (`idempotency`).
                host.remove(pane)
            })
    }
}

extension ExtensionWebviewPanePlacer: Loggable {
    public static nonisolated let logger = makeLogger()
}
