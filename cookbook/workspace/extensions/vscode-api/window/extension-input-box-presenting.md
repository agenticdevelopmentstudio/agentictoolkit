---
id: 5161980d-20b6-4779-867f-16ed45278a33
title: Extension Input Box Presenting
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/window/extension-input-box-presenting
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Data and validation types for one vscode.window.showInputBox call, and the
  thread-confined presenting role that shows the field and returns the result.
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
- agentictoolkit://cookbook/workspace/extensions/vscode-api/window/extension-input-box-view
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionInputBoxPresenting.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Extension Input Box Presenting

## Overview

This component declares the data and validation shapes for one
`vscode.window.showInputBox` call — a validation severity, a validation
result, and the input-box request itself — and the thread-confined
presenting role that an implementation conforms to in order to show a text
field for that request and report back what the user did. This role is
declared as its own role rather than an addition to the message-presenting
role or the quick-pick-presenting role, for interface-segregation reasons
(see Design Decisions). The picker presenter is named directly in this file
as the production implementation, serving this seam and the
quick-pick-presenting role both. The component itself performs no
networking, persistence, or UI construction — it is a pure data/role
declaration; every side effect belongs to an implementation.

## Behavioral Requirements

- **severity-case-set**: the validation severity type MUST declare exactly
  three cases — information, warning, and error — corresponding to VS
  Code's `InputBoxValidationSeverity` values `Info` (1), `Warning` (2), and
  `Error` (3).
- **severity-case-naming**: the three case identifiers MUST use this
  project's own lowercase-noun spelling (information, warning, error)
  rather than transcribing VS Code's `Info`/`Warning`/`Error` member names
  verbatim.
- **severity-no-ignore-case**: the validation severity type MUST NOT
  declare a case corresponding to VS Code's internal ignore-severity value;
  the "nothing to show" outcome MUST instead be represented by the absence
  of a validation result rather than by a fourth severity case.
- **severity-value-semantics**: the validation severity type MUST be safe
  to pass across concurrent contexts and MUST support equality comparison.
- **validation-fields**: the validation result type MUST expose exactly two
  fields, a message text and a severity value, and MUST be safe to pass
  across concurrent contexts and support equality comparison.
- **validation-explicit-construction**: the validation result type MUST
  expose a constructor naming both fields explicitly, so a value is
  directly constructible from outside the declaring module.
- **validation-severity-always-attached**: a severity value MUST only ever
  be attached to a validation result whose message exists; there MUST be
  no representation of a severity with nothing to show.
- **request-fields**: the input-box request type MUST expose exactly eight
  fields — an optional title, an optional prompt, an optional placeholder,
  a non-optional pre-fill value, an optional value-selection range, a
  password flag, a focus-out-ignoring flag, and a validating flag — and
  MUST be safe to pass across concurrent contexts and support equality
  comparison.
- **request-explicit-construction**: the input-box request type MUST expose
  a constructor naming all eight fields explicitly, for the same reason the
  validation result type does.
- **request-value-non-optional**: the pre-fill value field MUST be a
  non-optional string; a call that supplied no pre-fill value MUST be
  represented as an empty string, never as an absent value.
- **request-value-selection-absent-means-whole-value**: an absent
  value-selection MUST mean the whole pre-filled value is to be selected.
- **request-value-selection-empty-means-cursor-only**: a value-selection
  range whose lower and upper bounds are equal MUST mean only the cursor is
  to be positioned, with no text selected.
- **request-value-selection-unit**: the bounds of the value-selection range
  MUST be interpreted as user-perceived character (extended grapheme
  cluster) offsets into the pre-fill value, not UTF-16 code-unit or byte
  offsets, because the JavaScript values this field is built from count
  UTF-16 code units while this field counts user-perceived characters.
- **request-is-validating-independent-field**: the validating flag MUST
  record, as its own field, whether the originating call carried a
  validation function at all; it MUST NOT be derived by a presenter
  invoking the validate function once to see what it does.
