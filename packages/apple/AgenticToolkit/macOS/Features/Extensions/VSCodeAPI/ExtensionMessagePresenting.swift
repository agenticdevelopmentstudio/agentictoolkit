//
//  ExtensionMessagePresenting.swift
//  AgenticToolkit
//
//  Split out of MainThreadWindow.swift, which had grown past 2,800 lines.
//  The adaptor is still the only consumer; this is a file boundary, not a
//  tier one.
//

import Foundation

/// How urgently a `vscode.window.show*Message` call wants to be noticed.
public enum ExtensionMessageSeverity: Sendable, Equatable {
    case information, warning, error
}

/// One `vscode.window.show*Message` call, reduced to what a presenter needs
/// to show something and report back which button — if any — the user chose.
public struct ExtensionMessageRequest: Sendable {
    public let severity: ExtensionMessageSeverity
    public let message: String
    public let detail: String?
    public let isModal: Bool
    public let itemTitles: [String]

    /// Every index into `itemTitles` whose item carried a truthy
    /// `isCloseAffordance`, in item order — empty when none did. VS Code's
    /// rule for which item, if any, *is* the dismissal rather than one more
    /// button next to an implicit Cancel.
    ///
    /// A list rather than one index, because upstream keeps the flag on
    /// **every** item that set it. `extHostMessageService.ts` logs
    /// `Only one message item can have 'isCloseAffordance'` for the second
    /// and later ones but still pushes `isCloseAffordance: !!isCloseAffordance`
    /// for each, and `mainThreadMessageService.ts` then routes every flagged
    /// command to `cancelButton = button` — so each one is kept out of the
    /// ordinary button list and the **last** overwrites the cancel slot.
    /// Modelling only the first made a second flagged item render as an
    /// ordinary button, which upstream never does. See
    /// `NSAlertMessagePresenter.presentMessage(_:)` for what a presenter does
    /// with this.
    public let closeAffordanceIndices: [Int]
}

/// What `MainThreadWindow` depends on instead of AppKit directly, so the
/// adaptor's argument parsing and promise settlement are testable with no UI
/// — the same move `FileSystemServicing` made for `MainThreadWorkspace`'s
/// `fs`, and nearly the placement `ExtensionWorkspaceRoots` uses: declared
/// beside the one consumer that needs it, rather than anticipating a tier
/// split before a second conformer exists. Nearly, because this one sits in
/// a file of its own beside that consumer rather than inside it — the
/// adaptor outgrew carrying its own seams at 2,800 lines, and a file
/// boundary is not a tier boundary.
///
/// `@MainActor`, matching every protocol and class in this directory:
/// nothing here is ever read off the main actor.
@MainActor
public protocol ExtensionMessagePresenting: AnyObject {

    /// The index into `request.itemTitles` of the button the user chose, or
    /// `nil` if they dismissed it. Always `nil` when `itemTitles` is empty.
    func presentMessage(_ request: ExtensionMessageRequest) async -> Int?
}
