---
id: 6fa79a51-8e62-4a99-8979-c93a4269dac8
title: Diagnostic Types
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/languages/diagnostic-types
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Installs vscode.DiagnosticSeverity, DiagnosticTag, DiagnosticRelatedInformation
  and Diagnostic in the extension's script context, and bridges instances to and
  from host code.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- diagnostics
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/DiagnosticTypes.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/DiagnosticTypesTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/TextGeometry.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/Uri.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Diagnostic Types

## Overview

This component gives the extension host's embedded script context real, `instanceof`-checkable implementations of four `vscode` API declarations — `vscode.DiagnosticSeverity`, `vscode.DiagnosticTag`, `vscode.DiagnosticRelatedInformation` and `vscode.Diagnostic` (`vscode.d.ts`, `:7053-7072`, `:7077-7096` and `:7102-7161` at the pinned commit named in the component's own header) — and the host-side mirror types and bidirectional bridging functions that let host code read an extension-built `Diagnostic` back into a host value, and build a real `Diagnostic` instance from a host value to hand back to an extension. `vscode.Location`, the fifth declaration the same task adds, is intentionally not defined here: its constructor needs `Range`'s constructor, which exists only inside the text-geometry component's own script-evaluation closure, so `Location` lives there instead (that component's own header explains why in full). Two behaviors are drawn from the VS Code implementation (`extHostTypes.diagnostic.ts`) rather than from `vscode.d.ts`'s prose: the constructor throwing on an invalid `range` or a falsy `message`, and a missing third constructor argument defaulting `severity` to `DiagnosticSeverity.Error` (`0`). This component deliberately diverges from upstream in one place: `Diagnostic` and `DiagnosticRelatedInformation` require a real `Range`/`Location` instance at construction, where upstream accepts a duck-typed value structurally and only refuses it later, one call removed from where the extension made its mistake.

## Behavioral Requirements

- **install-once-per-context**: Installing the diagnostic types MUST evaluate the diagnostic-classes source at most once for a given script context; on a context that already carries a cached container under the global name `__vscodeDiagnosticTypesClasses`, it MUST return that cached container rather than re-evaluating the source.
- **cache-write-optional**: When caching the container under `__vscodeDiagnosticTypesClasses` via `Object.defineProperty` fails (a context that refuses the define), the evaluation MUST still return the freshly built result for that one call rather than treat the failed cache write as an error.
- **install-evaluate-failure**: Installing the diagnostic types MUST fail, leaving the four declarations uninstalled for that context, and MUST log an error, when evaluating the diagnostic-classes source in the context returns a value that is empty or not an object.
- **install-js-side-error**: Installing the diagnostic types MUST fail, leaving the four declarations uninstalled, and MUST log an error including the caught script error's message, when the evaluated result carries a non-empty installed-error value (the source's own error handling around class construction and freezing).
- **install-missing-member**: Installing the diagnostic types MUST fail, and MUST log an error, when the resulting container is missing an object-valued `DiagnosticSeverity`, `DiagnosticTag`, `DiagnosticRelatedInformation`, or `Diagnostic` member.
- **install-failure-is-non-fatal**: A failed install MUST NOT be treated as fatal to extension activation; `vscode.DiagnosticSeverity`/`DiagnosticTag`/`DiagnosticRelatedInformation`/`Diagnostic` simply stay the shim's not-implemented stub for that context.
- **severity-forward-mapping**: The installed `DiagnosticSeverity` object MUST expose `Error === 0`, `Warning === 1`, `Information === 2`, and `Hint === 3`.
- **severity-reverse-mapping**: The installed `DiagnosticSeverity` object MUST also expose the reverse numeric-key mapping `[0] === 'Error'`, `[1] === 'Warning'`, `[2] === 'Information'`, `[3] === 'Hint'`, mirroring the object shape the TypeScript compiler produces for a numeric enum.
- **tag-forward-mapping**: The installed `DiagnosticTag` object MUST expose `Unnecessary === 1` and `Deprecated === 2`; it MUST NOT define a `0` member.
- **tag-reverse-mapping**: The installed `DiagnosticTag` object MUST also expose the reverse mapping `[1] === 'Unnecessary'` and `[2] === 'Deprecated'`.
- **enum-objects-are-plain-and-frozen**: `DiagnosticSeverity` and `DiagnosticTag` MUST be plain frozen objects, not script classes; no code in this component constructs an instance of either.
- **classes-frozen-after-construction**: `DiagnosticRelatedInformation`, `DiagnosticRelatedInformation.prototype`, `Diagnostic`, and `Diagnostic.prototype` MUST each be frozen via `Object.freeze` inside the same evaluation that builds them, with no window in which any of the four exists unfrozen.
- **instances-not-frozen**: Neither a `DiagnosticRelatedInformation` instance nor a `Diagnostic` instance MUST be frozen; both types' properties are writable after construction (none of `vscode.d.ts`'s declared properties for either is `readonly`), so extension code MAY set `diagnostic.source`, `.code`, `.tags`, or a `relatedInformation`'s fields after construction.
- **related-information-constructor-validates-location**: `DiagnosticRelatedInformation`'s constructor MUST throw a `TypeError` whose message is `"location must be a vscode.Location"` when `location` is not `instanceof` the `Location` class published in the text-geometry component's installed container (read lazily via `globalThis[textGeometryGlobalName]` at construction time, not captured at evaluation time).
- **diagnostic-constructor-validates-range**: `Diagnostic`'s constructor MUST throw a `TypeError` whose message is `"range must be a vscode.Range"` when `range` is not `instanceof` the `Range` class published in the text-geometry component's installed container, read the same lazy way.
- **diagnostic-constructor-validates-message**: `Diagnostic`'s constructor MUST throw a `TypeError` with the message `"message must be set"` when `message` is falsy (including an empty string).
- **diagnostic-constructor-severity-default**: `Diagnostic`'s constructor MUST default `severity` to `DiagnosticSeverity.Error` (`0`) exactly when the third argument is `typeof severity === 'undefined'`; it MUST NOT use a falsy check such as `severity || DiagnosticSeverity.Error`, which would silently replace an explicitly passed `0`.
- **diagnostic-constructor-leaves-optionals-unassigned**: `Diagnostic`'s constructor MUST assign only `range`, `message`, and `severity`; it MUST NOT assign `source`, `code`, `relatedInformation`, or `tags` at all — not even the value `undefined` — when the corresponding argument is not supplied, so that `'source' in diagnostic` and `Object.hasOwn(diagnostic, 'source')` are both `false` until an extension sets the property itself.
- **geometry-classes-resolved-lazily**: Both `DiagnosticRelatedInformation` and `Diagnostic` MUST resolve the `Location`/`Range` class they validate against by reading `globalThis[textGeometryGlobalName]` at the moment the constructor runs, not at the moment the diagnostic-classes source is evaluated, so installing the diagnostic types and installing the text-geometry classes MAY run in either order on a given context.
- **diagnostic-related-information-decode-requires-real-instance**: Decoding a related-information value MUST fail for any script value that is not a genuine instance of the installed `DiagnosticRelatedInformation` class, even when the value is a plain object literal shaped identically (`{ location, message }` with a genuine `Location` for `location`).
- **diagnostic-related-information-decode-fields**: For a value that is a real `DiagnosticRelatedInformation` instance, decoding MUST fail unless `location` decodes via the text-geometry component's location decoding and `message` is a string; otherwise it MUST succeed, producing a related-information value carrying both.
- **diagnostic-decode-requires-real-instance**: Decoding a diagnostic value MUST fail for any script value that is not a genuine instance of the installed `Diagnostic` class, even when the value is a plain object literal shaped identically.
- **diagnostic-decode-required-fields**: For a value that is a real `Diagnostic` instance, decoding MUST fail unless `range` decodes via the text-geometry component's range decoding, `message` is a non-empty string, and `severity` is a number whose exact integer value maps to a defined severity value (`0`–`3`).
- **diagnostic-decode-optional-field-absence**: Decoding a diagnostic value MUST treat each of `source`, `code`, `relatedInformation`, and `tags` as absent — decoding to an unset field — when the corresponding property is `undefined` **or** `null`; the constructor produces `undefined` (by never assigning), while an extension filling the object from an LSP `Diagnostic` wire payload (whose JSON `null` survives parsing) produces `null`, and both MUST be treated identically as "not set".
- **diagnostic-decode-optional-field-malformed-refuses-whole-value**: Decoding a diagnostic value MUST fail for the entire diagnostic — not silently drop just that field — when `source`, `code`, `relatedInformation`, or `tags` is present (neither `undefined` nor `null`) but fails to decode into its expected shape.
- **diagnostic-code-three-shapes**: Decoding a diagnostic code MUST decode a string as a plain string code, a number as a plain number code, and an object carrying a `value` property (itself a string or number) and a `target` property that decodes via the URI decoding as a linked code (`value` plus `target`); it MUST fail for any value matching none of the three shapes.
- **related-information-array-decode-atomicity**: Decoding a related-information array MUST use the shared array-length check to determine the element count and MUST fail for the entire array — not a partial array — if any element fails the related-information decode.
- **tags-array-decode-atomicity**: Decoding a tags array MUST use the shared array-length check and MUST fail for the entire array if any element is not a number or does not map to a defined tag value (`1` or `2`; `0` is out of range).
- **tags-array-preserves-order**: Decoding a tags array MUST preserve the array's element order in the returned list; it MUST NOT sort, deduplicate, or reverse the tags.
- **diagnostic-value-constructs-through-real-constructor**: Encoding a diagnostic value MUST build the result by calling the installed `Diagnostic` class's constructor with `(range, message, severity)` — never by assembling a plain object literal — so the returned value is genuinely `instanceof` `vscode.Diagnostic`.
- **diagnostic-value-optional-fields-set-only-when-present**: Encoding a diagnostic value MUST assign `source`, `code`, `relatedInformation`, and `tags` on the constructed instance only when the corresponding field is present; when a field is absent, the corresponding property MUST be left unassigned, not set to `null` or `undefined`.
- **diagnostic-value-propagates-nested-encode-failure**: Encoding a diagnostic value MUST fail — without constructing a partially-filled result — if encoding `range`, any element of `relatedInformation`, or `code` fails.
- **related-information-value-constructs-through-real-constructor**: Encoding a related-information value MUST build the result by calling the installed `DiagnosticRelatedInformation` class's constructor with `(location, message)`, so the result is genuinely `instanceof` `vscode.DiagnosticRelatedInformation`.
- **no-instance-caching-of-decoded-values**: Decoding a diagnostic value or a related-information value MUST decode fresh from the given script value on every call; neither operation MUST cache or reuse a prior decode for the same underlying script object.