- **presenter-thread-confined-isolation**: the presenting role MUST be
  confined to a single execution context and MUST be usable only by
  reference types; every implementation's stored-property access and the
  synchronous portion of every method MUST execute within that confined
  context.
- **presenter-single-requirement**: the presenting role MUST declare
  exactly one requirement: presenting an input box, given a request and a
  validate function, and returning an optional resulting string
  asynchronously.
- **presenter-dismissal-vs-empty-value**: presenting an input box MUST
  return an absent result to mean the user dismissed the input box, and
  MUST return an empty string only to mean the user affirmatively accepted
  an empty value; an implementation MUST NOT collapse these into the same
  return value.
- **presenter-error-severity-blocks-accept**: an implementation of the
  presenting role MUST NOT resolve the presentation with a value whose most
  recent call to validate answered a validation result with error severity.
- **validate-return-contract**: the validate function a presentation is
  given MUST answer an absent result to mean the candidate value is valid,
  and MUST answer a present validation result to report a message,
  blocking acceptance when its severity is error, per
  **presenter-error-severity-blocks-accept**.
- **validate-absent-when-not-validating**: when the request's validating
  flag is false, the validate function MUST always answer an absent result
  regardless of the candidate string passed to it.
- **validate-non-optional-parameter**: the validate parameter given to a
  presentation MUST always be a callable function, never itself absent,
  even for a request where the validating flag is false, so every
  implementation follows one calling code path rather than branching
  between an absent function and a present one.
- **presenter-isolation-not-concurrency-safe**: the presenting role MUST
  NOT be declared safe to pass across concurrent contexts; an
  implementation's confinement to its single execution context is enforced
  by the confinement declared on the role itself, not by any
  concurrency-safety marker.
- **cross-call-ordering-left-to-conformer**: the presenting role MUST
  impose no ordering, queuing, or replacement policy of its own for a
  second presentation call issued on the same implementation before a
  prior call's returned value has settled; that decision is left to each
  implementation. The picker presenter, the production implementation
  named in this file, states its own replacement rule for an overlapping
  request outside this component, rather than queuing.
- **no-side-effects**: none of the validation severity type, the
  validation result type, the input-box request type, or the presenting
  role's declared members perform file I/O, network access, process
  launch, or persistence of any kind; the component imports only
  foundational, non-UI, non-networking facilities and declares no
  side-effecting code of its own — every side effect belongs to whatever
  implements the presenting role.

## Appearance

Not applicable — this is a data/role declaration for one vscode.window.showInputBox request, not a visual component.

## States

Not applicable — this is a data/role declaration for one vscode.window.showInputBox request, not a visual component. The only lifecycle this component shapes is the per-call sequence an implementation runs (show, validate, accept or dismiss), which is captured under Behavioral Requirements rather than as a visual-state table.

## Accessibility

