<!-- leaf: implement-extension-host-vs-1/code-api-language-model-message-vocabulary--edge-cases · source: extension-host-vs-code-api-language-model-message-vocabulary.md -->

# LanguageModelMessageVocabulary

**Rules** (cite as `implement-extension-host-vs-1/code-api-language-model-message-vocabulary--edge-cases#<slug>`):

- `null-empty-input` MUST — LanguageModelChatMessage's constructor called with content omitted (undefined) MUST store undefined unchanged as …
- `null-empty-input-2` MUST — LanguageModelTextPart/LanguageModelPromptTsxPart constructed with value as an empty string ('') MUST store '' …
- `null-empty-input-3` MUST — LanguageModelDataPart.json(undefined) MUST NOT throw or produce empty bytes; JSON.stringify(undefined, undefined, '\t') …
- `boundary-values` MUST — a code point of exactly 0x7F MUST encode as one byte and 0x80 MUST encode as two bytes — the boundary between …
- `boundary-values-2` MUST — a code point of exactly 0xFFFF MUST encode as three bytes (the top of the non-surrogate three-byte range), while a …
- `boundary-values-3` MUST — a high surrogate (0xD800–0xDBFF) at the last index of the input string, with no following code unit to pair with, MUST …
- `concurrent-access` MUST — not applicable in the sense of requiring synchronization — every function this file adds runs on the main actor (per …
- `error-states` MUST — installLanguageModelVocabulary(in:) failing for either of its two logged reasons (evaluate failure or a missing …

## Edge Cases

- **Null/empty input**: `LanguageModelChatMessage`'s constructor called with `content` omitted (`undefined`) MUST store `undefined` unchanged as `_content`, since `typeof undefined !== 'string'` takes the passthrough branch of **chat-message-content-setter-passthrough** (MUST).
- **Null/empty input**: `LanguageModelTextPart`/`LanguageModelPromptTsxPart` constructed with `value` as an empty string (`''`) MUST store `''` unchanged; neither constructor treats an empty string as absent or invalid, per **text-part-stores-value**/**prompt-tsx-part-stores-value** (MUST).
- **Null/empty input**: `LanguageModelDataPart.json(undefined)` MUST NOT throw or produce empty bytes; `JSON.stringify(undefined, undefined, '\t')` evaluates to the JS value `undefined` (not a string), and `utf8EncodeToUint8Array(undefined)` then runs `String(undefined)`, encoding the nine-character literal text `"undefined"` as its bytes — per **data-part-json-factory-serialization** (MUST), traced directly to `JSON.stringify`'s own documented behavior on `undefined` composed with `String()`'s coercion inside the encoder.
- **Boundary values**: a code point of exactly `0x7F` MUST encode as one byte and `0x80` MUST encode as two bytes — the boundary between **utf8-encoder-single-byte-range** and **utf8-encoder-two-and-three-byte-ranges** (MUST).
- **Boundary values**: a code point of exactly `0xFFFF` MUST encode as three bytes (the top of the non-surrogate three-byte range), while a combined surrogate pair decoding to `0x10000` MUST encode as four bytes — the boundary between **utf8-encoder-two-and-three-byte-ranges** and **utf8-encoder-surrogate-pairs** (MUST).
- **Boundary values**: a high surrogate (`0xD800`–`0xDBFF`) at the last index of the input string, with no following code unit to pair with, MUST take the unpaired-surrogate branch (`0xEF 0xBF 0xBD`), not read past the end of the string, per **utf8-encoder-unpaired-surrogate** (MUST).
- **Concurrent access**: not applicable in the sense of requiring synchronization — every function this file adds runs on the main actor (per **main-actor-isolation**), and `JSContext`/`JSValue` are not `Sendable`, so no two calls into this file's functions can execute concurrently against the same context; the compiler enforces this via `VSCodeAPI`'s own `@MainActor` declaration rather than a lock or queue in this file (MUST).
- **Concurrent access / cache identity**: if some other code has already defined an object under the global name `__vscodeLanguageModelVocabulary` on a context before `installLanguageModelVocabulary(in:)` first runs on it, this function adopts that pre-existing object as the cached container without any way to verify it is the genuine vocabulary this file built — the same residual behavior `Uri.swift`'s `installUriClass(in:)` documents for its own global, generalized here to a container object (per this file's own header comment; not independently re-verified against `Uri.swift`'s text in this recipe).
- **Error states**: `installLanguageModelVocabulary(in:)` failing for either of its two logged reasons (evaluate failure or a missing container member) MUST leave every `vscode.LanguageModel*` global as the shim's not-implemented stub for that context rather than raise a Swift error or a JS exception, per **install-failure-is-non-fatal** (MUST).
- **Error states**: the source's own inner `try`/`catch` around all class construction and freezing discards the caught JavaScript `error` entirely and returns the JS value `null`, so `installLanguageModelVocabulary(in:)` logs only its generic evaluate-failure message, with no record of which member failed or why (unlike `DiagnosticTypes.swift`'s installer, which captures `installedError`).
- **Offline or disconnected state**: not applicable — this file makes no network call and opens no file; every input it processes (a role, a content value, a `Uint8Array`, a mime string) arrives already resident in the `JSContext`.
- **Cancellation and timeouts**: not applicable — every function this file adds is synchronous; there is no long-running operation to cancel or time out.
- **Missing file or unreachable server**: not applicable — this file has no filesystem or network dependency of its own.
