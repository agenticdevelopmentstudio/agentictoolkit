//
//  ExtensionQuickPickPresenting.swift
//  AgenticToolkit
//
//  Split out of MainThreadWindow.swift, which had grown past 2,800 lines.
//  The adaptor is still the only consumer; this is a file boundary, not a
//  tier one.
//

import Foundation

/// One item of a `vscode.window.showQuickPick` call, reduced to what a
/// presenter needs to render a row and report which rows the user chose.
///
/// **`iconPath`, `resourceUri` and `buttons` are deliberately not carried,**
/// and that is a decision rather than an omission. `buttons` because the
/// declaration says they are not rendered by this API at all — "Buttons are
/// only rendered when using a quick pick created by the
/// {@link window.createQuickPick createQuickPick} API. Buttons are not
/// rendered when using the {@link window.showQuickPick showQuickPick} API"
/// (`vscode.d.ts:1979-1981`). `iconPath` and `resourceUri` because nothing in
/// this repo resolves an extension-supplied icon path to an image, and a
/// field that is always dropped is worse than an absent one: it reads to the
/// next person as a capability that exists.
public struct ExtensionQuickPickItem: Sendable, Equatable {

    /// The row's text. The only property `QuickPickItem` declares
    /// non-optional (`vscode.d.ts:1907`), and the only one that applies to a
    /// separator.
    public let label: String

    /// Rendered less prominently on the same line (`vscode.d.ts:1929`), or
    /// `nil` when the item carried none — or carried one that was not a
    /// string, which is omitted rather than rejected, on the same terms
    /// `handleShowMessage` omits an unusable `detail`.
    public let description: String?

    /// Rendered less prominently on a separate line (`vscode.d.ts:1939`), or
    /// `nil` on the same terms as `description`.
    public let detail: String?

    /// The item's `kind` was `QuickPickItemKind.Separator` — the number `-1`
    /// (`vscode.d.ts:1886`) — so it is a visual grouping rather than a
    /// selectable row.
    ///
    /// Every other property of a separator is left at its default here,
    /// because the declaration says so: "The only property that applies is
    /// {@link QuickPickItem.label label}. All other properties on
    /// {@link QuickPickItem} will be ignored and have no effect"
    /// (`vscode.d.ts:1881-1884`).
    public let isSeparator: Bool

    /// The item carried a truthy `picked` (`vscode.d.ts:1966`): it should
    /// start out selected.
    ///
    /// **Carried truthfully whatever `canPickMany` says.** The declaration's
    /// rule — "This is only honored when the picker allows multiple
    /// selections" (`vscode.d.ts:1959`) — is the presenter's to apply, not
    /// the parser's. A parser that zeroed this out would leave the presenter
    /// unable to tell "the extension did not ask for this row" from "the
    /// extension asked and something upstream discarded it".
    public let isPicked: Bool

    /// The item carried a truthy `alwaysShow` (`vscode.d.ts:1974`): keep the
    /// row visible even when the user's filter text would exclude it.
    ///
    /// `MainThreadWindow` puts it on the request and stops there — filtering
    /// is the panel's job, and `ExtensionQuickPickModel.matches(_:filter:)`
    /// is where this flag is actually honoured.
    public let alwaysShow: Bool

    /// Spelled out rather than synthesised: this type is `public`, so the
    /// memberwise initialiser would be `internal` and a test in another
    /// module could not call it.
    public init(
        label: String,
        description: String?,
        detail: String?,
        isSeparator: Bool,
        isPicked: Bool,
        alwaysShow: Bool
    ) {
        self.label = label
        self.description = description
        self.detail = detail
        self.isSeparator = isSeparator
        self.isPicked = isPicked
        self.alwaysShow = alwaysShow
    }
}

/// One `vscode.window.showQuickPick` call, reduced to what a presenter needs
/// to show a picker and report back which rows — if any — the user chose.
public struct ExtensionQuickPickRequest: Sendable, Equatable {

    /// `QuickPickOptions.title` (`vscode.d.ts:1997`), or `nil`.
    public let title: String?

    /// `QuickPickOptions.placeHolder` (`vscode.d.ts:2012`) — placeholder text
    /// for the filter field — or `nil`.
    public let placeHolder: String?

    /// `QuickPickOptions.prompt` (`vscode.d.ts:2019`), or `nil`.
    ///
    /// **Carried, and read by nothing this task builds.** The declaration
    /// says it is "displayed below the input box and above the list of items"
    /// (`vscode.d.ts:2017`) and upstream forwards it to the renderer as one
    /// more field of the `$show` payload (`extHostQuickOpen.ts:72`); what a
    /// renderer does with it is the renderer's business, and this host has no
    /// renderer for it. The field records what the extension asked for.
    public let prompt: String?