Not applicable — this is a data/role declaration for one vscode.window.showInputBox request, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-input-box-presenting-001 | severity-case-set, severity-case-naming, severity-value-semantics | Enumerate every case of the validation severity type with no fallback branch; compare an error-severity value against another error-severity value | Exactly three cases exist (information, warning, error) and every one is covered; the equality comparison evaluates true. |
| extension-input-box-presenting-002 | severity-no-ignore-case | Attempt to reference an ignore case on the validation severity type | No such case exists; "nothing to show" is represented by an absent validation result, not a fourth case. |
| extension-input-box-presenting-003 | validation-fields, validation-explicit-construction, validation-severity-always-attached | From outside the declaring component, construct a validation result with message "too short" and error severity | Construction succeeds via the explicit constructor; the value's message reads "too short" and its severity reads error; no construction path produces a severity with no message. |
| extension-input-box-presenting-004 | request-fields, request-explicit-construction, request-value-non-optional | From outside the declaring component, construct an input-box request with every optional field absent, the pre-fill value empty, and every flag false | Construction succeeds via the explicit constructor; the pre-fill value reads as an empty string (not absent), and all eight fields read back exactly as supplied. |
| extension-input-box-presenting-005 | request-value-selection-absent-means-whole-value, request-value-selection-empty-means-cursor-only | Construct two otherwise-identical requests differing only in value-selection: one absent, one spanning offset 3 to offset 3 | The two requests are unequal; per the documented contract, the request with an absent selection selects the whole pre-filled value, and the request with a zero-width selection at offset 3 positions only the cursor there, selecting nothing. |
| extension-input-box-presenting-006 | request-value-selection-unit | A pre-fill value containing one multi-code-unit emoji character followed by two plain characters (3 user-perceived characters, 4 UTF-16 code units), with a value-selection built for a selection covering only the emoji | The resulting value-selection spans offset 0 to offset 1 in user-perceived-character terms (the emoji alone), not the wider UTF-16 span that would split the emoji's underlying code-unit pair. |
| extension-input-box-presenting-007 | request-is-validating-independent-field | Construct one request with the validating flag true and a second, otherwise identical, with the validating flag false, without ever invoking a validate function | The two requests differ only in the validating flag and are unequal; the field's value is unaffected by whether validate was ever called. |
| extension-input-box-presenting-008 | presenter-thread-confined-isolation, presenter-single-requirement | Implement the presenting role with only the single required presentation method, as a reference type | The implementation is complete with exactly one method; invoking a member of it from outside the confined execution context without the required handoff fails. |
| extension-input-box-presenting-009 | presenter-dismissal-vs-empty-value | A stub implementation's presentation returns an absent result on one call and an empty string on a second call | The two results are distinguishable: absent (dismissed) versus present-and-empty (accepted empty). |
| extension-input-box-presenting-010 | presenter-error-severity-blocks-accept, validate-return-contract | A stub implementation's validate function answers a validation result of message "too short" and error severity for candidate "ab" | The stub does not resolve the presentation with "ab" while validate("ab") answers error severity; it resolves only once validate answers an absent result for the current value. |
| extension-input-box-presenting-011 | validate-absent-when-not-validating, validate-non-optional-parameter | A request with the validating flag false is presented; the harness calls the validate function handed to the presentation with three different candidate strings | Every call to validate answers an absent result regardless of the candidate string, and the function is invoked directly with no need to guard against it being absent. |
| extension-input-box-presenting-012 | presenter-isolation-not-concurrency-safe | Attempt to store an implementation of the presenting role into a context that requires concurrency-safe values, with no unsafe override annotation | Fails — the role carries no concurrency-safety guarantee. |
| extension-input-box-presenting-013 | cross-call-ordering-left-to-conformer, no-side-effects | Search the component's declaration for any networking, file-system, or process-launching call, or any queue/ordering property | No matches — the component declares no side-effecting API and no cross-call ordering state of its own. |

## Edge Cases

- **Null/empty input**: the title, prompt, and placeholder fields MAY each be absent simultaneously while the pre-fill value is an empty string; the type imposes no requirement that at least one of the four be non-empty (MUST).
- **Null/empty input**: an absent value-selection and an empty pre-fill value MAY co-occur; per **request-value-selection-absent-means-whole-value**, this selects the whole (empty) value, equivalent in effect to selecting nothing (MUST).
- **Boundary values**: the value-selection's bounds MAY span the full length of the pre-fill value; the input-box request's own constructor performs no check that the bounds fall within the pre-fill value's length — that check belongs to the mechanism that builds this field, outside this component (MUST — see Design Decisions).
- **Boundary values**: a value-selection range whose lower bound exceeds its upper bound cannot be constructed at all, so an input-box request can never hold a reversed value-selection regardless of what validation any caller does or skips (MUST).
- **Concurrent access**: this component specifies no behavior for two presentation calls in flight on the same implementation at once; per **cross-call-ordering-left-to-conformer**, a caller MUST NOT assume the second call queues, replaces, or is rejected — that policy is the implementation's own (MUST).
- **Error states**: presenting an input box declares no distinct error return; its sole non-success outcome is an absent result (dismissal), and validate likewise never signals an error — there is no error channel in this component for an implementation's own I/O or UI failures to surface through (MUST — see Design Decisions).
- **Error states**: validate returning a present validation result whose severity is information or warning MUST NOT block acceptance; only error severity MUST, per **presenter-error-severity-blocks-accept** (MUST).
- **Offline or disconnected state**: not applicable to this component directly — it performs no network access itself; an implementation of the presenting role and whatever validate function a caller supplies are responsible for their own connectivity handling, if any, entirely outside this component's given source (MUST).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | optional text | none (optional) | Label shown above the field, or absent. |
| `prompt` | optional text | none (optional) | Text shown underneath the field, or absent. |
| `placeHolder` | optional text | none (optional) | Placeholder text, or absent. |
| `value` | text | empty string | The pre-fill text — never absent. |
| `valueSelection` | optional integer range | absent (whole value selected) | Reduced to user-perceived-character offsets; an empty range positions the cursor only. |
| `isPassword` | boolean flag | false | Whether the field masks its content. |
| `ignoreFocusOut` | boolean flag | false | Whether losing focus dismisses the box. |
| `isValidating` | boolean flag | false | Whether the originating call supplied a validation function at all. |
| `validate` | async function from text to an optional validation result | none (required parameter of the presentation) | Runs the call's validation, if any; always answers an absent result when the validating flag is false. |

