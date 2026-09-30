<!-- leaf: implement-status-web-src-lib-1/err--edge-cases · source: status-web-src-lib-err.md -->

# Error Message

**Rules** (cite as `implement-status-web-src-lib-1/err--edge-cases#<slug>`):

- `empty-message` MUST — An Error with an empty message MUST yield ""; msg does not substitute a fallback, so callers that display it alone (for …
- `null-and-undefined` MUST — A thrown null or undefined MUST yield "null" or "undefined" as literal text.
- `object-with-a-message-field` MUST — A non-Error object such as a JSON error body { message: "..." } MUST yield "[object Object]"; the message field is not …
- `cross-realm-error` MUST — An Error constructed in another realm MUST take the string branch and yield the standard Error string form ("Error: …
- `symbol` MUST — A thrown Symbol("x") MUST yield "Symbol(x)", since String converts symbols without throwing.
- `unconvertible-value` MUST — An object with no prototype (Object.create(null)) or whose toString throws MUST cause msg to throw the conversion …
- `error-subclass-overriding-message` MUST — An Error subclass whose message getter returns a non-string MUST have that value returned as-is; msg does not coerce …

## Edge Cases

- **Empty message**: An `Error` with an empty `message` MUST yield `""`; `msg` does not substitute a fallback, so callers that display it alone (for example `ConfigPanel.tsx` setting the refresh error to `msg(e)`) show an empty error text.
- **Null and undefined**: A thrown `null` or `undefined` MUST yield "null" or "undefined" as literal text.
- **Object with a message field**: A non-`Error` object such as a JSON error body `{ message: "..." }` MUST yield "[object Object]"; the `message` field is not read.
- **Cross-realm Error**: An `Error` constructed in another realm MUST take the string branch and yield the standard `Error` string form ("Error: boom"), which includes the name, unlike the same-realm result.
- **Symbol**: A thrown `Symbol("x")` MUST yield "Symbol(x)", since `String` converts symbols without throwing.
- **Unconvertible value**: An object with no prototype (`Object.create(null)`) or whose `toString` throws MUST cause `msg` to throw the conversion error; `msg` does not catch it, so the exception propagates out of the caller's `catch` block.
- **Error subclass overriding message**: An `Error` subclass whose `message` getter returns a non-string MUST have that value returned as-is; `msg` does not coerce `message`, and the `string` return type is not enforced at runtime.
- **Concurrent access**: Not applicable — `msg` is a stateless pure function in single-threaded JavaScript; concurrent calls cannot interfere.
- **Offline or disconnected state**: Not applicable — `msg` performs no network access; it only renders errors that network failures produce elsewhere.
