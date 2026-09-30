<!-- leaf: implement-status-web-src-lib-1/err--test-vectors · source: status-web-src-lib-err.md -->

# Error Message

## Conformance Test Vectors

No test file exists for `err.ts` in the source (`src/lib` has no `err.test.ts`); these vectors are derived from the function body and standard `String` conversion semantics.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| err-001 | error-message-passthrough | `new Error("boom")` | `"boom"` |
| err-002 | error-message-passthrough, error-name-omitted | `new TypeError("bad arg")` | `"bad arg"` (no "TypeError: " prefix) |
| err-003 | error-message-passthrough | `new Error("")` | `""` (empty string) |
| err-004 | string-identity, non-error-string-conversion | `"network down"` | `"network down"` |
| err-005 | nullish-conversion | `null` | `"null"` |
| err-006 | nullish-conversion | `undefined` | `"undefined"` |
| err-007 | non-error-string-conversion | `42` | `"42"` |
| err-008 | plain-object-conversion, instanceof-discrimination | `{ message: "x" }` | `"[object Object]"` |
| err-009 | non-error-string-conversion | an object whose `toString` returns `"custom"` | `"custom"` |
| err-010 | purity | an `Error` instance, called twice | same string both times; the error object's own properties are unchanged |
| err-011 | no-prefixing, no-truncation | `new Error("  padded  ")` | `"  padded  "` exactly |
| err-012 | export-name | import from `lib/err` | a function named `msg` is exported |
