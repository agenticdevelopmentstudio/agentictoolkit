---
id: 5161980d-20b6-4779-867f-16ed45278a33
title: ExtensionInputBoxPresenting
domain: agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-input-box-presenting
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Data and validation types for one vscode.window.showInputBox call, and the
  @MainActor presenter protocol that shows the field and returns the result.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- input-box
- validation
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/extensions/ui/extension-input-box-view-controller
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionInputBoxPresenting.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a data/protocol declaration for one vscode.window.showInputBox request, not a visual component.

## States

Not applicable — this is a data/protocol declaration for one vscode.window.showInputBox request, not a visual component. The only lifecycle this file shapes is the per-call sequence a `presentInputBox` conformer runs (show, validate, accept or dismiss), which is captured under Behavioral Requirements rather than as a visual-state table.

## Accessibility

Not applicable — this is a data/protocol declaration for one vscode.window.showInputBox request, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-input-box-presenting-001 | severity-case-set, severity-case-naming, severity-conformances | Switch exhaustively over `ExtensionInputValidationSeverity` with no `default:` branch; compare `ExtensionInputValidationSeverity.error == ExtensionInputValidationSeverity.error` | The switch compiles over exactly three cases (`.information`, `.warning`, `.error`); the equality compiles and evaluates `true`. |
| extension-input-box-presenting-002 | severity-no-ignore-case | Reference `ExtensionInputValidationSeverity.ignore` | Fails to compile — no such case exists; "nothing to show" is represented by `Optional<ExtensionInputValidation>.none`, not a fourth case. |
| extension-input-box-presenting-003 | validation-fields, validation-public-init, validation-severity-always-attached | From a call site outside the declaring module, construct `ExtensionInputValidation(message: "too short", severity: .error)` | Construction succeeds via the explicit public initializer; the value's `message == "too short"` and `severity == .error`; no initializer path produces a `severity` with no `message`. |
| extension-input-box-presenting-004 | request-fields, request-public-init, request-value-non-optional | From outside the declaring module, construct `ExtensionInputBoxRequest(title: nil, prompt: nil, placeHolder: nil, value: "", valueSelection: nil, isPassword: false, ignoreFocusOut: false, isValidating: false)` | Construction succeeds via the explicit public initializer; `request.value == ""` (not `nil`), and all eight properties read back exactly as supplied. |
| extension-input-box-presenting-005 | request-value-selection-nil-means-whole-value, request-value-selection-empty-means-cursor-only | Construct two otherwise-identical requests differing only in `valueSelection`: one `nil`, one `3..<3` | The two requests are unequal by `Equatable`; per the documented contract, the `nil` request selects the whole pre-filled value and the `3..<3` request positions only the cursor at offset 3, selecting nothing. |
| extension-input-box-presenting-006 | request-value-selection-unit | A `value` of `"party ab"`-equivalent text containing one multi-code-unit emoji character followed by two ASCII characters (3 `Character`s, 4 UTF-16 code units), with `valueSelection` produced by `parseValueSelection(from:valueLength:)` for a JavaScript selection covering only the emoji | The resulting `valueSelection` is `0..<1` in `Character` terms (the emoji alone), not the UTF-16 span that would split the emoji's surrogate pair. |
| extension-input-box-presenting-007 | request-is-validating-independent-field | Construct one request with `isValidating: true` and a second, otherwise identical, with `isValidating: false`, without ever invoking a `validate` closure | The two requests differ only in `isValidating` and are unequal by `Equatable`; the field's value is unaffected by whether `validate` was ever called. |
| extension-input-box-presenting-008 | presenter-main-actor-isolation, presenter-single-requirement | Declare `final class StubInputBoxPresenter: ExtensionInputBoxPresenting` implementing only `presentInputBox(_:validate:)` | Compiles as a complete conformance with exactly one method; calling a member of the stub from outside the main actor without `await` fails to compile. |
| extension-input-box-presenting-009 | presenter-dismissal-vs-empty-value | A stub's `presentInputBox` returns `nil` on one call and `""` on a second call | The two `Optional<String>` results are distinguishable: `.none` (dismissed) versus `.some("")` (accepted empty). |
| extension-input-box-presenting-010 | presenter-error-severity-blocks-accept, validate-return-contract | A stub's `validate` closure answers `ExtensionInputValidation(message: "too short", severity: .error)` for candidate `"ab"` | The stub does not resolve `presentInputBox` with `"ab"` while `validate("ab")` answers `.error`; it resolves only once `validate` answers `nil` for the current value. |
| extension-input-box-presenting-011 | validate-nil-when-not-validating, validate-non-optional-parameter | A request with `isValidating == false` is presented; the harness calls the `validate` closure handed to `presentInputBox` with three different candidate strings | Every call to `validate` answers `nil` regardless of the candidate string, and the closure is invoked directly with no optional-chaining needed. |
| extension-input-box-presenting-012 | presenter-non-sendable | Attempt to store a value of a type conforming to `ExtensionInputBoxPresenting` into a generic context constrained to `Sendable`, with no `@unchecked Sendable` annotation | Fails to compile — the protocol carries no `Sendable` conformance. |
| extension-input-box-presenting-013 | cross-call-ordering-left-to-conformer, no-side-effects | Search `ExtensionInputBoxPresenting.swift` for `URLSession`, `FileManager`, `Process`, or any queue/ordering property | No matches — the file declares no side-effecting API and no cross-call ordering state of its own. |

