<!-- leaf: implement-extension-host-vs-1/code-api-js-value-bridge--edge-cases · source: extension-host-vs-code-api-js-value-bridge.md -->

# JSValueBridge

**Rules** (cite as `implement-extension-host-vs-1/code-api-js-value-bridge--edge-cases#<slug>`):

- `null-empty-input` MUST — an empty values array to array(of:in:)/arrayOrNull(of:in:) MUST produce an empty JavaScript array, never …
- `error-states` MUST — when the underlying JavaScriptCore constructor (JSValue(undefinedIn:), JSValue(object:in:), or …

## Edge Cases

- **Null/empty input**: an empty `values` array to `array(of:in:)`/`arrayOrNull(of:in:)` MUST produce an empty JavaScript array, never `undefined`/`NSNull()` (**empty-array-is-empty-not-missing**). The empty string to `stringOrNull(_:in:)` or `stringOptionalField(_:)` MUST be treated as a real value, not an absence (**string-or-null-value**, **string-field-empty-is-a-value**). A `nil` operand to `stringOptionalField(_:)` (no property at all was passed) MUST return `nil` (**string-field-read-without-coercion**).
- **Boundary values**: not applicable — no function in this file constrains `values`, `message`, or `path` to a minimum or maximum length, count, or numeric range; none is declared in the source.
- **Concurrent access**: not applicable to `JSValueBridge` itself — it holds no stored state and every member is a pure function of its arguments (**pure-value-construction**), so there is nothing for two calls to race over. Its `JSContext`/`JSValue` parameters are non-Sendable classes, so the Swift compiler already confines any one instance of them to whichever isolation domain created it before this bridge is ever called (**no-actor-isolation-declared**); every real call site in this codebase happens to be `@MainActor`.
- **Error states**: when the underlying JavaScriptCore constructor (`JSValue(undefinedIn:)`, `JSValue(object:in:)`, or `JSValue(newErrorFromMessage:in:)`) returns `nil`, each `*OrNull`/`Any`-returning member MUST fall back to `NSNull()` and each `JSValue?`-returning member MUST return `nil` (**undefined-value**, **undefined-or-null-value**, **array-construction**, **array-or-null-construction**, **string-or-null-value**). When `reject.context` is `nil` or `JSValue(newErrorFromMessage:in:)` fails, `rejectWithError(_:message:)` MUST take no action and produce no signal to any caller (**reject-with-error-silent-when-context-gone**) — this is documented in the source's own comment as deliberate, not an oversight.
- **Offline/disconnected state**: not applicable — this file performs no network or file-system I/O; every member only constructs or reads in-memory `JSValue` objects already resident in a `JSContext` the caller supplies.