## Deep Linking

Not applicable: this component defines no URL, route, or navigable destination — it is a data/role declaration for an in-process modal presentation, not a deep-linkable screen.

## Localization

Not applicable: this component declares no string literal of its own — every text value (title, prompt, placeholder, pre-fill value, and validation message) is supplied by a caller at construction time; there is nothing in this component for a localization catalog entry to translate.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none) | (none) | This component contains no string literal of its own. |

## Accessibility Options

Not applicable: this component renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own; an implementation's own UI is responsible for those settings outside this component.

## Feature Flags

Not applicable: the component declares no feature-flag key and no conditional feature-gating logic of any kind; every member is always available once an implementing instance exists.

## Analytics

Not applicable: the component contains no analytics or event-emission call of any kind.

## Privacy

- **Data collected**: This component collects no data of its own; it carries whatever a caller already supplied — the pre-fill value (the text the user is typing, which MAY be a password or other secret when the password flag is set), the title/prompt/placeholder (caller-authored labels), and the validation message (a validator-authored string). No field is derived, inferred, or read from any external source by this component.
- **Storage**: None. The input-box request and validation result are plain data values with no persistence of their own; nothing in this component writes to disk, to local preference storage, or to a cache.
- **Transmission**: None performed by this component. The pre-fill value (potentially a password, per the password flag) flows into and out of the presentation as a plain in-memory string; forwarding it to the extension that requested it, over any network or IPC channel, happens outside this component, in an implementation and in the surrounding host.
- **Retention**: None. Every value this component declares is held only for the lifetime of the local variables that reference it; there is no cache, singleton, or static storage in the component.

## Logging

Not applicable: this component contains no logging call and imports no logging framework — it declares data types and a role only. Logging for this seam, where it occurs, happens in the surrounding host, outside this component's given source.

## Platform Notes

