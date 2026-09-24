---
id: 6fa79a51-8e62-4a99-8979-c93a4269dac8
title: DiagnosticTypes
domain: agentictoolkit://recipes/extension-host-vs-code-api-diagnostic-types
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The VSCodeAPI extension installing vscode.DiagnosticSeverity, DiagnosticTag,
  DiagnosticRelatedInformation and Diagnostic in a JSContext, and bridging instances
  to and from Swift.
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

# DiagnosticTypes

## Overview

`DiagnosticTypes.swift` is a `VSCodeAPI` extension that gives the extension host's embedded `JSContext` real, `instanceof`-checkable implementations of four `vscode` API declarations — `vscode.DiagnosticSeverity`, `vscode.DiagnosticTag`, `vscode.DiagnosticRelatedInformation` and `vscode.Diagnostic` (`vscode.d.ts`, `:7053-7072`, `:7077-7096` and `:7102-7161` at the pinned commit named in the file's own header) — and the Swift-side mirror types and bidirectional bridging functions that let host code read an extension-built `Diagnostic` back into a Swift value, and build a real `Diagnostic` instance from a Swift value to hand back to an extension. `vscode.Location`, the fifth declaration the same task adds, is intentionally not defined here: its constructor needs `Range`'s constructor, which exists only inside `TextGeometry.swift`'s own `evaluateScript` closure, so `Location` lives in `TextGeometry.swift` instead (that file's header explains why in full). Two behaviors are drawn from the VS Code implementation (`extHostTypes.diagnostic.ts`) rather than from `vscode.d.ts`'s prose: the constructor throwing on an invalid `range` or a falsy `message`, and a missing third constructor argument defaulting `severity` to `DiagnosticSeverity.Error` (`0`). The file deliberately diverges from upstream in one place: `Diagnostic` and `DiagnosticRelatedInformation` require a real `Range`/`Location` instance at construction, where upstream accepts a duck-typed value structurally and only refuses it later, one call removed from where the extension made its mistake.

## Behavioral Requirements

- **main-actor-isolation**: Every function in this file MUST execute on the main actor; `VSCodeAPI` is declared `@MainActor` because `JSContext`/`JSValue` are not `Sendable` and JavaScriptCore always calls back on the thread that made the call.
- **install-once-per-context**: `installDiagnosticTypes(in:)` MUST evaluate `diagnosticClassesSource` at most once for a given `JSContext`; on a context that already carries a cached container under the global name `__vscodeDiagnosticTypesClasses`, it MUST return that cached container rather than re-evaluating the source.
- **cache-write-optional**: When caching the container under `__vscodeDiagnosticTypesClasses` via `Object.defineProperty` fails (a context that refuses the define), the evaluation MUST still return the freshly built `result` for that one call rather than treat the failed cache write as an error.
- **install-evaluate-failure**: `installDiagnosticTypes(in:)` MUST return `nil`, and MUST log an error via `VSCodeAPI.logger`, when `context.evaluateScript(diagnosticClassesSource)` returns a value that is `nil` or not an object.
- **install-js-side-error**: `installDiagnosticTypes(in:)` MUST return `nil`, and MUST log an error via `VSCodeAPI.logger` including the caught JS error's message, when the evaluated result carries a non-undefined `installedError` property (the source's own `try`/`catch` around class construction and freezing).
- **install-missing-member**: `installDiagnosticTypes(in:)` MUST return `nil`, and MUST log an error via `VSCodeAPI.logger`, when the resulting container is missing an object-valued `DiagnosticSeverity`, `DiagnosticTag`, `DiagnosticRelatedInformation`, or `Diagnostic` member.
- **install-failure-is-non-fatal**: A `nil` result from `installDiagnosticTypes(in:)` MUST NOT be treated as fatal to extension activation; `vscode.DiagnosticSeverity`/`DiagnosticTag`/`DiagnosticRelatedInformation`/`Diagnostic` simply stay the shim's not-implemented stub for that context.
- **severity-forward-mapping**: The installed `DiagnosticSeverity` object MUST expose `Error === 0`, `Warning === 1`, `Information === 2`, and `Hint === 3`.
- **severity-reverse-mapping**: The installed `DiagnosticSeverity` object MUST also expose the reverse numeric-key mapping `[0] === 'Error'`, `[1] === 'Warning'`, `[2] === 'Information'`, `[3] === 'Hint'`, mirroring the object shape `tsc` compiles a numeric `enum` to.
- **tag-forward-mapping**: The installed `DiagnosticTag` object MUST expose `Unnecessary === 1` and `Deprecated === 2`; it MUST NOT define a `0` member.
- **tag-reverse-mapping**: The installed `DiagnosticTag` object MUST also expose the reverse mapping `[1] === 'Unnecessary'` and `[2] === 'Deprecated'`.
- **enum-objects-are-plain-and-frozen**: `DiagnosticSeverity` and `DiagnosticTag` MUST be plain frozen objects, not JS classes; no code in this file constructs an instance of either.
- **classes-frozen-after-construction**: `DiagnosticRelatedInformation`, `DiagnosticRelatedInformation.prototype`, `Diagnostic`, and `Diagnostic.prototype` MUST each be frozen via `Object.freeze` inside the same evaluation that builds them, with no window in which any of the four exists unfrozen.
- **instances-not-frozen**: Neither a `DiagnosticRelatedInformation` instance nor a `Diagnostic` instance MUST be frozen; both types' properties are writable after construction (none of `vscode.d.ts`'s declared properties for either is `readonly`), so extension code MAY set `diagnostic.source`, `.code`, `.tags`, or a `relatedInformation`'s fields after construction.
- **related-information-constructor-validates-location**: `DiagnosticRelatedInformation`'s constructor MUST throw a `TypeError` whose message is `"location must be a vscode.Location"` when `location` is not `instanceof` the `Location` class published in `TextGeometry.swift`'s installed container (read lazily via `globalThis[textGeometryGlobalName]` at construction time, not captured at evaluation time).
- **diagnostic-constructor-validates-range**: `Diagnostic`'s constructor MUST throw a `TypeError` whose message is `"range must be a vscode.Range"` when `range` is not `instanceof` the `Range` class published in `TextGeometry.swift`'s installed container, read the same lazy way.
- **diagnostic-constructor-validates-message**: `Diagnostic`'s constructor MUST throw a `TypeError` with the message `"message must be set"` when `message` is falsy (including an empty string).
- **diagnostic-constructor-severity-default**: `Diagnostic`'s constructor MUST default `severity` to `DiagnosticSeverity.Error` (`0`) exactly when the third argument is `typeof severity === 'undefined'`; it MUST NOT use a falsy check such as `severity || DiagnosticSeverity.Error`, which would silently replace an explicitly passed `0`.
- **diagnostic-constructor-leaves-optionals-unassigned**: `Diagnostic`'s constructor MUST assign only `range`, `message`, and `severity`; it MUST NOT assign `source`, `code`, `relatedInformation`, or `tags` at all — not even the value `undefined` — when the corresponding argument is not supplied, so that `'source' in diagnostic` and `Object.hasOwn(diagnostic, 'source')` are both `false` until an extension sets the property itself.
- **geometry-classes-resolved-lazily**: Both `DiagnosticRelatedInformation` and `Diagnostic` MUST resolve the `Location`/`Range` class they validate against by reading `globalThis[textGeometryGlobalName]` at the moment the constructor runs, not at the moment `diagnosticClassesSource` is evaluated, so `installDiagnosticTypes(in:)` and `installTextGeometryClasses(in:)` MAY run in either order on a given context.
- **diagnostic-related-information-decode-requires-real-instance**: `diagnosticRelatedInformation(from:in:)` MUST return `nil` for any JS value that is not `isInstance(of:)` the installed `DiagnosticRelatedInformation` class, even when the value is a plain object literal shaped identically (`{ location, message }` with a genuine `Location` for `location`).
- **diagnostic-related-information-decode-fields**: For a value that is a real `DiagnosticRelatedInformation` instance, `diagnosticRelatedInformation(from:in:)` MUST return `nil` unless `location` decodes via `TextGeometry.swift`'s `location(from:in:)` and `message` is a JS string; otherwise it MUST return an `ExtensionDiagnosticRelatedInformation` carrying both.
- **diagnostic-decode-requires-real-instance**: `diagnostic(from:in:)` MUST return `nil` for any JS value that is not `isInstance(of:)` the installed `Diagnostic` class, even when the value is a plain object literal shaped identically.
- **diagnostic-decode-required-fields**: For a value that is a real `Diagnostic` instance, `diagnostic(from:in:)` MUST return `nil` unless `range` decodes via `TextGeometry.swift`'s `range(from:in:)`, `message` is a non-empty JS string, and `severity` is a JS number whose exact integer value maps to a defined `ExtensionDiagnosticSeverity` raw value (`0`–`3`).
- **diagnostic-decode-optional-field-absence**: `diagnostic(from:in:)` MUST treat each of `source`, `code`, `relatedInformation`, and `tags` as absent — decoding to a `nil` Swift field — when the corresponding JS property is `undefined` **or** `null`; the constructor produces `undefined` (by never assigning), while an extension filling the object from an LSP `Diagnostic` wire payload (whose JSON `null` `JSON.parse` preserves) produces `null`, and both MUST be treated identically as "not set".
- **diagnostic-decode-optional-field-malformed-refuses-whole-value**: `diagnostic(from:in:)` MUST return `nil` for the entire diagnostic — not silently drop just that field — when `source`, `code`, `relatedInformation`, or `tags` is present (neither `undefined` nor `null`) but fails to decode into its expected shape.
- **diagnostic-code-three-shapes**: `diagnosticCode(from:in:)` MUST decode a JS string as `.scalar(.string(...))`, a JS number as `.scalar(.number(...))`, and an object carrying a `value` property (itself a string or number) and a `target` property that decodes via `Uri.swift`'s `url(from:in:)` as `.link(value:target:)`; it MUST return `nil` for any value matching none of the three shapes.
- **related-information-array-decode-atomicity**: `diagnosticRelatedInformationArray(from:in:)` MUST use `VSCodeAPI.arrayLength(of:)` to determine the element count and MUST return `nil` for the entire array — not a partial array — if any element fails `diagnosticRelatedInformation(from:in:)`'s own decode.
- **tags-array-decode-atomicity**: `diagnosticTagArray(from:in:)` MUST use `VSCodeAPI.arrayLength(of:)` and MUST return `nil` for the entire array if any element is not a JS number or does not map to a defined `ExtensionDiagnosticTag` raw value (`1` or `2`; `0` is out of range).
- **tags-array-preserves-order**: `diagnosticTagArray(from:in:)` MUST preserve the JS array's element order in the returned `[ExtensionDiagnosticTag]`; it MUST NOT sort, deduplicate, or reverse the tags.
- **diagnostic-value-constructs-through-real-constructor**: `diagnosticValue(for:in:)` MUST build the result by calling the installed `Diagnostic` class's constructor with `(range, message, severity)` — never by assembling a plain object literal — so the returned value is genuinely `instanceof` `vscode.Diagnostic`.
- **diagnostic-value-optional-fields-set-only-when-present**: `diagnosticValue(for:in:)` MUST assign `source`, `code`, `relatedInformation`, and `tags` on the constructed instance only when the corresponding `ExtensionDiagnostic` field is non-`nil`; when a field is `nil`, the corresponding JS property MUST be left unassigned, not set to `null` or `undefined`.
- **diagnostic-value-propagates-nested-encode-failure**: `diagnosticValue(for:in:)` MUST return `nil` — without constructing a partially-filled result — if encoding `range`, any element of `relatedInformation`, or `code` fails (`rangeValue(for:in:)`, `diagnosticRelatedInformationValue(for:in:)`, or `diagnosticCodeJSValue(for:in:)` returning `nil`).
- **related-information-value-constructs-through-real-constructor**: `diagnosticRelatedInformationValue(for:in:)` MUST build the result by calling the installed `DiagnosticRelatedInformation` class's constructor with `(location, message)`, so the result is genuinely `instanceof` `vscode.DiagnosticRelatedInformation`.
- **swift-mirrors-are-sendable-value-types**: `ExtensionDiagnosticSeverity`, `ExtensionDiagnosticTag`, `ExtensionDiagnosticCodeValue`, `ExtensionDiagnosticCode`, `ExtensionDiagnosticRelatedInformation`, and `ExtensionDiagnostic` MUST each be declared `Sendable` and `Equatable`, so a decoded value MAY be passed across actor boundaries once it has left the `JSContext`.
- **no-instance-caching-of-decoded-values**: `diagnostic(from:in:)` and `diagnosticRelatedInformation(from:in:)` MUST decode fresh from the given `JSValue` on every call; neither function MUST cache or reuse a prior decode for the same underlying JS object.