## Edge Cases

- **Null/empty input**: `title`, `prompt`, and `placeHolder` MAY each be `nil` simultaneously while `value` is `""`; the type imposes no requirement that at least one of the four be non-empty (MUST).
- **Null/empty input**: `valueSelection == nil` and `value == ""` MAY co-occur; per **request-value-selection-nil-means-whole-value**, this selects the whole (empty) value, equivalent in effect to selecting nothing (MUST).
- **Boundary values**: `valueSelection`'s bounds MAY span the full length of `value` (`0..<value.count` in `Character`s); `ExtensionInputBoxRequest`'s own initializer performs no check that the bounds fall within `0...value.count` — that check belongs to `parseValueSelection(from:valueLength:)` in `MainThreadWindow.swift`, outside this file (MUST — see Design Decisions).
- **Boundary values**: a `Range<Int>` whose `lowerBound > upperBound` cannot be constructed in Swift at all (`Range.init` traps), so `ExtensionInputBoxRequest` can never hold a reversed `valueSelection` regardless of what validation any caller does or skips (MUST).
- **Concurrent access**: this file specifies no behavior for two `presentInputBox` calls in flight on the same conformer at once; per **cross-call-ordering-left-to-conformer**, a caller MUST NOT assume the second call queues, replaces, or is rejected — that policy is the conformer's own (MUST).
- **Error states**: `presentInputBox` declares no `throws` and no `Result` return; its sole non-success outcome is `nil` (dismissal), and `validate` likewise never throws — there is no error channel in this file for a conformer's own I/O or UI failures to surface through (MUST — see Design Decisions).
- **Error states**: `validate` returning a non-nil `ExtensionInputValidation` whose `severity` is `.information` or `.warning` MUST NOT block acceptance; only `.error` MUST, per **presenter-error-severity-blocks-accept** (MUST).
- **Offline or disconnected state**: not applicable to this file directly — it performs no network access itself; a conforming presenter and whatever `validate` closure a caller supplies are responsible for their own connectivity handling, if any, entirely outside this file's given source (MUST).

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

## Deep Linking

Not applicable: `ExtensionInputBoxPresenting.swift` defines no URL, route, or navigable destination — it is a data/protocol declaration for an in-process modal presentation, not a deep-linkable screen.

## Localization

Not applicable: `ExtensionInputBoxPresenting.swift` declares no string literal of its own — every `String` value (`title`, `prompt`, `placeHolder`, `value`, and `ExtensionInputValidation.message`) is supplied by a caller at construction time; there is nothing in this file for a String Catalog entry to localize.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none) | (none) | This file contains no string literal of its own. |

## Accessibility Options

