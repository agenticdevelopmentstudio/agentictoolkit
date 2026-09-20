//
//  WebviewPanelSerializer.swift
//  AgenticToolkit
//

import AppKit
import Foundation
import os
import AgenticToolkitCore

/// Keeps an extension's webview panels across a quit: one registered view
/// identifier, one row of pane state per panel, and the handoff back to the
/// extension that owns the view type.
///
/// ### Why a single view identifier
///
/// A pane never holds a view controller — it holds a `ComposableTabsViewID`
/// and asks the registry to build the content, and the *identifier* is what
/// the window's persisted layout records. An identifier minted per panel
/// (`extension.webview.<panelID>`, which is what placement used before this
/// type existed) therefore cannot survive a relaunch: nothing re-registers it,
/// and the pane comes back as a placeholder. So every extension webview pane
/// is one identifier, `extension.webview`, and *which* panel a given pane holds
/// is carried where per-pane facts belong — in the project's pane state, keyed
/// by the pane's node id.
///
/// ### The two ways a pane gets its panel
///
/// - **A panel an extension just created.** `ExtensionWebviewPanePlacer` hands
///   it here, splits a pane on the shared identifier, and the factory below
///   finds it waiting.
/// - **A pane rebuilt from a persisted layout.** Nothing is waiting, so the
///   factory reads the stored `WebviewPanelState`, asks the host installer for
///   the extension that claims its view type, and puts the panel that extension
///   deserializes into the pane.
///
/// Both paths end at the same place — `persist(_:in:)`, which is what makes the
/// panel's title and the page's own `setState` survive the next quit.
@MainActor
public final class WebviewPanelSerializer {

    /// The one identifier every extension webview pane is laid out under.
    public static let viewID = ComposableTabsViewID("extension.webview")

    /// The pane-state key the panel's `WebviewPanelState` is stored under.
    ///
    /// Not prefixed `chrome.`, which `ProjectWorkspace.paneState(nodeID:key:)`
    /// reserves for the pane's own chrome.
    public static let paneStateKey = "extension.webview.panel"

    /// Builds the panel a stored pane comes back as and hands it to the
    /// extension that owns its view type, or answers `nil` when no installed
    /// extension claims it.
    ///
    /// A closure rather than a reference to the host installer, for
    /// `PaneWebviewPresenter.Place`'s reason: this type is about panes and
    /// pane state, and which extension owns a view type is the installer's
    /// question entirely (`manage-complexity-through-boundaries`).
    public typealias Restore = (WebviewPanelState) -> WebviewPanelViewController?

    private let registry: ComposableTabsViewRegistry
    private let restore: Restore

    /// A panel placed but not yet claimed by a pane, keyed by the node id of
    /// the pane the split made for it.
    ///
    /// Two stages, because the pane tree builds content **lazily**:
    /// `ComposableTabsViewController.split(_:adding:direction:)` returns with
    /// the pane in the tree but its content unbuilt — `PaneViewController`
    /// calls the factory from `loadView()`, which may be this turn or several
    /// later. `unplaced` covers the case where the factory runs *inside*
    /// `split`, before the caller has a node id to key on; `pendingByNode`
    /// covers every other case.
    private var unplaced: WebviewPanelViewController?
    private var pendingByNode: [UUID: WebviewPanelViewController] = [:]

    /// The panes that already existed when the in-flight split began, and so
    /// cannot be the pane it is making.
    ///
    /// The `unplaced` slot has to be claimable by a pane whose node id nobody
    /// knows yet, which is the whole of why it exists — but "any pane at all"
    /// was too wide by one case that really happens: a split forces a layout
    /// pass, and a layout pass builds panes that had been left lazy. A
    /// restored extension webview pane in a tab the user has not opened yet is
    /// one of those, and it ran this same factory, under this same one
    /// identifier, in the middle of the split. It took the panel; the pane the
    /// split made came up empty; and the panel the old pane should have
    /// restored was never asked for. Naming the panes that existed first is
    /// what distinguishes "the pane being built is the new one" from "the pane
    /// being built is an old one waking up".
    private var panesBeforeSplit: Set<UUID> = []

    /// The pane that claimed `unplaced` from inside `split`, for the placer to
    /// read back. Cleared by the next `prepareToPlace`, so it only ever
    /// describes the placement in flight.
    private var claimedDuringSplit: (panel: WebviewPanelViewController, nodeID: UUID)?

    /// Registers `viewID` on `registry`, which is what makes a persisted
    /// layout naming it resolve to a panel rather than a placeholder.
    public init(registry: ComposableTabsViewRegistry, restore: @escaping Restore) {
        self.registry = registry
        self.restore = restore
        registry.register(
            Self.viewID,
            descriptor: ComposableTabsViewDescriptor(
                displayName: "Extension Webview",
                symbolName: "globe",
                isCollapsible: true)
        ) { [weak self] context in
            guard let self else { return PlaceholderPaneViewController(paneNumber: context.paneNumber) }
            return self.makeContent(for: context)
        }
    }

    // MARK: - Placing a newly created panel

    /// Takes ownership of a panel that is about to be split into a pane.
    ///
    /// Called immediately before `split(_:adding:direction:)`, because the
    /// factory may run inside that call. Between here and `didPlace(_:in:)`
    /// this object is the only thing holding the panel.
    ///
    /// - Parameter panesBeforeSplit: The node ids of every pane that exists
    ///   now, before the split. None of them may claim this panel — see the
    ///   property of the same name.
    public func prepareToPlace(
        _ panel: WebviewPanelViewController, panesBeforeSplit: Set<UUID>
    ) {
        unplaced = panel
        self.panesBeforeSplit = panesBeforeSplit
        claimedDuringSplit = nil
    }

