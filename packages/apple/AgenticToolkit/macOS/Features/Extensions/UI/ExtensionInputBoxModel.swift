//
//  ExtensionInputBoxModel.swift
//  AgenticToolkit
//

import Foundation

/// What a `vscode.window.showInputBox` field shows, its latest validation
/// answer, and whether Return may accept it.
///
/// Deliberately free of AppKit, on `ExtensionQuickPickModel`'s precedent: the
/// accept/reject rule and the initial-selection arithmetic are worth a unit
/// test each, and neither needs a window server.
@MainActor
public final class ExtensionInputBoxModel {

    /// The request this model was built from. Public and not part of this
    /// task's literal API sketch, but necessary for the same reason
    /// `ExtensionQuickPickModel.request` is: `ExtensionInputBoxViewController`
    /// is initialised from a model alone (`init(model:)`) and has no other
    /// way to read `title`, `prompt`, `placeHolder`, or `isPassword`.
    public let request: ExtensionInputBoxRequest

    /// The field's current value. Setting it clears `validation` — a
    /// validation answer is about the value that produced it, and a stale
    /// `.error` left standing over new text would refuse a keystroke the
    /// extension never saw.
    public var value: String {
        didSet {
            validation = nil
            isValidating = false
        }
    }

    /// The latest validation answer, or nil when the value is valid or
    /// nothing has been validated yet.
    public private(set) var validation: ExtensionInputValidation?

    /// True between `beginValidating()` and the `recordValidation(_:)` that
    /// answers it — i.e. while the extension's `validateInput` is in flight
    /// for the current `value`. Cleared by a further edit, which supersedes
    /// the answer being waited on.
    ///
    /// It exists because `validation` alone cannot tell "valid" from "not
    /// asked yet": setting `value` clears `validation`, so between a
    /// keystroke and its answer the model looked exactly as it does for a
    /// value the validator approved, and `canAccept` said yes. Return
    /// pressed in that window accepted text the extension was in the middle
    /// of rejecting.
    public private(set) var isValidating = false

    public init(request: ExtensionInputBoxRequest) {
        self.request = request
        self.value = request.value
    }

    /// Note that `validateInput` has been asked about the current `value`
    /// and has not answered yet. Call it synchronously, before the `await`.
    public func beginValidating() {
        isValidating = true
    }

    /// Record the latest answer from `request`'s `validateInput`, or nil for
    /// "valid" / "nothing to show". Ends the `isValidating` window the
    /// matching `beginValidating()` opened.
    public func recordValidation(_ validation: ExtensionInputValidation?) {
        self.validation = validation
        isValidating = false
    }

    /// False exactly when the latest validation was `.error`. `.information`
    /// and `.warning` do not block acceptance.
    ///
    /// `InputBoxValidationMessage.severity`'s own doc (`vscode.d.ts:2221-2223`,
    /// measured against commit `3addbda6`): "**Note:** When using
    /// {@link InputBoxValidationSeverity.Error}, the user will not be able to
    /// accept the input (e.g., by pressing Enter). {@link
    /// InputBoxValidationSeverity.Info Info} and {@link
    /// InputBoxValidationSeverity.Warning Warning} severities will still
    /// allow the input to be accepted."
    ///
    /// A value still being validated is not acceptable *yet* — see
    /// `isValidating`. The controller remembers the Return and replays it
    /// when the answer lands, so a slow validator delays acceptance rather
    /// than swallowing the keystroke.
    public var canAccept: Bool {
        !isValidating && validation?.severity != .error
    }

    /// The selection to apply to the field on first show, clamped to the
    /// value's length, or nil meaning "select the whole value".
    ///
    /// `InputBoxOptions.valueSelection`'s own doc (`vscode.d.ts:2244-2249`,
    /// measured against commit `3addbda6`): "Defined as tuple of two number
    /// where the first is the inclusive start index and the second the
    /// exclusive end index. When `undefined` the whole pre-filled value will
    /// be selected, when empty (start equals end) only the cursor will be
    /// set, otherwise the defined range will be selected." 5.5b-iii already
    /// rejected a reversed or out-of-bounds pair at the JS boundary
    /// (`ExtensionInputBoxRequest.valueSelection`'s own doc), so what reaches
    /// here is a well-formed `Range<Int>?`; clamping is a second guard
    /// against a value that changed underneath, not a re-parse.
    public func initialSelection() -> Range<Int>? {
        guard let selection = request.valueSelection else { return nil }
        let length = value.count
        let lowerBound = min(selection.lowerBound, length)
        let upperBound = min(max(selection.upperBound, lowerBound), length)
        return lowerBound..<upperBound
    }

    /// `initialSelection()` (or, when that is nil, the whole value),
    /// converted from a Character-offset range to a UTF-16 `NSRange` —
    /// what `NSTextView.selectedRange` actually takes.
    ///
    /// `initialSelection()` counts Characters (`value.count`); `NSRange` is
    /// UTF-16 code units. The two agree for any value made only of BMP
    /// scalars, and diverge for anything else — an emoji, for instance, is
    /// one Character but two UTF-16 units, so a Character offset past it is
    /// short by one in UTF-16 terms. Feeding a Character offset straight to
    /// `NSRange(location:length:)` can land the selection one code unit into
    /// the wrong grapheme, or split a surrogate pair outright. Walking
    /// through `String.Index` — `NSRange(_:in:)` — is what keeps the two
    /// scales from being conflated.
    public func initialSelectionUTF16Range() -> NSRange {
        let characterRange = initialSelection() ?? 0..<value.count
        guard let lower = value.index(
                value.startIndex, offsetBy: characterRange.lowerBound, limitedBy: value.endIndex),
              let upper = value.index(
                lower, offsetBy: characterRange.count, limitedBy: value.endIndex) else {
            return NSRange(location: value.utf16.count, length: 0)
        }
        return NSRange(lower..<upper, in: value)
    }
}