- **SwiftUI**: not applicable to this file — it imports only `Foundation` and has no SwiftUI dependency. A SwiftUI-based input surface would still consume `ExtensionInputBoxRequest`/`ExtensionInputValidation` and conform to `ExtensionInputBoxPresenting` unchanged; only the view layer calling it, outside this file, would differ.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionInputBoxPresenting.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. Per the file's own doc comment, it was split out of `MainThreadWindow.swift` once that file grew past 2,800 lines; `MainThreadWindow` remains its only consumer among the given sources, itself `@MainActor`; the production conformer this file names directly, `ExtensionPickerPresenter`, is an AppKit type in the same feature area. The three declared types are `ExtensionInputValidationSeverity` (an enum with cases `.information`, `.warning`, `.error`, conforming to `Sendable` and `Equatable`), `ExtensionInputValidation` (a `Sendable`, `Equatable` struct with `message: String` and `severity: ExtensionInputValidationSeverity`, plus a `public init(message:severity:)` because a `public` type's compiler-synthesized memberwise initializer is only `internal` and this type's callers include a test module), and `ExtensionInputBoxRequest` (a `Sendable`, `Equatable` struct with the same explicit-`public init` treatment, over eight properties: `title: String?`, `prompt: String?`, `placeHolder: String?`, `value: String`, `valueSelection: Range<Int>?`, `isPassword: Bool`, `ignoreFocusOut: Bool`, `isValidating: Bool`). `ExtensionInputBoxPresenting` itself is a class-bound (`AnyObject`), `@MainActor` protocol declaring exactly one requirement, `presentInputBox(_:validate:) async -> String?`, and is deliberately not declared `Sendable` — a conformer's main-actor confinement comes from the protocol's own `@MainActor` declaration, not from a `Sendable` conformance. `valueSelection`'s `Character`-offset bounds are produced by `parseValueSelection(from:valueLength:)` in `MainThreadWindow.swift`, whose own doc notes it "counts Characters" while the JavaScript values it is built from count UTF-16 code units; that function is also where a reversed or out-of-bounds selection is rejected, since `Range<Int>` traps at construction time on `lowerBound > upperBound` and so can never represent one. Enforcement of **presenter-error-severity-blocks-accept** belongs to whatever type builds a text field around this protocol (task 5.5b-iv), not to this file or to `MainThreadWindow`, which only carries the presenter's answer back to the extension.
- **Compose**: model this as a Kotlin `enum class InputValidationSeverity { INFORMATION, WARNING, ERROR }`, a `data class InputValidation(val message: String, val severity: InputValidationSeverity)`, a `data class InputBoxRequest(val title: String?, val prompt: String?, val placeHolder: String?, val value: String = "", val valueSelection: IntRange?, val isPassword: Boolean, val ignoreFocusOut: Boolean, val isValidating: Boolean)`, and an `interface InputBoxPresenting { suspend fun presentInputBox(request: InputBoxRequest, validate: suspend (String) -> InputValidation?): String? }` confined to the main dispatcher, with `null` preserved as the dismissal signal distinct from an accepted empty string.
- **React/Web**: model the two data shapes as a discriminated union (`type InputValidationSeverity = "information" | "warning" | "error"`) plus an `InputValidation`/`InputBoxRequest` interface, and the protocol as an async function type — `type PresentInputBox = (request: InputBoxRequest, validate: (value: string) => Promise<InputValidation | null>) => Promise<string | null>` — choosing `null`, not `undefined`, as the dismissal sentinel so it stays distinguishable from an accepted empty string.
- **WinUI 3**: model `InputBoxRequest` and `InputValidation` as C# `record`s (`public sealed record InputBoxRequest(string? Title, string? Prompt, string? PlaceHolder, string Value, Range? ValueSelection, bool IsPassword, bool IgnoreFocusOut, bool IsValidating)`, `public sealed record InputValidation(string Message, InputValidationSeverity Severity)`), `InputValidationSeverity` as a C# `enum { Information, Warning, Error }`, and `ExtensionInputBoxPresenting` as `interface IInputBoxPresenting { Task<string?> PresentInputBoxAsync(InputBoxRequest request, Func<string, Task<InputValidation?>> validate, CancellationToken cancellationToken = default); }`, implemented by a `TextBox`/`PasswordBox`-hosting `ContentDialog` that switches control type the way this file's `isPassword` switches the AppKit field type. UI-thread confinement, the counterpart of `@MainActor`, is a `DispatcherQueue` check or `[MainThread]`-style convention rather than a compiler-enforced actor; `System.Range` (or a plain `(int Start, int End)` tuple) is the WinUI counterpart of `Range<Int>`, and a `Task<string?>` resolving to `null` is the counterpart of this file's nil-means-dismissed contract. C# has no equivalent of Swift's compiler-enforced non-optional closure parameter, so the `validate` delegate's "always returns null when not validating" contract (per **validate-absent-when-not-validating**) has to be enforced by convention and tests rather than by the type system.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/window/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
