<!-- leaf: implement-extension-host-vs-1/code-api-diagnostic-types--edge-cases · source: extension-host-vs-code-api-diagnostic-types.md -->

# DiagnosticTypes

**Rules** (cite as `implement-extension-host-vs-1/code-api-diagnostic-types--edge-cases#<slug>`):

- `null-empty-input` MUST — message argument to Diagnostic's constructor as '' (empty string) MUST throw TypeError('message must be set'), per …
- `null-empty-input-2` MUST — a source/code/relatedInformation/tags property that is null (not merely undefined) MUST decode as absent, identically …
- `boundary-values` MUST — severity values outside 0–3 (e.g. 4, -1, or a non-integer such as 1.5) MUST fail …
- `boundary-values-2` MUST — a tags element equal to 0 MUST fail — DiagnosticTag declares no 0 case, per tags-array-decode-atomicity (MUST).
- `boundary-values-3` MUST — a relatedInformation or tags array of exactly VSCodeAPI.maximumDecodableArrayLength (100,000) elements is the largest …
- `boundary-values-4` MUST — an array-like object carrying a numeric length property but for which value.isArray is false MUST be refused by …
- `concurrent-access` MUST — not applicable in the sense of requiring synchronization — every function in this file runs on the main actor (per …
- `error-states` MUST — installDiagnosticTypes(in:) failing for any of its three logged reasons (evaluate failure, JS-side installedError, or a …
- `error-states-2` MUST — a Diagnostic or DiagnosticRelatedInformation constructor call that throws (invalid range/location, or a falsy message) …

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
