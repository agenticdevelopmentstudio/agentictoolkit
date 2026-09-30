<!-- leaf: implement-extension-host-vs-1/code-api-diagnostic-types--part-2 · source: extension-host-vs-code-api-diagnostic-types.md -->

# DiagnosticTypes — continued (part 2)

**Rules** (cite as `implement-extension-host-vs-1/code-api-diagnostic-types--part-2#<slug>`):

- `main-actor-isolation` MUST
- `install-once-per-context` MUST
- `cache-write-optional` MUST
- `install-evaluate-failure` MUST
- `install-js-side-error` MUST
- `install-missing-member` MUST
- `install-failure-is-non-fatal` MUST
- `severity-forward-mapping` MUST
- `severity-reverse-mapping` MUST
- `tag-forward-mapping` MUST
- `tag-reverse-mapping` MUST
- `enum-objects-are-plain-and-frozen` MUST
- `classes-frozen-after-construction` MUST
- `instances-not-frozen` MUST
- `related-information-constructor-validates-location` MUST
- `diagnostic-constructor-validates-range` MUST
- `diagnostic-constructor-validates-message` MUST
- `diagnostic-constructor-severity-default` MUST
- `diagnostic-constructor-leaves-optionals-unassigned` MUST
- `geometry-classes-resolved-lazily` MUST
- `diagnostic-related-information-decode-requires-real-instance` MUST
- `diagnostic-related-information-decode-fields` MUST
- `diagnostic-decode-requires-real-instance` MUST
- `diagnostic-decode-required-fields` MUST
- `diagnostic-decode-optional-field-absence` MUST
- `diagnostic-decode-optional-field-malformed-refuses-whole-value` MUST
- `diagnostic-code-three-shapes` MUST
- `related-information-array-decode-atomicity` MUST
- `tags-array-decode-atomicity` MUST
- `tags-array-preserves-order` MUST
- `diagnostic-value-constructs-through-real-constructor` MUST
- `diagnostic-value-optional-fields-set-only-when-present` MUST
- `diagnostic-value-propagates-nested-encode-failure` MUST

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