Not applicable: `ExtensionInputBoxPresenting.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own; a conforming presenter's own UI is responsible for those settings outside this file.

## Feature Flags

Not applicable: the source declares no feature-flag key and no conditional feature-gating logic of any kind; every member is always available once a conforming instance exists.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind.

## Privacy

- **Data collected**: This file collects no data of its own; it carries whatever a caller already supplied — `value` (the text the user is typing, which MAY be a password or other secret when `isPassword == true`), `title`/`prompt`/`placeHolder` (caller-authored labels), and `message` (a validator-authored string). No field is derived, inferred, or read from any external source by this file.
- **Storage**: None. `ExtensionInputBoxRequest` and `ExtensionInputValidation` are value types with no persistence of their own; nothing in this file writes to disk, to `UserDefaults`, or to a cache.
- **Transmission**: None performed by this file. `value` (potentially a password, per `isPassword`) flows into and out of `presentInputBox` as a plain in-memory `String`; forwarding it to the extension that requested it, over any network or IPC channel, happens outside this file, in a conformer and in `MainThreadWindow.swift`.
- **Retention**: None. Every value this file declares is held only for the lifetime of the local variables that reference it; there is no cache, singleton, or static storage in the file.

## Logging

Not applicable: `ExtensionInputBoxPresenting.swift` contains no logging call and imports no logging framework — it declares data types and a protocol only. Logging for this seam, where it occurs, happens in `MainThreadWindow.swift`, outside this file's given source.

## Platform Notes

- **SwiftUI**: not applicable to this file — it imports only `Foundation` and has no SwiftUI dependency. A SwiftUI-based input surface would still consume `ExtensionInputBoxRequest`/`ExtensionInputValidation` and conform to `ExtensionInputBoxPresenting` unchanged; only the view layer calling it, outside this file, would differ.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionInputBoxPresenting.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. Its one consumer among the given sources is `MainThreadWindow`, itself `@MainActor`; the production conformer this file names directly, `ExtensionPickerPresenter`, is an AppKit type in the same feature area.
- **Compose**: model this as a Kotlin `enum class InputValidationSeverity { INFORMATION, WARNING, ERROR }`, a `data class InputValidation(val message: String, val severity: InputValidationSeverity)`, a `data class InputBoxRequest(val title: String?, val prompt: String?, val placeHolder: String?, val value: String = "", val valueSelection: IntRange?, val isPassword: Boolean, val ignoreFocusOut: Boolean, val isValidating: Boolean)`, and an `interface InputBoxPresenting { suspend fun presentInputBox(request: InputBoxRequest, validate: suspend (String) -> InputValidation?): String? }` confined to the main dispatcher, with `null` preserved as the dismissal signal distinct from an accepted empty string.
- **React/Web**: model the two data shapes as a discriminated union (`type InputValidationSeverity = "information" | "warning" | "error"`) plus an `InputValidation`/`InputBoxRequest` interface, and the protocol as an async function type — `type PresentInputBox = (request: InputBoxRequest, validate: (value: string) => Promise<InputValidation | null>) => Promise<string | null>` — choosing `null`, not `undefined`, as the dismissal sentinel so it stays distinguishable from an accepted empty string.
- **WinUI 3**: model `InputBoxRequest` and `InputValidation` as C# `record`s (`public sealed record InputBoxRequest(string? Title, string? Prompt, string? PlaceHolder, string Value, Range? ValueSelection, bool IsPassword, bool IgnoreFocusOut, bool IsValidating)`, `public sealed record InputValidation(string Message, InputValidationSeverity Severity)`), `InputValidationSeverity` as a C# `enum { Information, Warning, Error }`, and `ExtensionInputBoxPresenting` as `interface IInputBoxPresenting { Task<string?> PresentInputBoxAsync(InputBoxRequest request, Func<string, Task<InputValidation?>> validate, CancellationToken cancellationToken = default); }`, implemented by a `TextBox`/`PasswordBox`-hosting `ContentDialog` that switches control type the way this file's `isPassword` switches the AppKit field type. UI-thread confinement, the counterpart of `@MainActor`, is a `DispatcherQueue` check or `[MainThread]`-style convention rather than a compiler-enforced actor; `System.Range` (or a plain `(int Start, int End)` tuple) is the WinUI counterpart of `Range<Int>`, and a `Task<string?>` resolving to `null` is the counterpart of this file's nil-means-dismissed contract. C# has no equivalent of Swift's compiler-enforced non-optional closure parameter, so the `validate` delegate's "always returns null when not validating" contract (per **validate-nil-when-not-validating**) has to be enforced by convention and tests rather than by the type system.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionInputBoxPresenting.swift` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |

`separation-of-concerns` passes because the file declares only two value types and one protocol with no business logic, transport, UI, or persistence code of its own (see Overview and **no-side-effects**) — every side effect belongs to whatever conforms to `ExtensionInputBoxPresenting`. `unit-test-coverage` is partial: no test file among the given sources exercises `ExtensionInputValidationSeverity`, `ExtensionInputValidation`, or `ExtensionInputBoxRequest` directly, but the repository's `ExtensionPickerPresenterTests.swift`, `ExtensionInputBoxModelTests.swift`, and `ExtensionPickerWindowControllerTests.swift` construct and assert against real instances of these types while testing their consumers, so the shapes are exercised indirectly rather than by a dedicated unit test of this file's own contract (no test isolates, for example, the nil-versus-empty-string dismissal distinction or the no-ignore-case rule). `explicit-error-handling` passes because the file has no error channel to mishandle: dismissal is a documented `nil`, not a discarded error, and a validation problem surfaces as a typed `ExtensionInputValidation` value rather than being thrown and caught silently — there is nothing here for an error to be swallowed by.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