    /// The items, in the order the extension supplied them — separators
    /// included, at their own positions. Indices into this array are the
    /// whole vocabulary `ExtensionQuickPickPresenting` answers in.
    public let items: [ExtensionQuickPickItem]

    /// `QuickPickOptions.canPickMany` (`vscode.d.ts:2030`): the user may
    /// accept more than one row, and "the result is an array of picks".
    public let canPickMany: Bool

    /// `QuickPickOptions.matchOnDescription` (`vscode.d.ts:2002`): include
    /// each item's `description` when filtering. Documented default `false`.
    public let matchOnDescription: Bool

    /// `QuickPickOptions.matchOnDetail` (`vscode.d.ts:2007`): include each
    /// item's `detail` when filtering. Documented default `false`.
    public let matchOnDetail: Bool

    /// `QuickPickOptions.ignoreFocusOut` (`vscode.d.ts:2025`): keep the
    /// picker open when focus moves elsewhere.
    public let ignoreFocusOut: Bool

    /// Spelled out for `ExtensionQuickPickItem.init`'s reason: a `public`
    /// type's synthesised memberwise initialiser is `internal`, and this
    /// one's callers include a test module.
    public init(
        title: String?,
        placeHolder: String?,
        prompt: String?,
        items: [ExtensionQuickPickItem],
        canPickMany: Bool,
        matchOnDescription: Bool,
        matchOnDetail: Bool,
        ignoreFocusOut: Bool
    ) {
        self.title = title
        self.placeHolder = placeHolder
        self.prompt = prompt
        self.items = items
        self.canPickMany = canPickMany
        self.matchOnDescription = matchOnDescription
        self.matchOnDetail = matchOnDetail
        self.ignoreFocusOut = ignoreFocusOut
    }
}

/// Where a `vscode.window.showQuickPick` call actually puts a picker on
/// screen (or, in a test, records what it was asked to show).
///
/// **A separate protocol from `ExtensionMessagePresenting`, deliberately.**
/// `NSAlertMessagePresenter` is the right conformer for a message and
/// the wrong one for a picker; one protocol carrying both members would force
/// it to implement a presentation it has no business showing. Interface
/// segregation, and the cost is that `MainThreadWindow.init` takes two
/// presenters rather than one.
///
/// Declared beside its one consumer rather than in a lower tier — the
/// placement `ExtensionMessagePresenting` already uses, and
/// `ExtensionWorkspaceRoots` (`MainThreadWorkspace.swift:28`) before it:
/// no tier split before a second consumer exists. Beside it in its own
/// file rather than inside it, which is the only thing that changed when
/// `MainThreadWindow.swift` was split.
///
/// `ExtensionPickerPresenter` is the production conformer, and it conforms to
/// `ExtensionInputBoxPresenting` as well — one panel serving both seams, which
/// is why neither was designed without the other in view.
///
/// `@MainActor`, matching every protocol and class in this directory.
@MainActor
public protocol ExtensionQuickPickPresenting: AnyObject {

    /// Shows `request` and answers **indices into `request.items`**.
    ///
    /// Indices, never labels. VS Code resolves `showQuickPick` with the
    /// original value the caller passed — `items[handle]` for single select,
    /// `handle.map(h => items[h])` for multi (`extHostQuickOpen.ts:125-131`)
    /// — so two items sharing a label have to stay distinguishable, and only
    /// a position distinguishes them.
    ///
    /// **`nil` means dismissed. An empty array does not.** With
    /// `request.canPickMany` a user can accept a selection of nothing, and
    /// upstream's `handle.map(…)` of an empty handle array resolves `[]`
    /// rather than `undefined` (`extHostQuickOpen.ts:128-129`). A conformer
    /// that answers `[]` for a dismissal tells the extension the user
    /// accepted an empty selection, which is a different answer.
    ///
    /// Single select answers a **one-element array**, not a bare `Int`: one
    /// return type for both modes, because `canPickMany` is a field of the
    /// request every conformer already reads, and two overloads would make
    /// each conformer spell the dismissal rule twice.
    ///
    /// - Parameters:
    ///   - request: What to show.
    ///   - onHighlight: Called with an index into `request.items` each time
    ///     the highlighted row changes. This is what VS Code's
    ///     `QuickPickOptions.onDidSelectItem` (`vscode.d.ts:2035`) is built
    ///     on, and upstream fires it from the widget's `onDidFocus`
    ///     (`mainThreadQuickOpen.ts:63-67`) rather than on acceptance. It may
    ///     be called any number of times, including zero, and must not be
    ///     called after `presentQuickPick` has returned.
    /// - Returns: The chosen indices, in the order the selection should be
    ///   reported to the extension, or `nil` if the picker was dismissed.
    func presentQuickPick(
        _ request: ExtensionQuickPickRequest,
        onHighlight: @escaping (Int) -> Void
    ) async -> [Int]?
}