## Appearance

Not applicable — this is a script-context class-installer and host↔script bridge, not a visual component.

## States

Not applicable — this is a script-context class-installer and host↔script bridge, not a visual component. Its only lifecycle-shaped behavior is the once-per-context installation and caching sequence, captured under Behavioral Requirements (**install-once-per-context**, **cache-write-optional**) rather than as a visual-state table.

## Accessibility

Not applicable — this is a script-context class-installer and host↔script bridge, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| diagnostic-types-001 | severity-forward-mapping, severity-reverse-mapping | Read `DiagnosticSeverity.Error`/`.Warning`/`.Information`/`.Hint` and `DiagnosticSeverity[0]`/`[1]`/`[2]`/`[3]` on an installed context | Forward reads are `0`, `1`, `2`, `3`; reverse reads are `"Error"`, `"Warning"`, `"Information"`, `"Hint"` — `DiagnosticTypesTests.diagnosticSeverityHasAllFourValuesByNumber` |
| diagnostic-types-002 | tag-forward-mapping, tag-reverse-mapping | Read `DiagnosticTag.Unnecessary`/`.Deprecated` and `DiagnosticTag[1]`/`[2]` | `Unnecessary == 1`, `Deprecated == 2`, neither is `0`; reverse reads are `"Unnecessary"`, `"Deprecated"` — `DiagnosticTypesTests.diagnosticTagHasBothValuesAndNeitherIsZero` |
| diagnostic-types-003 | diagnostic-constructor-severity-default | `new Diagnostic(new Range(0, 0, 0, 1), 'oops')` (no third argument) | `d.severity` is the JS number `0` (`typeof d.severity === 'number'`), not `undefined` — `DiagnosticTypesTests.diagnosticTwoArgConstructorDefaultsSeverityToError` |
| diagnostic-types-004 | diagnostic-constructor-severity-default | `new Diagnostic(new Range(0, 0, 0, 1), 'oops', DiagnosticSeverity.Hint)` | `d.severity === 3` | `DiagnosticTypesTests.diagnosticThreeArgConstructorHonoursExplicitHintSeverity` |
| diagnostic-types-005 | diagnostic-code-three-shapes | `d.code = 'E1234'` then decode `d` | Decodes to a plain string code `"E1234"` — `DiagnosticTypesTests.diagnosticCodeAcceptsAPlainString` |
| diagnostic-types-006 | diagnostic-code-three-shapes | `d.code = 42` then decode | Decodes to a plain number code `42` — `DiagnosticTypesTests.diagnosticCodeAcceptsAPlainNumber` |
| diagnostic-types-007 | diagnostic-code-three-shapes | `d.code = { value: 'E1234', target: Uri.parse('https://example.com/e1234') }` then decode | Decodes to a linked code with value `"E1234"` and target URL `"https://example.com/e1234"` — `DiagnosticTypesTests.diagnosticCodeAcceptsAnObjectFormWithARealUriTarget` |
| diagnostic-types-008 | diagnostic-related-information-decode-fields, related-information-array-decode-atomicity | `d.relatedInformation = [new DiagnosticRelatedInformation(new Location(otherUri, new Range(2,0,2,3)), 'see here')]` then decode `d` | Decoded `relatedInformation` has one entry with `message == "see here"` and `location.uri.path == "/other.txt"`, `location.range` matching the constructed `Range` — `DiagnosticTypesTests.diagnosticRelatedInformationRoundTripsANestedLocation` |
| diagnostic-types-009 | tags-array-preserves-order | `d.tags = [DiagnosticTag.Deprecated, DiagnosticTag.Unnecessary]` then decode | Decoded `tags` equals `[Deprecated, Unnecessary]`, in that exact order | `DiagnosticTypesTests.diagnosticTagsRoundTripPreservingOrder` |
| diagnostic-types-010 | classes-frozen-after-construction, instances-not-frozen | `Object.isFrozen(DiagnosticSeverity)`, `Object.isFrozen(Diagnostic)`, `Object.isFrozen(Diagnostic.prototype)`; then `DiagnosticSeverity.Error = 99` and re-read; then `DiagnosticRelatedInformation.prototype.tampered = 'yes'` | All three `isFrozen` checks are `true`; `DiagnosticSeverity.Error` still reads `0` after the tampering assignment; `'tampered' in DiagnosticRelatedInformation.prototype` is `false` — `DiagnosticTypesTests.everyDiagnosticClassAndPrototypeIsFrozen` |
| diagnostic-types-011 | diagnostic-related-information-decode-requires-real-instance | Decode a plain `{ location: <real Location>, message: 'oops' }` object literal as related information | Fails — `DiagnosticTypesTests.diagnosticRelatedInformationFromRefusesADuckTypedLiteral` |
| diagnostic-types-012 | diagnostic-related-information-decode-fields | Decode a real `new DiagnosticRelatedInformation(location, 'oops')` as related information | Succeeds, producing a value with `message == "oops"` and `location.uri.path == "/a.txt"` — `DiagnosticTypesTests.diagnosticRelatedInformationFromReadsARealInstance` |
| diagnostic-types-013 | diagnostic-decode-requires-real-instance | Decode a plain `{ range: <real Range>, message: 'oops', severity: 0 }` object literal as a diagnostic | Fails — `DiagnosticTypesTests.diagnosticFromRefusesADuckTypedLiteral` |
| diagnostic-types-014 | diagnostic-decode-required-fields | Decode a real `new Diagnostic(range, 'oops', DiagnosticSeverity.Warning)` as a diagnostic | Succeeds, producing a value with `message == "oops"`, `severity == Warning`, and `range` matching the constructed range — `DiagnosticTypesTests.diagnosticFromReadsARealInstance` |
| diagnostic-types-015 | related-information-value-constructs-through-real-constructor, diagnostic-related-information-decode-fields | Encode a related-information value, then check `instanceof DiagnosticRelatedInformation` and round-trip through the related-information decode | `instanceof` is `true`; the round-tripped value equals the original — `DiagnosticTypesTests.diagnosticRelatedInformationValueRoundTripsThroughTheReader` |
| diagnostic-types-016 | diagnostic-value-constructs-through-real-constructor, diagnostic-value-optional-fields-set-only-when-present | Encode a diagnostic value with `source`, a linked `code`, one `relatedInformation` entry, and two `tags` set, then check `instanceof Diagnostic` and round-trip through the diagnostic decode | `instanceof` is `true`; the round-tripped value equals the original, including all four optional fields — `DiagnosticTypesTests.diagnosticValueRoundTripsThroughTheReaderWithAllOptionalFields` |
| diagnostic-types-017 | diagnostic-value-optional-fields-set-only-when-present | Encode a diagnostic value with a number `code` (`42`) and no other optional fields, then round-trip | Round-tripped value equals the original; the linked-code-only fixture in vector 016 does not by itself cover this branch — `DiagnosticTypesTests.diagnosticValueRoundTripsAScalarCode` |
| diagnostic-types-018 | diagnostic-constructor-leaves-optionals-unassigned | `new Diagnostic(new Range(0,0,0,1), 'oops')`, then `'source' in d`/`Object.hasOwn(d, 'source')` for each of `source`, `code`, `relatedInformation`, `tags` | All eight checks are `false` — `DiagnosticTypesTests.diagnosticOptionalPropertiesAreAbsentNotUndefinedValued` |
| diagnostic-types-019 | diagnostic-decode-optional-field-malformed-refuses-whole-value | `d.source = 42` (a number, not a string) then decode `d` | Fails for the whole diagnostic — `DiagnosticTypesTests.diagnosticRefusesAMalformedSource` |
| diagnostic-types-020 | diagnostic-decode-optional-field-malformed-refuses-whole-value, diagnostic-code-three-shapes | `d.code = {}` (missing `value`/`target`) then decode `d` | Fails — `DiagnosticTypesTests.diagnosticRefusesAMalformedCode` |
| diagnostic-types-021 | diagnostic-decode-optional-field-malformed-refuses-whole-value, related-information-array-decode-atomicity | `d.relatedInformation = [{ location: <real Location>, message: 'oops' }]` (a duck-typed element, not a real `DiagnosticRelatedInformation`) then decode | Fails for the whole diagnostic — `DiagnosticTypesTests.diagnosticRefusesAMalformedRelatedInformationElement` |
| diagnostic-types-022 | diagnostic-decode-optional-field-malformed-refuses-whole-value, tags-array-decode-atomicity | `d.tags = [0]` (`0` is out of range for `DiagnosticTag`) then decode | Fails — `DiagnosticTypesTests.diagnosticRefusesAMalformedTagsElement` |

