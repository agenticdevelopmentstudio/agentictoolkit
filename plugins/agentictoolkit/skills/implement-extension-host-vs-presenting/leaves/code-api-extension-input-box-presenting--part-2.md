<!-- leaf: implement-extension-host-vs-presenting/code-api-extension-input-box-presenting--part-2 · source: extension-host-vs-code-api-extension-input-box-presenting.md -->

# ExtensionInputBoxPresenting — continued (part 2)

## Platform Notes

- **SwiftUI**: not applicable to this file — it imports only `Foundation` and has no SwiftUI dependency. A SwiftUI-based input surface would still consume `ExtensionInputBoxRequest`/`ExtensionInputValidation` and conform to `ExtensionInputBoxPresenting` unchanged; only the view layer calling it, outside this file, would differ.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionInputBoxPresenting.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. Its one consumer among the given sources is `MainThreadWindow`, itself `@MainActor`; the production conformer this file names directly, `ExtensionPickerPresenter`, is an AppKit type in the same feature area.
- **Compose**: model this as a Kotlin `enum class InputValidationSeverity { INFORMATION, WARNING, ERROR }`, a `data class InputValidation(val message: String, val severity: InputValidationSeverity)`, a `data class InputBoxRequest(val title: String?, val prompt: String?, val placeHolder: String?, val value: String = "", val valueSelection: IntRange?, val isPassword: Boolean, val ignoreFocusOut: Boolean, val isValidating: Boolean)`, and an `interface InputBoxPresenting { suspend fun presentInputBox(request: InputBoxRequest, validate: suspend (String) -> InputValidation?): String? }` confined to the main dispatcher, with `null` preserved as the dismissal signal distinct from an accepted empty string.
- **React/Web**: model the two data shapes as a discriminated union (`type InputValidationSeverity = "information" | "warning" | "error"`) plus an `InputValidation`/`InputBoxRequest` interface, and the protocol as an async function type — `type PresentInputBox = (request: InputBoxRequest, validate: (value: string) => Promise<InputValidation | null>) => Promise<string | null>` — choosing `null`, not `undefined`, as the dismissal sentinel so it stays distinguishable from an accepted empty string.
- **WinUI 3**: model `InputBoxRequest` and `InputValidation` as C# `record`s (`public sealed record InputBoxRequest(string? Title, string? Prompt, string? PlaceHolder, string Value, Range? ValueSelection, bool IsPassword, bool IgnoreFocusOut, bool IsValidating)`, `public sealed record InputValidation(string Message, InputValidationSeverity Severity)`), `InputValidationSeverity` as a C# `enum { Information, Warning, Error }`, and `ExtensionInputBoxPresenting` as `interface IInputBoxPresenting { Task<string?> PresentInputBoxAsync(InputBoxRequest request, Func<string, Task<InputValidation?>> validate, CancellationToken cancellationToken = default); }`, implemented by a `TextBox`/`PasswordBox`-hosting `ContentDialog` that switches control type the way this file's `isPassword` switches the AppKit field type. UI-thread confinement, the counterpart of `@MainActor`, is a `DispatcherQueue` check or `[MainThread]`-style convention rather than a compiler-enforced actor; `System.Range` (or a plain `(int Start, int End)` tuple) is the WinUI counterpart of `Range<Int>`, and a `Task<string?>` resolving to `null` is the counterpart of this file's nil-means-dismissed contract. C# has no equivalent of Swift's compiler-enforced non-optional closure parameter, so the `validate` delegate's "always returns null when not validating" contract (per **validate-nil-when-not-validating**) has to be enforced by convention and tests rather than by the type system.

## Design Decisions

**Decision**: `ExtensionInputBoxRequest.valueSelection` is declared as an optional `Range<Int>` rather than upstream's raw two-number tuple.
**Rationale**: per the source's own doc comment, a `Range` "rejects a pair this type could not otherwise represent — reversed, negative, or past value's end — rather than trapping when a presenter eventually tried to build a Range from a raw tuple"; pushing the rejection to construction time, in `parseValueSelection(from:valueLength:)` outside this file, means every consumer of `ExtensionInputBoxRequest` already holds a valid `Range` and never has to re-validate it.
**Approved**: pending

**Decision**: `ExtensionInputValidationSeverity` has no case corresponding to upstream's internal `Severity.Ignore`.
**Rationale**: per the source's own doc comment, a severity is only ever attached to a message that exists in this type's model, so "nothing to show" is represented by the complete absence of an `ExtensionInputValidation` value rather than by a fourth severity case that would also require an empty message.
**Approved**: pending

**Decision**: The severity cases are spelled `.information`, `.warning`, `.error`, matching this directory's own `ExtensionMessageSeverity` spelling rather than transcribing upstream's `Info`/`Warning`/`Error` member names verbatim.
**Rationale**: stated directly in the source's own doc comment — a Swift enum case name is this codebase's word, not a transcription of upstream's.
**Approved**: pending

**Decision**: `ExtensionInputBoxPresenting` is declared as its own protocol rather than as an additional method on `ExtensionMessagePresenting` or `ExtensionQuickPickPresenting`.
**Rationale**: the source's own doc comment points to `ExtensionQuickPickPresenting`'s doc for the interface-segregation reasoning that already governs this adaptor's other seam — a conformer right for one presentation is often the wrong one for another, and one protocol carrying every seam's members would force every conformer to implement presentations it has no business showing; the cost, paid at `MainThreadWindow.init`, is one presenter parameter per seam rather than one shared parameter.
**Approved**: pending

**Decision**: `ExtensionInputBoxPresenting` states that a conformer must not accept a value whose most recent call to `validate` answered `.error` severity, but enforces nothing itself.
**Rationale**: per the source's own doc comment, enforcing that rule belongs to whatever type builds a text field around this — task 5.5b-iv, not this type or `MainThreadWindow`, which only carries the presenter's answer back to the extension; the protocol states the contract once so every conformer is held to the same rule, while leaving the UI-level mechanics to each conformer.
**Approved**: pending
