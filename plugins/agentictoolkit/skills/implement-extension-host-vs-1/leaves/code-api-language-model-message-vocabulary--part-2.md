<!-- leaf: implement-extension-host-vs-1/code-api-language-model-message-vocabulary--part-2 · source: extension-host-vs-code-api-language-model-message-vocabulary.md -->

# LanguageModelMessageVocabulary — continued (part 2)

**Rules** (cite as `implement-extension-host-vs-1/code-api-language-model-message-vocabulary--part-2#<slug>`):

- `main-actor-isolation` MUST
- `install-once-per-context` MUST
- `cache-write-optional` MUST
- `member-presence-check-runs-every-call` MUST
- `install-evaluate-failure` MUST
- `install-missing-member` MUST
- `install-missing-member-reports-first-only` MUST
- `install-failure-is-non-fatal` MUST
- `members-returned-as-dictionary` MUST
- `single-evaluation-builds-all-eight` MUST
- `role-enum-shape` MUST
- `text-part-stores-value` MUST
- `prompt-tsx-part-stores-value` MUST
- `tool-call-part-stores-fields` MUST
- `tool-call-part-input-shape-unconstrained` MUST
- `tool-result-part-stores-fields` MUST
- `tool-result-stores-content` MUST
- `data-part-constructor-stores-fields-by-reference` MUST
- `data-part-image-factory` MUST
- `data-part-json-factory-default-mime` MUST
- `data-part-json-factory-serialization` MUST
- `data-part-text-factory-default-mime` MUST
- `data-part-text-factory-encoding` MUST
- `data-part-explicit-mime-override` MUST
- `utf8-encoder-single-byte-range` MUST
- `utf8-encoder-two-and-three-byte-ranges` MUST
- `utf8-encoder-surrogate-pairs` MUST
- `utf8-encoder-unpaired-surrogate` MUST
- `chat-message-constructor-fields` MUST
- `chat-message-content-setter-string-coercion` MUST
- `chat-message-content-setter-passthrough` MUST
- `chat-message-content-setter-runs-post-construction` MUST
- `chat-message-role-name-not-accessors` MUST
- `chat-message-user-factory` MUST
- `chat-message-assistant-factory` MUST

## Behavioral Requirements