## Edge Cases

- **Null/empty input**: `message` argument to `Diagnostic`'s constructor as `''` (empty string) MUST throw `TypeError('message must be set')`, per **diagnostic-constructor-validates-message** (MUST) — traced to the constructor's falsy check, which an empty string satisfies the same way `null`/`undefined` would.
- **Null/empty input**: a `source`/`code`/`relatedInformation`/`tags` property that is `null` (not merely `undefined`) MUST decode as absent, identically to a genuinely unset property, per **diagnostic-decode-optional-field-absence** (MUST) — this is the shape an LSP-derived `Diagnostic` payload produces once round-tripped through `JSON.parse`.
- **Boundary values**: `severity` values outside `0`–`3` (e.g. `4`, `-1`, or a non-integer such as `1.5`) MUST fail when constructing a severity value from its raw number, and MUST cause decoding a diagnostic value to fail for the whole value, per **diagnostic-decode-required-fields** (MUST).
- **Boundary values**: a `tags` element equal to `0` MUST fail — no defined tag value corresponds to `0`, per **tags-array-decode-atomicity** (MUST).
- **Boundary values**: a `relatedInformation` or `tags` array of exactly the shared array-length limit (100,000) elements is the largest the shared array-length check will accept; one element longer MUST cause that check to fail, which MUST cause the whole `relatedInformation`/`tags` array decode — and therefore the whole diagnostic decode — to fail, with an error logged by the shared array-length check itself (MUST).
- **Boundary values**: an array-like object carrying a numeric `length` property but that is not genuinely an array MUST be refused by the shared array-length check, and therefore by decoding a related-information array or a tags array, rather than walked by its reported length (MUST).
- **Concurrent access**: not applicable in the sense of requiring synchronization — this component is confined to a single serialized execution domain, so there is no path by which two calls into its operations execute concurrently against the same context; see Platform Notes for how that confinement is enforced (MUST).
- **Error states**: installing the diagnostic types failing for any of its three logged reasons (evaluate failure, script-side installed-error, or a missing container member) MUST leave `vscode.DiagnosticSeverity`/`DiagnosticTag`/`DiagnosticRelatedInformation`/`Diagnostic` as the shim's not-implemented stub for that context rather than raise a host error or a script exception, per **install-failure-is-non-fatal** (MUST).
- **Error states**: a `Diagnostic` or `DiagnosticRelatedInformation` constructor call that throws (invalid `range`/`location`, or a falsy `message`) MUST propagate as a real script `TypeError` to the extension's own calling code — this component performs no error handling around the constructors themselves; only the diagnostic-classes source's own outer wrapper catches errors, and only during installation, not during later construction (MUST).
- **Offline or disconnected state**: not applicable — this component makes no network call and opens no file; every input it processes arrives already in memory as a script value.
- **Cancellation and timeouts**: not applicable — every operation in this component is synchronous; there is no long-running operation to cancel or time out.
- **Missing file or unreachable server**: not applicable — this component has no filesystem or network dependency of its own; the URI decoding used for a linked code's target decodes a value already resident in the script context rather than resolving it against a filesystem or server.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `context` | script context | none (required) | Every operation in this component takes the target context explicitly; there is no ambient or singleton context. |
| `value` (decode operations) | script value | none (required) | The script value to decode; decoding a diagnostic, related information, a diagnostic code, a related-information array, and a tags array all take one. |
| `diagnostic` / `relatedInformation` (encode operations) | diagnostic value / related-information value | none (required) | The host value the diagnostic encoder / related-information encoder encodes back into a real script instance. |
| `maximumDecodableArrayLength` | integer | `100_000` | The ceiling the shared array-length check enforces for any array this component walks (`relatedInformation`, `tags`). Not settable per call. |
| `severity` (constructor's 3rd argument) | script number or `undefined` | `DiagnosticSeverity.Error` (`0`) when omitted | Read by `Diagnostic`'s constructor; an explicit `0` is preserved and distinguished from "omitted" via `typeof`. |
| `severity` (host-side default) | severity value | `Error` | The host-side diagnostic value's own default, mirroring the script constructor's default. |

## Deep Linking

Not applicable: this component defines no URL, route, or navigable destination — it installs script classes and bridges values, with no navigation surface of its own.

## Localization

- **hardcoded-error-messages**: The three `TypeError` messages this component's constructors throw — `"location must be a vscode.Location"`, `"range must be a vscode.Range"`, and `"message must be set"` — are hardcoded English string literals with no localization key. They are visible to the extension author, not to the app's own end-user UI, per the component's own documentation framing these as validation surfaced to "the extension" that made the mistake.
- **hardcoded-log-strings**: The three error-log messages produced while installing the diagnostic types (evaluate failure, script-side installed-error, missing container member) are hardcoded English log strings, also unlocalized.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `location must be a vscode.Location` | `DiagnosticRelatedInformation`'s constructor, thrown when `location` fails the `instanceof` check. |
| (none — literal only) | `range must be a vscode.Range` | `Diagnostic`'s constructor, thrown when `range` fails the `instanceof` check. |
| (none — literal only) | `message must be set` | `Diagnostic`'s constructor, thrown when `message` is falsy. |
| (none — literal only) | `Could not install the 'vscode.DiagnosticSeverity'/'vscode.DiagnosticTag'/'vscode.DiagnosticRelatedInformation'/'vscode.Diagnostic' classes in context '<name>'; they stay the shim's not-implemented stub` | Logged while installing the diagnostic types, on an evaluate failure. |
| (none — literal only) | `Could not install the 'vscode.DiagnosticSeverity'/'vscode.DiagnosticTag'/'vscode.DiagnosticRelatedInformation'/'vscode.Diagnostic' classes in context '<name>': '<error>'; they stay the shim's not-implemented stub` | Logged while installing the diagnostic types, on a script-side installed-error. |
| (none — literal only) | `The 'vscode' diagnostic-types container in context '<name>' is missing one of 'DiagnosticSeverity', 'DiagnosticTag', 'DiagnosticRelatedInformation' or 'Diagnostic'; all four stay the shim's not-implemented stub` | Logged while installing the diagnostic types, when the container is missing an expected member. |

## Accessibility Options

Not applicable: this component renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; the four declarations it installs are always available once installing the diagnostic types succeeds for a context.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; its only telemetry-adjacent calls are the three error-log lines covered under Logging, which are diagnostic logging, not analytics events.

## Privacy

- **Data collected**: this component collects no data of its own; it decodes and re-encodes whatever `range`, `message`, `severity`, `source`, `code`, `relatedInformation`, and `tags` values an extension or the host already holds, without retaining a copy beyond the return value of each call.
- **Storage**: this component performs no storage of its own; a decoded diagnostic value is only as persistent as whatever the caller does with the returned value.
- **Transmission**: this component makes no network call; it neither sends nor receives anything over a network.
- **Retention**: nothing in this component is retained beyond the lifetime of one operation's local variables, except the per-context installed-class cache (`__vscodeDiagnosticTypesClasses`), which holds only class/prototype objects, never a diagnostic's data.

## Logging

Subsystem: the host application's bundle identifier (falling back to a default when unavailable) | Category: the shared logger for this extension-API area, reused across every component in it, including this one

| Event | Level | Message |
|-------|-------|---------|
| Evaluating the diagnostic-classes source in the context returns an empty value or a non-object | error | `Could not install the 'vscode.DiagnosticSeverity'/'vscode.DiagnosticTag'/'vscode.DiagnosticRelatedInformation'/'vscode.Diagnostic' classes in context '<name>'; they stay the shim's not-implemented stub` |
| The evaluated result carries a non-empty installed-error value | error | `Could not install the 'vscode.DiagnosticSeverity'/'vscode.DiagnosticTag'/'vscode.DiagnosticRelatedInformation'/'vscode.Diagnostic' classes in context '<name>': '<installedError>'; they stay the shim's not-implemented stub` |
| The installed container is missing one of the four expected members | error | `The 'vscode' diagnostic-types container in context '<name>' is missing one of 'DiagnosticSeverity', 'DiagnosticTag', 'DiagnosticRelatedInformation' or 'Diagnostic'; all four stay the shim's not-implemented stub` |
| An array passed to the shared array-length check (via decoding a related-information array or a tags array) reports a length over 100,000 | error | (logged inside the shared array-length check, not inside this component): `refusing an array of <count> elements: longer than the 100000 this host decodes` |

No other event in this component is logged: neither a constructor's error nor a decode failure for a malformed field is logged at the point it occurs — both are facts the code surfaces to the caller (as a thrown script error, or as a decode failure) instead of a log line, per **diagnostic-constructor-validates-range**/**diagnostic-constructor-validates-message** and **diagnostic-decode-optional-field-malformed-refuses-whole-value**.

## Platform Notes

- **SwiftUI**: not applicable to this file — `DiagnosticTypes.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing here renders or observes view state.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/DiagnosticTypes.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is an extension of `VSCodeAPI`, itself `@MainActor`, and its consumers among the given sources are the JS-side `vscode.languages` diagnostics collection machinery and `MainThreadDiagnostics` (not among the given sources), which reads decoded `ExtensionDiagnostic` values back through `diagnostic(from:in:)`. Every function in this file MUST execute on the main actor: `VSCodeAPI` is declared `@MainActor` because `JSContext`/`JSValue` are not `Sendable` and JavaScriptCore always calls back on the thread that made the call, so there is no path by which two calls into this file's functions execute concurrently against the same context — the compiler enforces this rather than any lock or queue in the source. The Swift mirror types (`ExtensionDiagnosticSeverity`, `ExtensionDiagnosticTag`, `ExtensionDiagnosticCodeValue`, `ExtensionDiagnosticCode`, `ExtensionDiagnosticRelatedInformation`, and `ExtensionDiagnostic`) are each declared `Sendable` and `Equatable`, so a decoded value MAY be passed across actor boundaries once it has left the `JSContext`.
- **Compose**: model the four installed declarations as Kotlin: `DiagnosticSeverity`/`DiagnosticTag` as enum classes with an explicit numeric `value` property (Kotlin enums do not compile to a bidirectional-mapping object the way `tsc` does, so a small companion-object lookup table is needed to reproduce **severity-reverse-mapping**/**tag-reverse-mapping**), and `DiagnosticRelatedInformation`/`Diagnostic` as `data class`es whose "constructor" is a factory function performing the same `range`/`location`/`message` validation and throwing an `IllegalArgumentException` in place of a JS `TypeError`. The "never assign `undefined`" contract (**diagnostic-constructor-leaves-optionals-unassigned**) has no direct Kotlin analogue on a `data class`; model it with nullable properties defaulted to `null` and treat "absent" and "explicitly null" as the same case throughout, mirroring **diagnostic-decode-optional-field-absence**.
- **React/Web**: this is closest to the actual runtime shape — extension code in the real VS Code product already runs against the genuine `vscode.d.ts` declarations these mirror. A React/Web host embedding a similar extension bridge would decode/encode the same four shapes across whatever serialization boundary (e.g. `postMessage` to a worker) replaces this file's `JSContext` boundary, and would need the same "refuse the whole value on any malformed optional field" discipline (**diagnostic-decode-optional-field-malformed-refuses-whole-value**) when deserializing untrusted extension-authored data.
- **WinUI 3**: model `DiagnosticSeverity`/`DiagnosticTag` as `public enum DiagnosticSeverity { Error = 0, Warning = 1, Information = 2, Hint = 3 }` (a real C# enum already gives the forward mapping; `Enum.GetName(typeof(DiagnosticSeverity), value)` reproduces the reverse mapping on demand rather than needing a hand-built table). Model `DiagnosticRelatedInformation` and `Diagnostic` as `sealed record`s or plain classes whose constructors validate `location`/`range` with `is Location`/`is Range` pattern-matching (WinUI 3's `Location`/`Range` equivalents) and throw `ArgumentException` in place of a JS `TypeError`, matching **diagnostic-constructor-validates-location** and **diagnostic-constructor-validates-range**. `ExtensionDiagnosticCode`'s three-shape union (`code?: string | number | { value: string | number; target: Uri }`) has no built-in C# union type; model it as a small discriminated `abstract record CodeValue` with `Scalar`/`Link` subtypes, the direct analogue of the Swift `enum ExtensionDiagnosticCode { case scalar(...); case link(...) }` this file declares. `System.Text.Json.JsonSerializer` with a custom converter is the .NET equivalent of this file's manual `diagnosticCode(from:in:)`/`diagnosticCodeJSValue(for:in:)` pair, since the WinUI host would decode extension-authored diagnostics from a JSON-shaped bridge rather than a `JSValue`. The "assign only when present, never `null`/`undefined`" contract (**diagnostic-value-optional-fields-set-only-when-present**) maps to `JsonIgnoreCondition.WhenWritingNull` combined with nullable reference types, so an absent field is omitted from serialized output rather than written as `null`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/DiagnosticTypes.swift` |

## Design Decisions

**Decision**: `Diagnostic` requires a real `Range` instance and `DiagnosticRelatedInformation` requires a real `Location` instance at construction time (`requireGeometryInstance`), rather than accepting any value shaped like one.
**Rationale**: upstream VS Code checks `range` structurally (`Range.isRange`) and does not check `location` at all, then reads a duck-typed value back happily; this host's readers (`range(from:in:)`, `location(from:in:)`, both in `TextGeometry.swift`) already refuse anything that is not a real instance via `isInstance(of:)`. Accepting at construction what the reader will later refuse would surface an extension's mistake one call removed, at `collection.set(uri, [d])`, naming neither the argument nor the line that built it; refusing in the constructor puts the failure where the extension's own code made the mistake.
**Approved**: pending

**Decision**: `Diagnostic`'s constructor never assigns `source`, `code`, `relatedInformation`, or `tags` at all when not supplied, rather than assigning them `undefined`.
**Rationale**: matches `diagnostic.ts`'s constructor, which only ever assigns `range`, `message`, and `severity`; this is what makes `'source' in diagnostic` genuinely `false` until an extension sets it, exactly as real VS Code behaves. An implementation that unconditionally wrote `this.source = source` would make that membership check always `true`, a detectable behavioral divergence from the upstream declaration real extensions may rely on.
**Approved**: pending

**Decision**: `diagnostic(from:in:)` treats a present-but-undecodable optional field (a `source` that is a number, a `code` matching none of the three shapes, a malformed `relatedInformation`/`tags` element) as a failure of the *entire* decode, returning `nil` rather than a partial `ExtensionDiagnostic` with that one field dropped.
**Rationale**: the source's own inline comment traces a concrete production incident to the opposite choice: reading `code: null` or `source: null` as "present but undecodable" once dropped every diagnostic in a file for every extension that asked, because a downstream array reader (`MainThreadDiagnostics`, not among the given sources) itself refuses a whole file's array when one element refuses. Distinguishing `null`/`undefined` ("absent") from a genuinely malformed present value, and refusing the whole diagnostic only for the latter, is the fix; treating every malformed field as if the diagnostic silently lost that one field would reintroduce a different silent-data-loss failure mode one level up.
**Approved**: pending

**Decision**: this file's own doc comment characterizes the `range`/`location` validity check inside `requireGeometryInstance` as "a validity gate, not an identity check" and describes it as dispatching structurally on `.start`/`.end`-shaped properties, "the same structural way `Range.prototype.contains` already dispatches." The actual `requireGeometryInstance` implementation performs `value instanceof geometryClass`, where `geometryClass` is looked up dynamically via `globalThis[textGeometryGlobalName][name]` — a genuine identity check against the class TextGeometry.swift installed, not a structural check of `.start`/`.end`.
**Rationale**: not stated in the source; this is a divergence between the file's header prose and its own code, not a design choice this recipe can attribute to either. Practically it makes no behavioral difference for a well-formed `Range`/`Location` instance, since a real instance is both `instanceof` its class and shaped correctly — but it does mean a hypothetical duck-typed literal carrying `.start`/`.end` properties, which the header's prose implies would pass, is in fact refused by the actual `instanceof` check, per **diagnostic-constructor-validates-range**/**related-information-constructor-validates-location**, which this recipe states from the code rather than the header.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because this file's only responsibilities are installing four JS declarations in a `JSContext` and bridging their instances to and from Swift; it delegates all `Range`/`Location`/`Uri` decoding to `TextGeometry.swift` and `Uri.swift` rather than duplicating that logic (see Overview and **geometry-classes-resolved-lazily**). `unit-test-coverage` passes: `DiagnosticTypesTests.swift`'s twenty test methods exercise every one of this file's thirteen documented mutation points named in its own header — both enum mappings, both constructor defaults, all three `code` shapes, nested `relatedInformation`, tag ordering, every freeze, both duck-typed-literal refusals, both writer round-trips, absent-vs-undefined-valued optionals, and all three "malformed present value refuses the whole diagnostic" cases. `explicit-error-handling` is partial: constructor failures are real, typed JS `TypeError`s with specific messages, and reader failures are a clean `nil` rather than a swallowed exception, but `installDiagnosticTypes(in:)`'s own `try`/`catch` (inside `diagnosticClassesSource`'s IIFE) collapses every installation-time exception into a single generic `{ installedError: error.message }` shape, discarding which specific step (severity object construction, class construction, or freezing) failed. `input-sanitization` passes because every reader in this file refuses a value that is not a genuine instance of the class it claims to be (`isInstance(of:)`/`instanceof`) before reading any of that value's properties, rather than trusting a duck-typed shape from untrusted extension-authored JavaScript (see **diagnostic-decode-requires-real-instance**, **diagnostic-related-information-decode-requires-real-instance**). `no-hardcoded-strings` fails because both the three constructor `TypeError` messages and the three installer log messages are English literals with no localization mechanism (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/languages/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
