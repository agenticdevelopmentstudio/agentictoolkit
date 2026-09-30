<!-- leaf: implement-extension-host-vs-presenting/code-api-extension-input-box-presenting · source: extension-host-vs-code-api-extension-input-box-presenting.md -->

**Rules** (cite as `implement-extension-host-vs-presenting/code-api-extension-input-box-presenting#<slug>`):

- `severity-case-set` MUST
- `severity-case-naming` MUST
- `severity-no-ignore-case` MUST
- `severity-conformances` MUST
- `validation-fields` MUST
- `validation-public-init` MUST
- `validation-severity-always-attached` MUST
- `request-fields` MUST
- `request-public-init` MUST
- `request-value-non-optional` MUST
- `request-value-selection-nil-means-whole-value` MUST
- `request-value-selection-empty-means-cursor-only` MUST
- `request-value-selection-unit` MUST
- `request-is-validating-independent-field` MUST
- `presenter-main-actor-isolation` MUST
- `presenter-single-requirement` MUST
- `presenter-dismissal-vs-empty-value` MUST
- `presenter-error-severity-blocks-accept` MUST
- `validate-return-contract` MUST
- `validate-nil-when-not-validating` MUST
- `validate-non-optional-parameter` MUST
- `presenter-non-sendable` MUST
- `cross-call-ordering-left-to-conformer` MUST
- `data-collected` MAY — This file collects no data of its own; it carries whatever a caller already supplied — value (the text the user is …

# ExtensionInputBoxPresenting

## Overview

`ExtensionInputBoxPresenting` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionInputBoxPresenting.swift`) declares the data and validation shapes for one `vscode.window.showInputBox` call — `ExtensionInputValidationSeverity`, `ExtensionInputValidation`, and `ExtensionInputBoxRequest` — and the `@MainActor` protocol, `ExtensionInputBoxPresenting`, that a presenter conforms to in order to show a text field for that request and report back what the user did. Per the file's own doc comment, it was split out of `MainThreadWindow.swift` once that file grew past 2,800 lines; `MainThreadWindow` remains its only consumer among the given sources. `ExtensionInputBoxPresenting` is declared as its own protocol rather than an addition to `ExtensionMessagePresenting` or `ExtensionQuickPickPresenting`, for the interface-segregation reasoning this file's own doc comment points to in `ExtensionQuickPickPresenting`'s doc (see Design Decisions). `ExtensionPickerPresenter` is named directly in this file as the production conformer, serving this seam and `ExtensionQuickPickPresenting` both. The file itself performs no networking, persistence, or UI construction — it is a pure data/protocol declaration; every side effect belongs to a conformer.

## Behavioral Requirements

- **severity-case-set**: `ExtensionInputValidationSeverity` MUST declare exactly three cases — `.information`, `.warning`, and `.error` — corresponding to upstream `InputBoxValidationSeverity`'s `Info` (1), `Warning` (2), and `Error` (3).
- **severity-case-naming**: The three case identifiers MUST use this directory's own lowercase-noun spelling (`.information`, `.warning`, `.error`) rather than transcribing upstream's `Info`/`Warning`/`Error` member names verbatim.
- **severity-no-ignore-case**: `ExtensionInputValidationSeverity` MUST NOT declare a case corresponding to upstream's internal `Severity.Ignore` value; the "nothing to show" outcome MUST instead be represented by the absence of an `ExtensionInputValidation` value (`nil`) rather than by a fourth severity case.
- **severity-conformances**: `ExtensionInputValidationSeverity` MUST conform to `Sendable` and `Equatable`.
- **validation-fields**: `ExtensionInputValidation` MUST expose exactly two stored properties, `message: String` and `severity: ExtensionInputValidationSeverity`, and MUST conform to `Sendable` and `Equatable`.
- **validation-public-init**: `ExtensionInputValidation` MUST expose a `public init(message:severity:)` that sets both properties directly, because a `public` type's compiler-synthesized memberwise initializer is `internal` and this type's callers include a test module.
- **validation-severity-always-attached**: A severity value MUST only ever be attached to an `ExtensionInputValidation` whose `message` exists; there MUST be no representation of a severity with nothing to show.
- **request-fields**: `ExtensionInputBoxRequest` MUST expose exactly eight stored properties — `title: String?`, `prompt: String?`, `placeHolder: String?`, `value: String`, `valueSelection: Range<Int>?`, `isPassword: Bool`, `ignoreFocusOut: Bool`, and `isValidating: Bool` — and MUST conform to `Sendable` and `Equatable`.
- **request-public-init**: `ExtensionInputBoxRequest` MUST expose a `public init` naming all eight properties explicitly, for the same reason `ExtensionInputValidation` does.
- **request-value-non-optional**: `value` MUST be a non-optional `String`; a call that supplied no pre-fill value MUST be represented as `value == ""`, never as `nil`.
- **request-value-selection-nil-means-whole-value**: `valueSelection == nil` MUST mean the whole pre-filled `value` is to be selected.
- **request-value-selection-empty-means-cursor-only**: A `valueSelection` whose `lowerBound == upperBound` MUST mean only the cursor is to be positioned, with no text selected.
- **request-value-selection-unit**: The `Int` bounds of `valueSelection` MUST be interpreted as `Character` (extended grapheme cluster) offsets into `value`, not UTF-16 code-unit or byte offsets — traced to `parseValueSelection(from:valueLength:)` in `MainThreadWindow.swift`, the function this file's own doc comment names as the producer of this field, whose own doc states that this field "counts Characters" while the JavaScript values it is built from count UTF-16 code units.
- **request-is-validating-independent-field**: `isValidating` MUST record, as its own stored field, whether the originating call carried a `validateInput` function at all; it MUST NOT be derived by a presenter invoking the `validate` closure once to see what it does.
- **presenter-main-actor-isolation**: `ExtensionInputBoxPresenting` MUST be declared `@MainActor` and MUST be class-bound (`AnyObject`); every conformer's stored property access and the synchronous portion of every method MUST execute on the main actor.
- **presenter-single-requirement**: `ExtensionInputBoxPresenting` MUST declare exactly one requirement, `presentInputBox(_:validate:) async -> String?`.
- **presenter-dismissal-vs-empty-value**: `presentInputBox` MUST return `nil` to mean the user dismissed the input box, and MUST return an empty string only to mean the user affirmatively accepted an empty value; a conformer MUST NOT collapse these into the same return value.
- **presenter-error-severity-blocks-accept**: A conformer of `ExtensionInputBoxPresenting` MUST NOT resolve `presentInputBox` with a value whose most recent call to `validate` answered an `ExtensionInputValidation` with `severity == .error`.
- **validate-return-contract**: The `validate` closure `presentInputBox` is given MUST answer `nil` to mean the candidate value is valid, and MUST answer a non-nil `ExtensionInputValidation` to report a message, blocking acceptance when its severity is `.error` per **presenter-error-severity-blocks-accept**.
- **validate-nil-when-not-validating**: When `request.isValidating == false`, `validate` MUST always answer `nil` regardless of the candidate string passed to it.
- **validate-non-optional-parameter**: `presentInputBox`'s `validate` parameter MUST be declared as a non-optional closure, even for a request where `request.isValidating == false`, so every conformer implements one closure-calling code path rather than branching on an optional closure plus a non-optional one.
- **presenter-non-sendable**: `ExtensionInputBoxPresenting` MUST NOT be declared `Sendable`; a conformer instance's confinement to the main actor is enforced by the `@MainActor` declaration on the protocol itself, not by a `Sendable` conformance.
- **cross-call-ordering-left-to-conformer**: `ExtensionInputBoxPresenting` MUST impose no ordering, queuing, or replacement policy of its own for a second `presentInputBox` call issued on the same conformer before a prior call's returned value has settled; that decision is left to each conformer. The production conformer named in this file, `ExtensionPickerPresenter`, states its own replacement rule for an overlapping request in a doc comment outside this file, rather than queuing.
- **no-side-effects**: None of `ExtensionInputValidationSeverity`, `ExtensionInputValidation`, `ExtensionInputBoxRequest`, or `ExtensionInputBoxPresenting`'s declared members perform file I/O, network access, process launch, or persistence of any kind; the file imports only `Foundation` and declares no side-effecting code of its own — every side effect belongs to whatever conforms to `ExtensionInputBoxPresenting`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | `String?` | none (optional) | Label shown above the field, or absent. |
| `prompt` | `String?` | none (optional) | Text shown underneath the field, or absent. |
| `placeHolder` | `String?` | none (optional) | Placeholder text, or absent. |
| `value` | `String` | `""` | The pre-fill text — never optional. |
| `valueSelection` | `Range<Int>?` | `nil` (whole value selected) | Reduced to `Character` offsets; an empty range positions the cursor only. |
| `isPassword` | `Bool` | `false` | Whether the field masks its content. |
| `ignoreFocusOut` | `Bool` | `false` | Whether losing focus dismisses the box. |
| `isValidating` | `Bool` | `false` | Whether the originating call supplied a validation function at all. |
| `validate` | `(String) async -> ExtensionInputValidation?` | none (required parameter of `presentInputBox`) | Runs the call's validation, if any; always answers `nil` when `isValidating == false`. |

## Privacy

- **Data collected**: This file collects no data of its own; it carries whatever a caller already supplied — `value` (the text the user is typing, which MAY be a password or other secret when `isPassword == true`), `title`/`prompt`/`placeHolder` (caller-authored labels), and `message` (a validator-authored string). No field is derived, inferred, or read from any external source by this file.
- **Storage**: None. `ExtensionInputBoxRequest` and `ExtensionInputValidation` are value types with no persistence of their own; nothing in this file writes to disk, to `UserDefaults`, or to a cache.
- **Transmission**: None performed by this file. `value` (potentially a password, per `isPassword`) flows into and out of `presentInputBox` as a plain in-memory `String`; forwarding it to the extension that requested it, over any network or IPC channel, happens outside this file, in a conformer and in `MainThreadWindow.swift`.
- **Retention**: None. Every value this file declares is held only for the lifetime of the local variables that reference it; there is no cache, singleton, or static storage in the file.

