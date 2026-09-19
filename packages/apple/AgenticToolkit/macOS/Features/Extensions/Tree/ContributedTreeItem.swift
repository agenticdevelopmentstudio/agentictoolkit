//
//  ContributedTreeItem.swift
//  AgenticToolkit
//

import Foundation
import AgenticToolkitCore

/// One row of a contributed tree view, as far as the pane needs to know it.
///
/// A `vscode.TreeItem` (`vscode.d.ts:11391`) read down to what an
/// `NSOutlineView` row can draw, plus the one thing that is not drawable: the
/// `elementID` that names the extension's own element back in its JSContext.
///
/// **The element, not the item, is the identity.** `TreeDataProvider` is
/// asked for children of an *element* — the extension's own model object —
/// and it is asked to turn that element into a `TreeItem` separately
/// (`getChildren(element)` and `getTreeItem(element)`). The item is a
/// rendering of the element, re-made on demand, so two items that look
/// identical are the same row only if their elements are. That is why `id`
/// here is `elementID` rather than upstream's optional `TreeItem.id`:
/// upstream's is a hint for reveal and persistence, this is the handle
/// without which the next `getChildren` cannot be asked.
///
/// In `macOS` rather than `Core`, unlike `ContributedView` beside it, because
/// its only builder reads a `JSValue` and its only consumer is an AppKit pane
/// — both above `Core`. A value type here with no producer or consumer there
/// would be a shared component nobody assembles from (`design-for-deletion`).
public struct ContributedTreeItem: Sendable, Equatable, Identifiable {

    /// `vscode.TreeItemCollapsibleState` (`vscode.d.ts:11530-11543`).
    ///
    /// The raw values are upstream's and are load-bearing: an extension is
    /// as likely to write `1` as `vscode.TreeItemCollapsibleState.Collapsed`,
    /// so this is read from a number rather than from a name.
    public enum CollapsibleState: Int, Sendable, Equatable {
        case none = 0
        case collapsed = 1
        case expanded = 2

        /// `.none` for anything that is not one of the three, which is
        /// upstream's own reading of an absent `collapsibleState` — a leaf.
        /// Clamping rather than refusing because a tree with one odd row is
        /// worth more to a user than no tree (`principle-of-least-astonishment`).
        public static func read(_ raw: Int?) -> CollapsibleState {
            guard let raw, let state = CollapsibleState(rawValue: raw) else { return .none }
            return state
        }

        /// Whether the outline view should offer a disclosure triangle.
        ///
        /// Both non-`none` states are expandable; they differ only in whether
        /// the pane expands the row on first sight.
        public var isExpandable: Bool { self != .none }
    }

    /// The handle on the extension's element, minted by the adaptor that
    /// holds the element itself. Opaque here on purpose: a pane that could
    /// read it would be a pane that could guess one.
    public let id: String

    /// What the row shows. Never empty — a `TreeItem` with neither a `label`
    /// nor a `resourceUri` is drawn with its element's description rather
    /// than a blank row, because a blank row is indistinguishable from a
    /// broken pane.
    public let label: String

    /// The dimmer text after the label (`vscode.d.ts:11416`). `nil` when the
    /// item declared none, and also when it declared `true` — upstream reads
    /// `description: true` as "derive it from the resourceUri", which this
    /// host has no resource model to derive from.
    public let description: String?

    /// The hover text (`vscode.d.ts:11421`). A `MarkdownString` tooltip is
    /// read for its `value` and shown as plain text; nothing here renders
    /// Markdown in a tooltip.
    public let tooltip: String?

    public let collapsibleState: CollapsibleState

    /// The SF Symbol the row draws, resolved from a `ThemeIcon`'s id through
    /// `CodiconSymbols`. `nil` for a themed icon with no faithful symbol, and
    /// for an `iconPath` that names a file — which this pane does not load,
    /// for `ContributedViewsBuilder`'s reason one tier down.
    public let symbolName: String?

    /// The command id an activated row runs (`vscode.d.ts:11437`), carried so
    /// the pane can offer activation only on rows that have one. The
    /// arguments stay with the adaptor: they are `any[]` in the extension's
    /// own context and have no meaning here.
    public let commandID: String?

    public init(
        id: String,
        label: String,
        description: String?,
        tooltip: String?,
        collapsibleState: CollapsibleState,
        symbolName: String?,
        commandID: String?
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.tooltip = tooltip
        self.collapsibleState = collapsibleState
        self.symbolName = symbolName
        self.commandID = commandID
    }
}