    /// Which pane took `panel` while the split was still running, if one did.
    ///
    /// The placer's fallback for naming the pane it just made. It normally
    /// finds that pane by difference against the panes it listed beforehand;
    /// when that comes up empty but the factory has already handed the panel
    /// over, cancelling the placement would be wrong — the panel is on screen
    /// — and this is the pane it is in.
    public func nodeIDOfPaneThatClaimed(_ panel: WebviewPanelViewController) -> UUID? {
        guard let claimed = claimedDuringSplit, claimed.panel === panel else { return nil }
        return claimed.nodeID
    }

    /// Names the pane the split actually made, so the factory can find the
    /// panel when it runs later.
    ///
    /// A no-op when the factory already ran inside `split` and consumed
    /// `unplaced` — that pane has its panel, and the node id is only needed to
    /// *find* one still waiting (`idempotency`).
    public func didPlace(_ panel: WebviewPanelViewController, in nodeID: UUID) {
        guard unplaced === panel else { return }
        unplaced = nil
        panesBeforeSplit = []
        pendingByNode[nodeID] = panel
    }

    /// Drops a panel that was prepared for a split that did not happen.
    ///
    /// Without this, a failed placement would leave the panel in `unplaced`
    /// for the *next* extension webview pane to pick up — a panel appearing in
    /// a pane nobody asked to put it in.
    public func cancelPlacement(of panel: WebviewPanelViewController) {
        guard unplaced === panel else { return }
        unplaced = nil
        panesBeforeSplit = []
    }

    // MARK: - Filling a pane

    private func makeContent(for context: ComposableTabsViewContext) -> NSViewController {
        if let panel = takePending(nodeID: context.nodeID) {
            // Reveal and removal are already installed by `PaneWebviewPresenter`
            // from the placement it was handed; only persistence is missing.
            persist(panel, in: context)
            return panel
        }
        return makeRestoredContent(for: context)
    }

    private func takePending(nodeID: UUID) -> WebviewPanelViewController? {
        if let panel = pendingByNode.removeValue(forKey: nodeID) { return panel }
        // The factory ran inside `split`, so `didPlace` has not been called
        // yet. There can only be one such panel — a split is one call — and
        // this pane is the one it was for *unless* it is a pane that already
        // existed when the split started, which is a lazy pane the split's own
        // layout pass has just woken up. See `panesBeforeSplit`.
        guard let panel = unplaced, !panesBeforeSplit.contains(nodeID) else { return nil }
        unplaced = nil
        claimedDuringSplit = (panel: panel, nodeID: nodeID)
        return panel
    }

    private func makeRestoredContent(for context: ComposableTabsViewContext) -> NSViewController {
        let blank = PlaceholderPaneViewController(paneNumber: context.paneNumber)
        guard let stored = context.project.paneState(
            nodeID: context.nodeID, key: Self.paneStateKey)
        else {
            // A pane laid out under this identifier with nothing stored is a
            // layout written before this row existed, or a row that failed to
            // save. Either way there is no panel to rebuild and nothing to
            // blame an extension for.
            Self.logger.notice(
                """
                An extension webview pane (node \(context.nodeID.uuidString, privacy: .public)) \
                has no stored panel; it comes back empty
                """)
            return blank
        }
        guard let state = try? WebviewPanelState(json: stored) else {
            Self.logger.error(
                """
                An extension webview pane (node \(context.nodeID.uuidString, privacy: .public)) \
                stored a panel this app cannot read; it comes back empty
                """)
            return blank
        }
        guard let panel = restore(state) else { return blank }

        // A restored panel was never placed, so nothing installed the two verbs
        // `PaneWebviewPresenter` takes from `ExtensionWebviewPlacement` on the
        // creation path. They are the placer's, called with the node id this
        // pane is being built for — and the pane does not exist yet at this
        // moment, which is exactly why those verbs look it up at call time.
        let nodeID = context.nodeID
        panel.onRevealRequested = { preserveFocus in
            ExtensionWebviewPanePlacer.reveal(nodeID: nodeID, preserveFocus: preserveFocus)
        }
        panel.onRemovalRequested = {
            ExtensionWebviewPanePlacer.remove(nodeID: nodeID)
        }
        persist(panel, in: context)
        return panel
    }

    // MARK: - Writing it down

    /// Stores the panel now, and again whenever what would be stored changes.
    ///
    /// `onRestorationStateChanged` rather than `onPaneTitleChange`: the pane
    /// claims that one in `viewDidLoad`, which runs after this factory
    /// returned, so anything installed there would be overwritten a moment
    /// later. See the callback's own doc.
    ///
    /// The write happens up front as well as on change because a panel that is
    /// never retitled and never calls `setState` is still a panel that has to
    /// come back — and on the creation path this is the only moment before the
    /// user quits that anything knows the pane's node id.
    private func persist(_ panel: WebviewPanelViewController, in context: ComposableTabsViewContext) {
        let project = context.project
        let nodeID = context.nodeID
        let write: () -> Void = { [weak panel] in
            guard let panel else { return }
            do {
                project.setPaneState(
                    nodeID: nodeID,
                    key: Self.paneStateKey,
                    value: try panel.restorationState.encoded())
            } catch {
                Self.logger.error(
                    """
                    A webview panel of type \(panel.viewType, privacy: .public) could not be \
                    encoded for storage: \(error.localizedDescription, privacy: .public)
                    """)
            }
        }
        panel.onRestorationStateChanged = write
        write()
    }
}

extension WebviewPanelSerializer: Loggable {
    public static nonisolated let logger = makeLogger()
}
