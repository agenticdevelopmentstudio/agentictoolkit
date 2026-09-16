//
//  ExtensionInputBoxPresenting.swift
//  AgenticToolkit
//
//  Split out of MainThreadWindow.swift, which had grown past 2,800 lines.
//  The adaptor is still the only consumer; this is a file boundary, not a
//  tier one.
//

import Foundation

/// How urgently a `vscode.window.showInputBox` validation message wants to be
/// noticed — `InputBoxValidationSeverity` (`vscode.d.ts:2194-2207`, measured
/// against commit `3addbda6`): `Info = 1` (`:2198`), `Warning = 2` (`:2202`),
/// `Error = 3` (`:2206`).
///
/// `case information`, not `.info` — matching this directory's own
/// `ExtensionMessageSeverity` spelling rather than the declaration's member
/// name, for the same reason that type already made: a Swift enum case name
/// is this codebase's word, not a transcription of upstream's.
///
/// **No `.ignore` case.** `Severity.Ignore` exists on upstream's internal
/// `$validateInput` bridge (`extHostQuickOpen.ts:187-189`) for a validation
/// result whose `severity` matched none of the three and whose `message` was
/// also empty — upstream's way of saying "nothing to show." This type has no
/// member for that because `MainThreadWindow.inputValidation(from:)`
/// answers `nil` for that same case instead: a severity is only ever
/// attached to a message that exists, so "nothing to show" is the absence
/// of an `ExtensionInputValidation` altogether, not a fourth severity.
public enum ExtensionInputValidationSeverity: Sendable, Equatable {
    case information, warning, error
}

/// One validation result from a `vscode.window.showInputBox` call's
/// `validateInput`, reduced to what a presenter needs to show a message and
/// decide whether to keep accepting the current value.
///
/// `InputBoxValidationMessage` (`vscode.d.ts:2212-2225`, measured against
/// commit `3addbda6`). **A presenter must not accept a value whose most
/// recent validation carried `.error`:** "When using
/// {@link InputBoxValidationSeverity.Error}, the user will not be able to
/// accept the input (e.g., by pressing Enter)" (`vscode.d.ts:2221-2223`).
/// Enforcing that belongs to whatever type builds an `NSTextField` around
/// this — task 5.5b-iv — not to this type or to `MainThreadWindow`, which
/// only carries the presenter's answer back to the extension.
public struct ExtensionInputValidation: Sendable, Equatable {
    public let message: String
    public let severity: ExtensionInputValidationSeverity

    /// Spelled out rather than synthesised, for `ExtensionQuickPickItem.init`'s
    /// reason: a `public` type's memberwise initialiser is `internal`, and
    /// this one's callers include a test module.
    public init(message: String, severity: ExtensionInputValidationSeverity) {
        self.message = message
        self.severity = severity
    }
}

/// One `vscode.window.showInputBox` call, reduced to what a presenter needs
/// to show a text field and report back the value the user accepted.
///
/// `InputBoxOptions` (`vscode.d.ts:2231-2282`, measured against commit
/// `3addbda6`).
public struct ExtensionInputBoxRequest: Sendable, Equatable {

    /// `InputBoxOptions.title` (`vscode.d.ts:2236`), or `nil`.
    public let title: String?

    /// `InputBoxOptions.prompt` (`vscode.d.ts:2251-2254`) — "The text to
    /// display underneath the input box" — or `nil`.
    public let prompt: String?

    /// `InputBoxOptions.placeHolder` (`vscode.d.ts:2259`), or `nil`.
    public let placeHolder: String?

    /// `InputBoxOptions.value` (`vscode.d.ts:2241`): the value to pre-fill.
    /// **Non-optional, defaulting to `""`** — every consumer of this request
    /// seeds a text field with a `String`, never an `Optional` to unwrap
    /// first, and `""` is the spelling that means "an empty box."
    public let value: String