## Appearance

Not applicable — this is a `JSContext` class-installer and Swift↔JS bridge, not a visual component.

## States

Not applicable — this is a `JSContext` class-installer and Swift↔JS bridge, not a visual component. Its only lifecycle-shaped behavior is the once-per-context installation and caching sequence, captured under Behavioral Requirements (**install-once-per-context**, **cache-write-optional**) rather than as a visual-state table.

## Accessibility

Not applicable — this is a `JSContext` class-installer and Swift↔JS bridge, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| diagnostic-types-001 | severity-forward-mapping, severity-reverse-mapping | Read `DiagnosticSeverity.Error`/`.Warning`/`.Information`/`.Hint` and `DiagnosticSeverity[0]`/`[1]`/`[2]`/`[3]` on an installed context | Forward reads are `0`, `1`, `2`, `3`; reverse reads are `"Error"`, `"Warning"`, `"Information"`, `"Hint"` — `DiagnosticTypesTests.diagnosticSeverityHasAllFourValuesByNumber` |
| diagnostic-types-002 | tag-forward-mapping, tag-reverse-mapping | Read `DiagnosticTag.Unnecessary`/`.Deprecated` and `DiagnosticTag[1]`/`[2]` | `Unnecessary == 1`, `Deprecated == 2`, neither is `0`; reverse reads are `"Unnecessary"`, `"Deprecated"` — `DiagnosticTypesTests.diagnosticTagHasBothValuesAndNeitherIsZero` |
| diagnostic-types-003 | diagnostic-constructor-severity-default | `new Diagnostic(new Range(0, 0, 0, 1), 'oops')` (no third argument) | `d.severity` is the JS number `0` (`typeof d.severity === 'number'`), not `undefined` — `DiagnosticTypesTests.diagnosticTwoArgConstructorDefaultsSeverityToError` |
| diagnostic-types-004 | diagnostic-constructor-severity-default | `new Diagnostic(new Range(0, 0, 0, 1), 'oops', DiagnosticSeverity.Hint)` | `d.severity === 3` | `DiagnosticTypesTests.diagnosticThreeArgConstructorHonoursExplicitHintSeverity` |
| diagnostic-types-005 | diagnostic-code-three-shapes | `d.code = 'E1234'` then `VSCodeAPI.diagnostic(from: d, in: context)` | Decodes to `.scalar(.string("E1234"))` — `DiagnosticTypesTests.diagnosticCodeAcceptsAPlainString` |
| diagnostic-types-006 | diagnostic-code-three-shapes | `d.code = 42` then decode | Decodes to `.scalar(.number(42))` — `DiagnosticTypesTests.diagnosticCodeAcceptsAPlainNumber` |
| diagnostic-types-007 | diagnostic-code-three-shapes | `d.code = { value: 'E1234', target: Uri.parse('https://example.com/e1234') }` then decode | Decodes to `.link(value: .string("E1234"), target: URL with absoluteString "https://example.com/e1234")` — `DiagnosticTypesTests.diagnosticCodeAcceptsAnObjectFormWithARealUriTarget` |
| diagnostic-types-008 | diagnostic-related-information-decode-fields, related-information-array-decode-atomicity | `d.relatedInformation = [new DiagnosticRelatedInformation(new Location(otherUri, new Range(2,0,2,3)), 'see here')]` then decode `d` | Decoded `relatedInformation` has one entry with `message == "see here"` and `location.uri.path == "/other.txt"`, `location.range` matching the constructed `Range` — `DiagnosticTypesTests.diagnosticRelatedInformationRoundTripsANestedLocation` |
| diagnostic-types-009 | tags-array-preserves-order | `d.tags = [DiagnosticTag.Deprecated, DiagnosticTag.Unnecessary]` then decode | Decoded `tags == [.deprecated, .unnecessary]`, in that exact order | `DiagnosticTypesTests.diagnosticTagsRoundTripPreservingOrder` |
| diagnostic-types-010 | classes-frozen-after-construction, instances-not-frozen | `Object.isFrozen(DiagnosticSeverity)`, `Object.isFrozen(Diagnostic)`, `Object.isFrozen(Diagnostic.prototype)`; then `DiagnosticSeverity.Error = 99` and re-read; then `DiagnosticRelatedInformation.prototype.tampered = 'yes'` | All three `isFrozen` checks are `true`; `DiagnosticSeverity.Error` still reads `0` after the tampering assignment; `'tampered' in DiagnosticRelatedInformation.prototype` is `false` — `DiagnosticTypesTests.everyDiagnosticClassAndPrototypeIsFrozen` |
| diagnostic-types-011 | diagnostic-related-information-decode-requires-real-instance | `VSCodeAPI.diagnosticRelatedInformation(from:in:)` on a plain `{ location: <real Location>, message: 'oops' }` object literal | Returns `nil` — `DiagnosticTypesTests.diagnosticRelatedInformationFromRefusesADuckTypedLiteral` |
| diagnostic-types-012 | diagnostic-related-information-decode-fields | `VSCodeAPI.diagnosticRelatedInformation(from:in:)` on a real `new DiagnosticRelatedInformation(location, 'oops')` | Returns a value with `message == "oops"` and `location.uri.path == "/a.txt"` — `DiagnosticTypesTests.diagnosticRelatedInformationFromReadsARealInstance` |
| diagnostic-types-013 | diagnostic-decode-requires-real-instance | `VSCodeAPI.diagnostic(from:in:)` on a plain `{ range: <real Range>, message: 'oops', severity: 0 }` object literal | Returns `nil` — `DiagnosticTypesTests.diagnosticFromRefusesADuckTypedLiteral` |
| diagnostic-types-014 | diagnostic-decode-required-fields | `VSCodeAPI.diagnostic(from:in:)` on a real `new Diagnostic(range, 'oops', DiagnosticSeverity.Warning)` | Returns a value with `message == "oops"`, `severity == .warning`, and `range` matching the constructed range — `DiagnosticTypesTests.diagnosticFromReadsARealInstance` |
| diagnostic-types-015 | related-information-value-constructs-through-real-constructor, diagnostic-related-information-decode-fields | `diagnosticRelatedInformationValue(for:in:)` on an `ExtensionDiagnosticRelatedInformation`, then check `instanceof DiagnosticRelatedInformation` and round-trip through `diagnosticRelatedInformation(from:in:)` | `instanceof` is `true`; the round-tripped value equals the original — `DiagnosticTypesTests.diagnosticRelatedInformationValueRoundTripsThroughTheReader` |
| diagnostic-types-016 | diagnostic-value-constructs-through-real-constructor, diagnostic-value-optional-fields-set-only-when-present | `diagnosticValue(for:in:)` on an `ExtensionDiagnostic` with `source`, a `.link` `code`, one `relatedInformation` entry, and two `tags` set, then check `instanceof Diagnostic` and round-trip through `diagnostic(from:in:)` | `instanceof` is `true`; the round-tripped value equals the original, including all four optional fields — `DiagnosticTypesTests.diagnosticValueRoundTripsThroughTheReaderWithAllOptionalFields` |
| diagnostic-types-017 | diagnostic-value-optional-fields-set-only-when-present | `diagnosticValue(for:in:)` on an `ExtensionDiagnostic` with `code == .scalar(.number(42))` and no other optional fields, then round-trip | Round-tripped value equals the original; the scalar `.link`-only fixture in vector 016 does not by itself cover this branch — `DiagnosticTypesTests.diagnosticValueRoundTripsAScalarCode` |
| diagnostic-types-018 | diagnostic-constructor-leaves-optionals-unassigned | `new Diagnostic(new Range(0,0,0,1), 'oops')`, then `'source' in d`/`Object.hasOwn(d, 'source')` for each of `source`, `code`, `relatedInformation`, `tags` | All eight checks are `false` — `DiagnosticTypesTests.diagnosticOptionalPropertiesAreAbsentNotUndefinedValued` |
| diagnostic-types-019 | diagnostic-decode-optional-field-malformed-refuses-whole-value | `d.source = 42` (a number, not a string) then `VSCodeAPI.diagnostic(from: d, in: context)` | Returns `nil` for the whole diagnostic — `DiagnosticTypesTests.diagnosticRefusesAMalformedSource` |
| diagnostic-types-020 | diagnostic-decode-optional-field-malformed-refuses-whole-value, diagnostic-code-three-shapes | `d.code = {}` (missing `value`/`target`) then decode | Returns `nil` — `DiagnosticTypesTests.diagnosticRefusesAMalformedCode` |
| diagnostic-types-021 | diagnostic-decode-optional-field-malformed-refuses-whole-value, related-information-array-decode-atomicity | `d.relatedInformation = [{ location: <real Location>, message: 'oops' }]` (a duck-typed element, not a real `DiagnosticRelatedInformation`) then decode | Returns `nil` for the whole diagnostic — `DiagnosticTypesTests.diagnosticRefusesAMalformedRelatedInformationElement` |
| diagnostic-types-022 | diagnostic-decode-optional-field-malformed-refuses-whole-value, tags-array-decode-atomicity | `d.tags = [0]` (`0` is out of `DiagnosticTag`'s range) then decode | Returns `nil` — `DiagnosticTypesTests.diagnosticRefusesAMalformedTagsElement` |

## Edge Cases

- **Null/empty input**: `message` argument to `Diagnostic`'s constructor as `''` (empty string) MUST throw `TypeError('message must be set')`, per **diagnostic-constructor-validates-message** (MUST) — traced to the constructor's falsy check, which an empty string satisfies the same way `null`/`undefined` would.
- **Null/empty input**: a `source`/`code`/`relatedInformation`/`tags` property that is `null` (not merely `undefined`) MUST decode as absent, identically to a genuinely unset property, per **diagnostic-decode-optional-field-absence** (MUST) — this is the shape an LSP-derived `Diagnostic` payload produces once round-tripped through `JSON.parse`.
- **Boundary values**: `severity` values outside `0`–`3` (e.g. `4`, `-1`, or a non-integer such as `1.5`) MUST fail `ExtensionDiagnosticSeverity(rawValue:)`'s construction and MUST cause `diagnostic(from:in:)` to return `nil` for the whole value, per **diagnostic-decode-required-fields** (MUST).
- **Boundary values**: a `tags` element equal to `0` MUST fail — `DiagnosticTag` declares no `0` case, per **tags-array-decode-atomicity** (MUST).
- **Boundary values**: a `relatedInformation` or `tags` array of exactly `VSCodeAPI.maximumDecodableArrayLength` (100,000) elements is the largest `VSCodeAPI.arrayLength(of:)` will accept; one element longer MUST cause `arrayLength(of:)` to return `nil`, which MUST cause the whole `relatedInformation`/`tags` array decode — and therefore the whole `diagnostic(from:in:)` call — to fail, with an error logged by `VSCodeAPI.arrayLength(of:)` itself (MUST).
- **Boundary values**: an array-like object carrying a numeric `length` property but for which `value.isArray` is `false` MUST be refused by `VSCodeAPI.arrayLength(of:)`, and therefore by `diagnosticRelatedInformationArray`/`diagnosticTagArray`, rather than walked by its reported length (MUST).
- **Concurrent access**: not applicable in the sense of requiring synchronization — every function in this file runs on the main actor (per **main-actor-isolation**), and `JSContext`/`JSValue` are not `Sendable`, so there is no path by which two calls into this file's functions execute concurrently against the same context; the compiler enforces this rather than any lock or queue in the source (MUST, per the type's own `@MainActor` declaration).
- **Error states**: `installDiagnosticTypes(in:)` failing for any of its three logged reasons (evaluate failure, JS-side `installedError`, or a missing container member) MUST leave `vscode.DiagnosticSeverity`/`DiagnosticTag`/`DiagnosticRelatedInformation`/`Diagnostic` as the shim's not-implemented stub for that context rather than raise a Swift error or a JS exception, per **install-failure-is-non-fatal** (MUST).
- **Error states**: a `Diagnostic` or `DiagnosticRelatedInformation` constructor call that throws (invalid `range`/`location`, or a falsy `message`) MUST propagate as a real JS `TypeError` to the extension's own calling code — this file performs no `try`/`catch` around the constructors themselves; only `diagnosticClassesSource`'s outer IIFE catches errors, and only during installation, not during later construction (MUST).
- **Offline or disconnected state**: not applicable — this file makes no network call and opens no file; every input it processes arrives already in memory as a `JSValue`.
- **Cancellation and timeouts**: not applicable — every function in this file is synchronous; there is no long-running operation to cancel or time out.
- **Missing file or unreachable server**: not applicable — this file has no filesystem or network dependency of its own; `Uri.swift`'s `url(from:in:)`, which `diagnosticCode(from:in:)`'s object-shape branch calls for `target`, decodes a value already resident in the `JSContext` rather than resolving it against a filesystem or server.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `context` | `JSContext` | none (required) | Every function in this file takes the target context explicitly; there is no ambient or singleton context. |
| `value` (readers) | `JSValue` | none (required) | The JS value to decode; `diagnostic(from:in:)`, `diagnosticRelatedInformation(from:in:)`, `diagnosticCode(from:in:)`, `diagnosticRelatedInformationArray(from:in:)`, and `diagnosticTagArray(from:in:)` all take one. |
| `diagnostic` / `relatedInformation` (writers) | `ExtensionDiagnostic` / `ExtensionDiagnosticRelatedInformation` | none (required) | The Swift value `diagnosticValue(for:in:)` / `diagnosticRelatedInformationValue(for:in:)` encodes back into a real JS instance. |
| `VSCodeAPI.maximumDecodableArrayLength` | `Int` | `100_000` | Declared in `VSCodeAPI.swift`; the ceiling `VSCodeAPI.arrayLength(of:)` enforces for any array this file walks (`relatedInformation`, `tags`). Not settable per call. |
| `severity` (constructor's 3rd argument) | JS number or `undefined` | `DiagnosticSeverity.Error` (`0`) when omitted | Read by `Diagnostic`'s constructor; an explicit `0` is preserved and distinguished from "omitted" via `typeof`. |
| `ExtensionDiagnostic.severity` (Swift initializer) | `ExtensionDiagnosticSeverity` | `.error` | `ExtensionDiagnostic.init`'s own default parameter value, mirroring the JS constructor's default. |

## Deep Linking

Not applicable: `DiagnosticTypes.swift` defines no URL, route, or navigable destination — it installs JS classes and bridges values, with no navigation surface of its own.

## Localization

- **hardcoded-error-messages**: The three `TypeError` messages this file's constructors throw — `"location must be a vscode.Location"`, `"range must be a vscode.Range"`, and `"message must be set"` — are hardcoded English string literals with no localization key or `String(localized:)` call. They are visible to the extension author, not to the app's own end-user UI, per the file's own doc comment framing these as validation surfaced to "the extension" that made the mistake.
- **hardcoded-log-strings**: The three `logger.error` messages in `installDiagnosticTypes(in:)` (evaluate failure, JS-side `installedError`, missing container member) are hardcoded English `Logger` interpolated strings, also unlocalized.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `location must be a vscode.Location` | `DiagnosticRelatedInformation`'s constructor, thrown when `location` fails the `instanceof` check. |
| (none — literal only) | `range must be a vscode.Range` | `Diagnostic`'s constructor, thrown when `range` fails the `instanceof` check. |
| (none — literal only) | `message must be set` | `Diagnostic`'s constructor, thrown when `message` is falsy. |
| (none — literal only) | `Could not install the 'vscode.DiagnosticSeverity'/'vscode.DiagnosticTag'/'vscode.DiagnosticRelatedInformation'/'vscode.Diagnostic' classes in context '<name>'; they stay the shim's not-implemented stub` | `installDiagnosticTypes(in:)`, logged on an evaluate failure. |
| (none — literal only) | `Could not install the 'vscode.DiagnosticSeverity'/'vscode.DiagnosticTag'/'vscode.DiagnosticRelatedInformation'/'vscode.Diagnostic' classes in context '<name>': '<error>'; they stay the shim's not-implemented stub` | `installDiagnosticTypes(in:)`, logged on a JS-side `installedError`. |
| (none — literal only) | `The 'vscode' diagnostic-types container in context '<name>' is missing one of 'DiagnosticSeverity', 'DiagnosticTag', 'DiagnosticRelatedInformation' or 'Diagnostic'; all four stay the shim's not-implemented stub` | `installDiagnosticTypes(in:)`, logged when the container is missing an expected member. |

## Accessibility Options

Not applicable: `DiagnosticTypes.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; the four declarations it installs are always available once `installDiagnosticTypes(in:)` succeeds for a context.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; its only telemetry-adjacent calls are the three `logger.error` lines covered under Logging, which are diagnostic logging, not analytics events.

## Privacy

- **Data collected**: `DiagnosticTypes.swift` collects no data of its own; it decodes and re-encodes whatever `range`, `message`, `severity`, `source`, `code`, `relatedInformation`, and `tags` values an extension or the host already holds, without retaining a copy beyond the return value of each call.
- **Storage**: this file performs no storage of its own; a decoded `ExtensionDiagnostic` is only as persistent as whatever the caller (outside this file's given sources) does with the returned value.
- **Transmission**: this file makes no network call; it neither sends nor receives anything over a network.
- **Retention**: nothing in this file is retained beyond the lifetime of one function call's local variables, except the per-context installed-class cache (`__vscodeDiagnosticTypesClasses`), which holds only class/prototype objects, never a diagnostic's data.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `VSCodeAPI` (the shared logger declared once in `VSCodeAPI.swift` and reused by every `VSCodeAPI` extension file, including this one)

| Event | Level | Message |
|-------|-------|---------|
| `context.evaluateScript(diagnosticClassesSource)` returns `nil` or a non-object | error | `Could not install the 'vscode.DiagnosticSeverity'/'vscode.DiagnosticTag'/'vscode.DiagnosticRelatedInformation'/'vscode.Diagnostic' classes in context '<name>'; they stay the shim's not-implemented stub` |
| The evaluated result carries a non-undefined `installedError` | error | `Could not install the 'vscode.DiagnosticSeverity'/'vscode.DiagnosticTag'/'vscode.DiagnosticRelatedInformation'/'vscode.Diagnostic' classes in context '<name>': '<installedError>'; they stay the shim's not-implemented stub` |
| The installed container is missing one of the four expected members | error | `The 'vscode' diagnostic-types container in context '<name>' is missing one of 'DiagnosticSeverity', 'DiagnosticTag', 'DiagnosticRelatedInformation' or 'Diagnostic'; all four stay the shim's not-implemented stub` |
| An array passed to `VSCodeAPI.arrayLength(of:)` (via `diagnosticRelatedInformationArray`/`diagnosticTagArray`) reports a length over 100,000 | error | (logged inside `VSCodeAPI.swift`'s shared `arrayLength(of:)`, not inside this file): `refusing an array of <count> elements: longer than the 100000 this host decodes` |

No other event in this file is logged: neither a constructor's `TypeError` nor a reader's `nil` return for a malformed field is logged at the point it occurs — both are facts the code surfaces to the caller (as a thrown JS error, or as a `nil` Swift value) instead of a log line, per **diagnostic-constructor-validates-range**/**diagnostic-constructor-validates-message** and **diagnostic-decode-optional-field-malformed-refuses-whole-value**.

## Platform Notes

- **SwiftUI**: not applicable to this file — `DiagnosticTypes.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing here renders or observes view state.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/DiagnosticTypes.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is an extension of `VSCodeAPI`, itself `@MainActor`, and its consumers among the given sources are the JS-side `vscode.languages` diagnostics collection machinery and `MainThreadDiagnostics` (not among the given sources), which reads decoded `ExtensionDiagnostic` values back through `diagnostic(from:in:)`.
- **Compose**: model the four installed declarations as Kotlin: `DiagnosticSeverity`/`DiagnosticTag` as enum classes with an explicit numeric `value` property (Kotlin enums do not compile to a bidirectional-mapping object the way `tsc` does, so a small companion-object lookup table is needed to reproduce **severity-reverse-mapping**/**tag-reverse-mapping**), and `DiagnosticRelatedInformation`/`Diagnostic` as `data class`es whose "constructor" is a factory function performing the same `range`/`location`/`message` validation and throwing an `IllegalArgumentException` in place of a JS `TypeError`. The "never assign `undefined`" contract (**diagnostic-constructor-leaves-optionals-unassigned**) has no direct Kotlin analogue on a `data class`; model it with nullable properties defaulted to `null` and treat "absent" and "explicitly null" as the same case throughout, mirroring **diagnostic-decode-optional-field-absence**.
- **React/Web**: this is closest to the actual runtime shape — extension code in the real VS Code product already runs against the genuine `vscode.d.ts` declarations these mirror. A React/Web host embedding a similar extension bridge would decode/encode the same four shapes across whatever serialization boundary (e.g. `postMessage` to a worker) replaces this file's `JSContext` boundary, and would need the same "refuse the whole value on any malformed optional field" discipline (**diagnostic-decode-optional-field-malformed-refuses-whole-value**) when deserializing untrusted extension-authored data.
- **WinUI 3**: model `DiagnosticSeverity`/`DiagnosticTag` as `public enum DiagnosticSeverity { Error = 0, Warning = 1, Information = 2, Hint = 3 }` (a real C# enum already gives the forward mapping; `Enum.GetName(typeof(DiagnosticSeverity), value)` reproduces the reverse mapping on demand rather than needing a hand-built table). Model `DiagnosticRelatedInformation` and `Diagnostic` as `sealed record`s or plain classes whose constructors validate `location`/`range` with `is Location`/`is Range` pattern-matching (WinUI 3's `Location`/`Range` equivalents) and throw `ArgumentException` in place of a JS `TypeError`, matching **diagnostic-constructor-validates-location** and **diagnostic-constructor-validates-range**. `ExtensionDiagnosticCode`'s three-shape union (`code?: string | number | { value: string | number; target: Uri }`) has no built-in C# union type; model it as a small discriminated `abstract record CodeValue` with `Scalar`/`Link` subtypes, the direct analogue of the Swift `enum ExtensionDiagnosticCode { case scalar(...); case link(...) }` this file declares. `System.Text.Json.JsonSerializer` with a custom converter is the .NET equivalent of this file's manual `diagnosticCode(from:in:)`/`diagnosticCodeJSValue(for:in:)` pair, since the WinUI host would decode extension-authored diagnostics from a JSON-shaped bridge rather than a `JSValue`. The "assign only when present, never `null`/`undefined`" contract (**diagnostic-value-optional-fields-set-only-when-present**) maps to `JsonIgnoreCondition.WhenWritingNull` combined with nullable reference types, so an absent field is omitted from serialized output rather than written as `null`.

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
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
