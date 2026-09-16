//
//  ExtensionStatusBarPresenting.swift
//  AgenticToolkit
//
//  Split out of MainThreadWindow.swift, which had grown past 2,800 lines.
//  The adaptor is still the only consumer; this is a file boundary, not a
//  tier one.
//

import Foundation

/// `vscode.window.StatusBarAlignment` (`vscode.d.ts:7545-7556`, measured
/// against pinned upstream `3addbda6`): `Left = 1`, `Right = 2`. Lowercased
/// cases, matching `ExtensionMessageSeverity` — the raw JS
/// numbers map onto these cases at the boundary
/// (`MainThreadWindow.statusBarAlignmentMembers` and `parseAlignment(_:)`)
/// and nowhere else.
public enum ExtensionStatusBarAlignment: Sendable, Equatable {
    case left, right
}

/// One `vscode.window.createStatusBarItem` object, reduced to what a
/// presenter needs to render it — everything Ruling 5 of task 5.5c's brief
/// says this host carries by value, and nothing it routes to
/// `NotImplementedLedger` instead.
///
/// `color` and `backgroundColor` are always the flat `id` string here, never
/// the shape the extension actually wrote: `vscode.d.ts:7605-7608` types
/// `color` as `string | ThemeColor | undefined` and `:7610-7622` types
/// `backgroundColor` as `ThemeColor | undefined`, and
/// `ExtensionStatusBarItem` (the model class inside `MainThreadWindow`)
/// is what remembers which of the two it was, so it can hand the *getter*
/// back the right shape. A presenter that renders a colour only ever needs
/// the id, never the original `JSValue`-shaped shell around it.
///
/// Sendable and a plain value type on purpose: a presenter may hop off the
/// main actor to lay out a view before touching AppKit again, and this is
/// the snapshot it carries across that hop — the same reason
/// `ExtensionQuickPickRequest` and `ExtensionInputBoxRequest` are structs
/// and not references to the live model.
public struct ExtensionStatusBarItemRequest: Sendable, Equatable {

    /// The key this item is put under, and the key `removeStatusBarItem`
    /// must be called with to remove the same item. Never shown to the
    /// extension — see `ExtensionStatusBarItem.internalID`'s own doc for how
    /// it differs from `id` below.
    public let internalID: String

    /// `StatusBarItem.id` (`vscode.d.ts:7564-7570`): the caller's id, or —
    /// quoting the property's own doc — "if no identifier was provided by
    /// the [...] method, the identifier will match the [...] extension
    /// identifier."
    public let id: String

    public let alignment: ExtensionStatusBarAlignment

    /// `StatusBarItem.priority` (`vscode.d.ts:7577-7581`): `number |
    /// undefined`. `nil` for "undefined", never coerced to `0` — see Ruling
    /// 8 in task 5.5c's brief for why a presenter must not either.
    public let priority: Double?

    public var name: String?
    public var text: String
    public var tooltip: String?
    public var color: String?
    public var backgroundColor: String?
    public var command: String?
    public var accessibilityLabel: String?
    public var accessibilityRole: String?

    /// Spelled out for `ExtensionQuickPickItem.init`'s reason: a `public`
    /// type's synthesised memberwise initialiser is `internal`, and this
    /// one's callers include a test module.
    public init(
        internalID: String,
        id: String,
        alignment: ExtensionStatusBarAlignment,
        priority: Double?,
        name: String?,
        text: String,
        tooltip: String?,
        color: String?,
        backgroundColor: String?,
        command: String?,
        accessibilityLabel: String?,
        accessibilityRole: String?
    ) {
        self.internalID = internalID
        self.id = id
        self.alignment = alignment
        self.priority = priority
        self.name = name
        self.text = text
        self.tooltip = tooltip
        self.color = color
        self.backgroundColor = backgroundColor
        self.command = command
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityRole = accessibilityRole
    }
}

/// Where a `vscode.window.createStatusBarItem` object actually puts
/// something on screen (or, in a test, records what it was asked to show).
///
/// **Task 5.5c builds this seam and not its view** — Ruling 1 and Ruling 2
/// of that task's brief name the eventual home
/// (`WindowFooterBar.trailingAccessories`, `WindowFooterBar.swift:35-46`)
/// without building it, on the same terms `ExtensionQuickPickPresenting`
/// was left for 5.5b-iv to conform to.
///
/// **Two operations, not four.** Upstream's `ExtHostStatusBarEntry` exposes
/// `show()`, `hide()`, a private debounced `update()`, and `dispose()`
/// (`extHostStatusBar.ts:233`, `:238`, `:244`, `:303`), but only two of those
/// are distinct *observable effects on a presenter*: putting an item up (or
/// refreshing what is already up) and taking one down. `hide()` and
/// `dispose()` both resolve to the same removal upstream — "There is no
/// `$hideEntry`", `extHostStatusBar.ts:242`'s `this.#proxy.$disposeEntry(...)`
/// is what `hide()` itself calls — and task 5.5c's Ruling 7 forbids
/// replicating `update()`'s debounce, so nothing here needs a fourth verb
/// for it either.
///
/// Both synchronous — nothing here awaits a user, unlike
/// `ExtensionQuickPickPresenting.presentQuickPick`.
///
/// `@MainActor`, matching every protocol and class in this directory.
@MainActor
public protocol ExtensionStatusBarPresenting: AnyObject {

    /// Puts `request` up, or refreshes it if `request.internalID` is already
    /// up. Called once per committed change (task 5.5c's Ruling 7: no
    /// coalescing) — never batched, and never called for an item that has not
    /// been shown (`ExtensionStatusBarItem.isVisible`) or has been disposed.
    func putOrUpdateStatusBarItem(_ request: ExtensionStatusBarItemRequest)

    /// Takes the item keyed by `internalID` down. Safe to call for an id the
    /// presenter never put up — `MainThreadWindow.hideStatusBarItem`'s own
    /// doc explains why an adaptor may call this before ever calling
    /// `putOrUpdateStatusBarItem`.
    func removeStatusBarItem(internalID: String)
}