    /// `InputBoxOptions.valueSelection` (`vscode.d.ts:2243-2249`): "Defined as
    /// tuple of two number where the first is the inclusive start index and
    /// the second the exclusive end index." `nil` means "the whole
    /// pre-filled value will be selected"; an empty range (`start == end`)
    /// means "only the cursor will be set" — both the declaration's own
    /// words, and both left to the presenter to act on, since carrying them
    /// as anything but this range would force this type to guess what
    /// `value.count` is going to be by the time a presenter reads it.
    ///
    /// A `Range<Int>`, not the declaration's tuple: parsing rejects a pair
    /// this type could not otherwise represent — reversed, negative, or past
    /// `value`'s end — rather than trapping when a presenter eventually tried
    /// to build a `Range` from a raw tuple. See `parseValueSelection(from:valueLength:)`.
    public let valueSelection: Range<Int>?

    /// `InputBoxOptions.password` (`vscode.d.ts:2261-2264`): "Controls if a
    /// password input is shown."
    public let isPassword: Bool

    /// `InputBoxOptions.ignoreFocusOut` (`vscode.d.ts:2270`).
    public let ignoreFocusOut: Bool

    /// Whether this call carried a `validateInput` function at all.
    ///
    /// A separate stored field rather than something a presenter derives
    /// from the `validate` closure `ExtensionInputBoxPresenting` hands it
    /// alongside this request — the two are separate parameters precisely so
    /// a presenter can decide whether to call `validate` at all without
    /// having to invoke it once to find out, on the same terms upstream's
    /// own `typeof this._validateInput === 'function'`
    /// (`extHostQuickOpen.ts:156`) is computed once and threaded through
    /// rather than re-derived from the function reference each time.
    public let isValidating: Bool

    /// Spelled out for `ExtensionQuickPickItem.init`'s reason: a `public`
    /// type's synthesised memberwise initialiser is `internal`, and this
    /// one's callers include a test module.
    public init(
        title: String?,
        prompt: String?,
        placeHolder: String?,
        value: String,
        valueSelection: Range<Int>?,
        isPassword: Bool,
        ignoreFocusOut: Bool,
        isValidating: Bool
    ) {
        self.title = title
        self.prompt = prompt
        self.placeHolder = placeHolder
        self.value = value
        self.valueSelection = valueSelection
        self.isPassword = isPassword
        self.ignoreFocusOut = ignoreFocusOut
        self.isValidating = isValidating
    }
}

/// Where a `vscode.window.showInputBox` call actually puts a text field on
/// screen (or, in a test, records what it was asked to show).
///
/// A third presenter rather than a member added to `ExtensionMessagePresenting`
/// or `ExtensionQuickPickPresenting` — see `ExtensionQuickPickPresenting`'s
/// own doc for the interface-segregation reasoning that already governs this
/// adaptor's other seam.
///
/// `ExtensionPickerPresenter` is the production conformer, serving this seam
/// and `ExtensionQuickPickPresenting` both.
///
/// `@MainActor`, matching every protocol and class in this directory.
@MainActor
public protocol ExtensionInputBoxPresenting: AnyObject {

    /// Shows `request` and answers the value the user accepted.
    ///
    /// **`nil` means dismissed. An empty string does not** — the user can
    /// accept an empty value, and that is a different answer from never
    /// answering at all, on the same terms `ExtensionQuickPickPresenting`
    /// draws between a dismissal and an accepted empty selection.
    ///
    /// - Parameters:
    ///   - request: What to show.
    ///   - validate: Runs `request`'s `validateInput`, if it has one, against
    ///     a candidate value, and answers `nil` for "valid" — following
    ///     `InputBoxOptions.validateInput`'s own contract: "Return
    ///     `undefined`, `null`, or the empty string when 'value' is valid"
    ///     (`vscode.d.ts:2278`, measured against commit `3addbda6`). **A
    ///     conformer must not accept a value whose most recent call to
    ///     `validate` answered `.error` severity** —
    ///     `InputBoxValidationMessage`'s own doc: "the user will not be able
    ///     to accept the input (e.g., by pressing Enter)" for that severity
    ///     (`vscode.d.ts:2221-2223`). When `request.isValidating` is `false`,
    ///     `validate` always answers `nil`, and a conformer has no reason to
    ///     call it — but it is not made optional, so every conformer handles
    ///     one shape rather than two.
    /// - Returns: The accepted value, or `nil` if dismissed.
    func presentInputBox(
        _ request: ExtensionInputBoxRequest,
        validate: @escaping (String) async -> ExtensionInputValidation?
    ) async -> String?
}
