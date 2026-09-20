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
/// the tree resolves content through.
///
/// ### Where the panel actually comes from
///
/// A pane never holds a view controller directly — it holds a
/// `ComposableTabsViewID` and asks the registry to build the content. So
/// placing a panel that *already exists* means handing it to something the
/// registry will ask, and that something is `WebviewPanelSerializer`: it owns
/// the one registered identifier every extension webview pane is laid out
/// under, it hands this panel back when the pane for it is built, and it is
/// what puts the panel back after a quit. All this half knows is where to put
/// the pane.
@MainActor
public enum ExtensionWebviewPanePlacer {

    /// The `PaneWebviewPresenter.Place` the app installs, bound to the
    /// serializer that will vend the panel to the pane.
    ///
    /// `nil` when there is no project window open — which is a real state, not
    /// a failure: this app's windows belong to projects, and an extension can
    /// activate (on `*`, on a command) with none open. `MainThreadWebviews`
    /// turns that `nil` into a JavaScript exception naming the reason.
    public static func place(
        _ panel: WebviewPanelViewController,
        using serializer: WebviewPanelSerializer
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

        // Before the split, not after: the pane tree builds content lazily, but
        // "lazily" includes "during this very call" — `PaneViewController`
        // calls the factory from `loadView()`, and a split that lays out
        // immediately reaches it before `split(_:adding:direction:)` returns.
        serializer.prepareToPlace(panel, panesBeforeSplit: Set(panes.map(\.nodeID)))

        // The pane the split just made, found by difference, exactly as
        // `DocumentTabsViewController.openToTheSide(_:)` finds its editor: the
        // split lands beside the *anchor*, so "the last pane" would be the
        // wrong pane as soon as the anchor is not the last one.
        let before = Set(panes.map(ObjectIdentifier.init))
        split.split(anchor, adding: WebviewPanelSerializer.viewID, direction: .right)
        let newPane = controller.allPanes().first { !before.contains(ObjectIdentifier($0)) }
        if let newPane {
            serializer.didPlace(panel, in: newPane.nodeID)
        }
        // The difference lookup is the normal answer; the serializer's is the
        // one case it cannot give. A split that lays out immediately reaches
        // the factory before it returns, so the panel can already be in a pane
        // — and cancelling a placement that has visibly happened would leave
        // that panel on screen in a pane no extension verb can name.
        guard let nodeID = newPane?.nodeID ?? serializer.nodeIDOfPaneThatClaimed(panel) else {
            serializer.cancelPlacement(of: panel)
            Self.logger.error("A webview panel was placed but the split produced no pane to put it in")
            return nil
        }

        return placement(forNodeID: nodeID)
    }

    /// The two verbs, bound to one pane's node id.
    ///
    /// **Both paths that produce a placed panel come through here.** Creating
    /// one lands in `place(_:using:)` above; a panel restored after a quit is
    /// built by `WebviewPanelSerializer`, which never placed anything and so
    /// has to install the same two verbs itself. They were written out twice,
    /// which is one definition of what a placed panel can do in two files
    /// (`dry`) — and the restore copy is the one nobody looks at until a
    /// relaunch.
    public static func placement(forNodeID nodeID: UUID) -> ExtensionWebviewPlacement {
        ExtensionWebviewPlacement(
            reveal: { preserveFocus in
                reveal(nodeID: nodeID, preserveFocus: preserveFocus)
            },
            remove: {
                remove(nodeID: nodeID)
            })
    }

    // MARK: - The two verbs, by node id

    /// Brings the pane holding a panel to the front of its tab.
    ///
    /// By node id rather than a captured pane, because the restore path has no
    /// pane to capture when it installs this — the pane is being built at that
    /// moment — and because a pane can outlive the window this closure was
    /// made in only by not existing any more, which the lookup answers.
    static func reveal(nodeID: UUID, preserveFocus: Bool) {
        guard let pane = pane(withNodeID: nodeID), let window = pane.view.window else { return }
        ComposableTabsActivePane.shared.activate(nodeID: nodeID, in: window)
        // Never `makeKeyAndOrderFront` — revealing a pane is a change *within*
        // a window, and a window that came forward on an extension's say-so
        // would take the user's next keystrokes. See the project's "never take
        // the screen" rule.
        if !preserveFocus {
            window.makeFirstResponder(pane.view)
        }
    }

    /// Closes the pane holding a panel.
    ///
    /// `remove(_:)` is a no-op for a pane its split no longer holds, so the
    /// user's own close — which reaches here through
    /// `paneContentWillBeDiscarded()` → `dispose()` — costs a failed lookup
    /// rather than a second removal (`idempotency`).
    static func remove(nodeID: UUID) {
        guard let pane = pane(withNodeID: nodeID),
              let host = pane.host as? ComposableTabsViewController
        else { return }
        host.remove(pane)
    }

    /// Finds a pane by its layout node id across every open project window.
    ///
    /// Every window, not just the front one: by the time an extension reveals
    /// or disposes a panel the user may well be looking at another project.
    /// Node ids are minted per tab through `LayoutNode.inFreshIDs()` and never
    /// reused, so at most one pane anywhere answers to one.
    static func pane(withNodeID nodeID: UUID) -> ComposableTabsPaneViewController? {
        for controller in ProjectWindowManager.shared.openWindowControllers {
            if let pane = controller.allPanes().first(where: { $0.nodeID == nodeID }) {
                return pane
            }
        }
        return nil
    }
}

extension ExtensionWebviewPanePlacer: Loggable {
    public static nonisolated let logger = makeLogger()
}