- **main-actor-isolation**: Every function this file adds MUST execute on the main actor; `VSCodeAPI` is declared `@MainActor`, a caseless `enum` with no state of its own, because `JSContext`/`JSValue` are not `Sendable` and JavaScriptCore always calls back on the thread that made the call — the type carries its isolation in its own declaration, and this file adds no conformance of its own.
- **install-once-per-context**: `installLanguageModelVocabulary(in:)` MUST evaluate `languageModelVocabularySource` at most once for a given `JSContext`; on a context that already carries an object-valued cached container under the global name `__vscodeLanguageModelVocabulary`, it MUST reuse that cached container rather than re-evaluating the source.
- **cache-write-optional**: When caching the freshly built container under `__vscodeLanguageModelVocabulary` via `Object.defineProperty` fails (a context that refuses the define, e.g. because that key is already a non-configurable property), the evaluation MUST still return the freshly built `vocabulary` object for that one call rather than treat the failed cache write as an error; the failure is caught and silently ignored, with nothing logged for it.
- **member-presence-check-runs-every-call**: Whether the container comes from the cache or a fresh evaluation, `installLanguageModelVocabulary(in:)` MUST re-check, on every call, that all eight names in `languageModelVocabularyMemberNames` (`LanguageModelChatMessageRole`, `LanguageModelChatMessage`, `LanguageModelToolCallPart`, `LanguageModelToolResultPart`, `LanguageModelTextPart`, `LanguageModelPromptTsxPart`, `LanguageModelToolResult`, `LanguageModelDataPart`) resolve to an object-valued property of the container.
- **install-evaluate-failure**: `installLanguageModelVocabulary(in:)` MUST return `nil`, and MUST log an error via `VSCodeAPI.logger`, when `context.evaluateScript(languageModelVocabularySource)` returns a value that is `nil` or not an object — which includes the case where the evaluated IIFE's own `try`/`catch` caught an internal error and returned the JS value `null`.
- **install-missing-member**: `installLanguageModelVocabulary(in:)` MUST return `nil`, and MUST log an error via `VSCodeAPI.logger` naming the missing member, when the resolved container is missing an object-valued property for one of the eight names in `languageModelVocabularyMemberNames`.
- **install-missing-member-reports-first-only**: When more than one of the eight names is missing or non-object, `installLanguageModelVocabulary(in:)` MUST name only the first missing member encountered in `languageModelVocabularyMemberNames`'s declared order in the log message and MUST return `nil` immediately, without checking the remaining names.
- **install-failure-is-non-fatal**: `installLanguageModelVocabulary(in:)` MUST return `nil` rather than throw a Swift error or crash on any installation failure, so a context where installation fails is recoverable: `vscode.LanguageModelChatMessageRole`/`LanguageModelChatMessage`/`LanguageModelToolCallPart`/`LanguageModelToolResultPart`/`LanguageModelTextPart`/`LanguageModelPromptTsxPart`/`LanguageModelToolResult`/`LanguageModelDataPart` simply stay the shim's not-implemented stub for that context.
- **members-returned-as-dictionary**: On success, `installLanguageModelVocabulary(in:)` MUST return a `[String: JSValue]` keyed by the eight member names; it MUST NOT guarantee that any iteration of the returned dictionary preserves `languageModelVocabularyMemberNames`'s declared order.
- **single-evaluation-builds-all-eight**: `languageModelVocabularySource` MUST construct all eight members inside one evaluated IIFE so that `LanguageModelChatMessage`'s `content` setter can reference `LanguageModelTextPart`, and `LanguageModelDataPart.json`/`.text` can reference the shared `utf8EncodeToUint8Array` function, as ordinary lexical bindings rather than by re-finding each other off `globalThis`.
- **role-enum-shape**: The installed `LanguageModelChatMessageRole` object MUST be a plain, frozen object (not a JS class) exposing exactly two own enumerable keys, `User === 1` and `Assistant === 2`; it MUST NOT define a `System` member.
- **text-part-stores-value**: `LanguageModelTextPart`'s constructor MUST assign its single argument to `this.value` with no validation or transformation.
- **prompt-tsx-part-stores-value**: `LanguageModelPromptTsxPart`'s constructor MUST assign its single argument to `this.value` with no validation or transformation.
- **tool-call-part-stores-fields**: `LanguageModelToolCallPart`'s constructor MUST assign its three arguments to `this.callId`, `this.name`, and `this.input` respectively, under those exact property names and in that argument order, with no validation.
- **tool-call-part-input-shape-unconstrained**: `LanguageModelToolCallPart`'s `input` property MUST accept and store any JS value as given; the constructor MUST NOT enforce that `input` is an object, matching that `vscode.d.ts` declares `input` as `object` while `extHostTypes.ts`'s implementation types it `any` and neither is checked at runtime.
- **tool-result-part-stores-fields**: `LanguageModelToolResultPart`'s constructor MUST assign its two arguments to `this.callId` and `this.content` respectively, with no `isError` field and no validation of `content`'s shape.
- **tool-result-stores-content**: `LanguageModelToolResult`'s constructor MUST assign its single argument to `this.content` with no validation.
- **data-part-constructor-stores-fields-by-reference**: `LanguageModelDataPart`'s constructor MUST assign its two arguments to `this.data` and `this.mimeType` by reference, with no copy and no validation that `data` is a `Uint8Array`.
- **data-part-image-factory**: `LanguageModelDataPart.image(data, mime)` MUST return `new LanguageModelDataPart(data, mime)`, passing both arguments straight through with no default applied to `mime` when it is omitted, unlike `.json` and `.text`.
- **data-part-json-factory-default-mime**: `LanguageModelDataPart.json(value, mime)` MUST default `mimeType` to `'text/x-json'` exactly when `mime === undefined`; it MUST NOT default to `'application/json'`.
- **data-part-json-factory-serialization**: `LanguageModelDataPart.json(value, mime)` MUST serialize `value` via `JSON.stringify(value, undefined, '\t')` (tab-indented, not compact) and MUST encode the resulting string as UTF-8 bytes via `utf8EncodeToUint8Array` before storing it in `data`.
- **data-part-text-factory-default-mime**: `LanguageModelDataPart.text(value, mime)` MUST default `mimeType` to `'text/plain'` exactly when `mime === undefined`.
- **data-part-text-factory-encoding**: `LanguageModelDataPart.text(value, mime)` MUST encode `value` as UTF-8 bytes via `utf8EncodeToUint8Array` before storing it in `data`.
- **data-part-explicit-mime-override**: When `mime` is not `undefined`, both `LanguageModelDataPart.json` and `LanguageModelDataPart.text` MUST use the given value verbatim as `mimeType` instead of their respective default.
- **utf8-encoder-single-byte-range**: `utf8EncodeToUint8Array` MUST encode a code point below `0x80` as one byte equal to the code point.
- **utf8-encoder-two-and-three-byte-ranges**: `utf8EncodeToUint8Array` MUST encode a code point in `0x80`–`0x7FF` as two bytes and a code point in `0x800`–`0xFFFF` (excluding surrogate values) as three bytes, using the standard UTF-8 continuation-byte bit pattern (`0x80 | (value & 0x3F)` per continuation byte).
- **utf8-encoder-surrogate-pairs**: `utf8EncodeToUint8Array` MUST combine a valid high surrogate (`0xD800`–`0xDBFF`) immediately followed by a valid low surrogate (`0xDC00`–`0xDFFF`) into one code point above `0xFFFF` and encode it as four bytes, consuming both UTF-16 code units.
- **utf8-encoder-unpaired-surrogate**: `utf8EncodeToUint8Array` MUST encode an unpaired high or low surrogate — one with no matching partner adjacent to it — as the three-byte UTF-8 replacement character sequence `0xEF 0xBF 0xBD` (U+FFFD), matching the `TextEncoder` behavior `extHostTypes.ts`'s `VSBuffer.fromString` relies on; it MUST NOT emit the raw three-byte surrogate code unit, which is not valid UTF-8.
- **chat-message-constructor-fields**: `LanguageModelChatMessage`'s constructor MUST assign `role` directly to `this.role`, assign `content` through `this.content = content` (routing through the `content` accessor's setter, not a duplicated coercion), and assign `name` directly to `this.name`.
- **chat-message-content-setter-string-coercion**: `LanguageModelChatMessage.prototype`'s `content` setter MUST, when the assigned value's `typeof` is `'string'`, store `[new LanguageModelTextPart(value)]` as the backing `_content`.
- **chat-message-content-setter-passthrough**: `LanguageModelChatMessage.prototype`'s `content` setter MUST, when the assigned value's `typeof` is not `'string'` (including `undefined`, an array, or any object), store the value unchanged as the backing `_content`, with no further validation of its shape.
- **chat-message-content-setter-runs-post-construction**: The string-coercion behavior of the `content` setter MUST apply identically to an assignment made after construction (`message.content = 'x'`) as it does to the value passed into the constructor, since both paths go through the same property setter.
- **chat-message-role-name-not-accessors**: `role` and `name` on `LanguageModelChatMessage` MUST remain plain, writable, non-accessor data properties; only `content` MUST be defined as an accessor pair.
- **chat-message-user-factory**: `LanguageModelChatMessage.User(content, name)` MUST return `new LanguageModelChatMessage(LanguageModelChatMessageRole.User, content, name)`.
- **chat-message-assistant-factory**: `LanguageModelChatMessage.Assistant(content, name)` MUST return `new LanguageModelChatMessage(LanguageModelChatMessageRole.Assistant, content, name)`.
