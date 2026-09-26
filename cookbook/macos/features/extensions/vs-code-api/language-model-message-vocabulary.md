---
id: 4d04037c-098f-4ea5-8313-7e0374700a96
title: LanguageModelMessageVocabulary
domain: agentictoolkit://cookbook/macos/features/extensions/vs-code-api/language-model-message-vocabulary
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The VSCodeAPI extension installing the eight vscode.LanguageModel* value
  types an extension constructs to talk to a language model, in one JSContext evaluation.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- language-model
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/extensions/host
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/ai-plugin-language-model-provider
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/LanguageModelMessageVocabulary.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/LanguageModelMessageVocabularyTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Host/ExtensionHost.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

# LanguageModelMessageVocabulary

## Overview

`LanguageModelMessageVocabulary.swift` is a `VSCodeAPI` extension that gives the extension host's embedded `JSContext` real, `instanceof`-checkable implementations of the eight value types an extension *constructs* when it talks to a language model — `vscode.LanguageModelChatMessageRole`, `LanguageModelChatMessage`, `LanguageModelToolCallPart`, `LanguageModelToolResultPart`, `LanguageModelTextPart`, `LanguageModelPromptTsxPart`, `LanguageModelToolResult`, and `LanguageModelDataPart` — measured against `vscode.d.ts` and `extHostTypes.ts` at the pinned commit `3addbda66f9e80c3ed1b943822ab823bb6747b02`. Nothing that *calls* a model (`selectChatModels`, `LanguageModelChat`, `countTokens`, `sendRequest`) is in scope; those are built on top of the eight members this file installs. All eight are built in one evaluated source, in one closure, under one cached global, because `LanguageModelChatMessage`'s `content` setter constructs a `LanguageModelTextPart`, and `LanguageModelDataPart.json`/`.text` construct a `LanguageModelDataPart` through a shared UTF-8 encoder — all three need to see each other and the encoder as ordinary lexical bindings, not re-find one another off `globalThis`. The source deliberately narrows three places where `vscode.d.ts`'s stable declaration and `extHostTypes.ts`'s implementation disagree, or where the implementation carries a PROPOSED-API member not present in the stable declaration: `LanguageModelChatMessageRole` has exactly `User`/`Assistant`, never the PROPOSED `System`; `LanguageModelToolResultPart` has no `isError`; and neither `LanguageModelTextPart` nor `LanguageModelDataPart` has an `audience` field. `LanguageModelDataPart.json`'s default mime is `'text/x-json'` (not `application/json`, which is what `vscode.d.ts`'s own doc comment prose claims), and its JSON is tab-indented; `LanguageModelDataPart.text`'s default mime is `'text/plain'`. Neither factory's explicit `mime` argument, when given, is overridden. No member defines a `toJSON`, since upstream's carries `$mid` values for an extension-host RPC marshalling layer this host has no reader for.

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
- **chat-message-name-defaults-undefined**: When `LanguageModelChatMessage.User`/`.Assistant` is called without a `name` argument, the constructed message's `name` MUST be `undefined` (`typeof message.name === 'undefined'`), not any other default value.
- **chat-message-name-passthrough**: When `LanguageModelChatMessage.User`/`.Assistant` is called with a `name` argument, the constructed message's `name` MUST equal that argument.
- **content-part-type-not-runtime-checked**: `LanguageModelChatMessage`'s `content` setter MUST NOT validate that array elements match the role-specific part types `vscode.d.ts` documents (a `LanguageModelToolResultPart` inside a `User` message's content, or a `LanguageModelToolCallPart` inside an `Assistant` message's, are both accepted at runtime), matching that upstream enforces this distinction only at the TypeScript type-checking layer.
- **classes-frozen-after-construction**: `LanguageModelTextPart`, `LanguageModelPromptTsxPart`, `LanguageModelToolCallPart`, `LanguageModelToolResultPart`, `LanguageModelToolResult`, `LanguageModelDataPart`, and `LanguageModelChatMessage` MUST each be frozen via `Object.freeze`, and each of their seven `.prototype` objects MUST also be frozen, all inside the same evaluation that builds them, with no window in which any of the fourteen is unfrozen.
- **instances-not-frozen**: No instance of any of the seven constructor functions MUST be frozen; `role`, `name`, `content`, `value`, `callId`, `input`, `data`, and `mimeType` MUST all remain writable on a constructed instance after construction.
- **no-tojson-method**: None of the eight installed members MUST define a `toJSON` method; `vscode.d.ts` declares none, and this host has no reader for the extension-host RPC marshalling shape (`$mid`) upstream's own `toJSON` produces.

## Appearance

Not applicable — this is a `JSContext` class-installer, not a visual component.

## States

Not applicable — this is a `JSContext` class-installer, not a visual component. Its only lifecycle-shaped behavior is the once-per-context installation and caching sequence, captured under Behavioral Requirements (**install-once-per-context**, **cache-write-optional**, **member-presence-check-runs-every-call**) rather than as a visual-state table.

## Accessibility

Not applicable — this is a `JSContext` class-installer, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| vocab-001 | chat-message-content-setter-runs-post-construction | `new LanguageModelChatMessage(1, [], undefined)` then `message.content = 'replaced'` | `Array.isArray(message.content)` and `message.content.length === 1` — `LanguageModelMessageVocabularyTests.contentSetterReCoercesAStringAfterConstruction` |
| vocab-002 | chat-message-content-setter-string-coercion, text-part-stores-value | `LanguageModelChatMessage.User('hello')` | `content` is an array of length 1 whose element `instanceof LanguageModelTextPart` with `.value === 'hello'` — `LanguageModelMessageVocabularyTests.contentCoercionWrapsAStringInATextPartWithTheGivenValue` |
| vocab-003 | chat-message-user-factory, chat-message-assistant-factory | `LanguageModelChatMessage.User('hi').role` and `LanguageModelChatMessage.Assistant('hi').role` | `1` and `2` respectively — `LanguageModelMessageVocabularyTests.userAndAssistantSetDistinctRoleValues` |
| vocab-004 | data-part-json-factory-default-mime | `LanguageModelDataPart.json({ a: 1 })` | `part.mimeType === 'text/x-json'` — `LanguageModelMessageVocabularyTests.jsonDefaultMimeIsTextXJsonNotApplicationJson` |
| vocab-005 | data-part-json-factory-serialization | `LanguageModelDataPart.json({ a: 1, b: 2 })`, decode `.data`'s bytes back to a string | Decoded string equals `JSON.stringify({a:1,b:2}, undefined, '\t')` exactly — `LanguageModelMessageVocabularyTests.jsonStringifiesTabIndentedNotCompact` |
| vocab-006 | data-part-text-factory-default-mime | `LanguageModelDataPart.text('hello')` | `part.mimeType === 'text/plain'` — `LanguageModelMessageVocabularyTests.textDefaultMimeIsTextPlain` |
| vocab-007 | data-part-explicit-mime-override | `LanguageModelDataPart.json({a:1}, 'application/custom+json')` and `LanguageModelDataPart.text('hello', 'text/custom')` | `mimeType` is `'application/custom+json'` and `'text/custom'` respectively — `LanguageModelMessageVocabularyTests.explicitMimeOverridesTheDefaultForJsonAndText` |
| vocab-008 | role-enum-shape | `Object.keys(LanguageModelChatMessageRole)`, `.User`, `.Assistant`, `.System`, `Object.isFrozen(...)` | `keys.length === 2`, `User === 1`, `Assistant === 2`, `typeof System === 'undefined'`, frozen is `true` — `LanguageModelMessageVocabularyTests.roleEnumHasExactlyTwoMembers` |
| vocab-009 | classes-frozen-after-construction | Construct one instance of each of the seven constructor functions, check `instanceof` and `Object.isFrozen` on the constructor and its prototype | Every `instanceof` is `true`; every constructor and prototype is frozen — `LanguageModelMessageVocabularyTests.constructedPartsAreRealInstancesAndClassesAreFrozen` |
| vocab-010 | chat-message-name-defaults-undefined | `LanguageModelChatMessage.User('hi').name` | `typeof name === 'undefined'` — `LanguageModelMessageVocabularyTests.nameDefaultsToUndefinedWhenOmitted` |
| vocab-011 | utf8-encoder-two-and-three-byte-ranges, data-part-text-factory-encoding | `LanguageModelDataPart.text('€')` (the Euro sign, U+20AC) | `.data.length === 3` and bytes equal `0xE2, 0x82, 0xAC` — `LanguageModelMessageVocabularyTests.textDataBytesAreUtf8Encoded` |
| vocab-012 | data-part-constructor-stores-fields-by-reference | `new LanguageModelDataPart(new Uint8Array([9,8,7,6]), 'application/octet-stream')` | `.data === original` (same reference), `.data.length === 4`, `.data[0] === 9`, `.data[3] === 6` — `LanguageModelMessageVocabularyTests.uint8ArrayRoundTripsUnchangedThroughConstructorToData` |
| vocab-013 | instances-not-frozen, chat-message-role-name-not-accessors | `LanguageModelChatMessage.User('hello')` then `message.role = 2; message.name = 'changed';` | Both assignments succeed and read back as assigned — `LanguageModelMessageVocabularyTests.chatMessageRoleAndNameRemainAssignableAfterConstruction` |
| vocab-014 | tool-call-part-stores-fields, tool-call-part-input-shape-unconstrained | `new LanguageModelToolCallPart('call-1', 'the-tool', { a: 1 })` | `.callId === 'call-1'`, `.name === 'the-tool'`, `.input.a === 1` — `LanguageModelMessageVocabularyTests.toolCallPartStoresItsThreeArgumentsUnderTheirOwnNames` |
| vocab-015 | tool-result-part-stores-fields, tool-result-stores-content | `new LanguageModelToolResultPart('call-1', [textPart])` and `new LanguageModelToolResult([textPart])` | Both `.content` arrays have length 1 with `.content[0] === textPart` — `LanguageModelMessageVocabularyTests.toolResultPartAndToolResultStoreTheGivenContent` |
| vocab-016 | prompt-tsx-part-stores-value | `new LanguageModelPromptTsxPart('some-tsx').value` | `=== 'some-tsx'` — `LanguageModelMessageVocabularyTests.promptTsxPartStoresTheGivenValue` |
| vocab-017 | chat-message-name-passthrough | `LanguageModelChatMessage.User('hi', 'bob').name` and `.Assistant('hi', 'alice').name` | `'bob'` and `'alice'` respectively — `LanguageModelMessageVocabularyTests.userAndAssistantPassTheNameArgumentThrough` |
| vocab-018 | utf8-encoder-unpaired-surrogate | `LanguageModelDataPart.text('\uD800')` (a lone high surrogate) | `.data.length === 3` and bytes equal `0xEF, 0xBF, 0xBD` — `LanguageModelMessageVocabularyTests.unpairedSurrogateEncodesAsTheReplacementCharacter` |
| vocab-019 | data-part-image-factory | `LanguageModelDataPart.image(bytes, 'image/jpeg')` | `.data === bytes` (same reference), `.mimeType === 'image/jpeg'` — `LanguageModelMessageVocabularyTests.imageStoresTheGivenDataAndMimeType` |
| vocab-020 | members-returned-as-dictionary, member-presence-check-runs-every-call | Call `installLanguageModelVocabulary(in: freshContext)` on a `JSContext()` with nothing installed | Returns a non-`nil` `[String: JSValue]` with exactly the eight keys `LanguageModelChatMessageRole`, `LanguageModelChatMessage`, `LanguageModelToolCallPart`, `LanguageModelToolResultPart`, `LanguageModelTextPart`, `LanguageModelPromptTsxPart`, `LanguageModelToolResult`, `LanguageModelDataPart`, each an object value — the precondition `LanguageModelMessageVocabularyTests.makeContext()` relies on before every other test in the suite runs |
| vocab-021 | install-once-per-context | Call `installLanguageModelVocabulary(in: context)` twice on the same `JSContext`, comparing `LanguageModelTextPart` from each call via `context.evaluateScript("... === ...")` | The two calls' `LanguageModelTextPart` values are the identical JS object (`===` is `true`); the source is evaluated once, not twice |
| vocab-022 | install-evaluate-failure | `context.evaluateScript("Object.freeze = function () { throw new Error('boom'); };")`, then call `installLanguageModelVocabulary(in: context)` | Returns `nil`; `VSCodeAPI.logger` logs one error containing "Could not install"; no `vscode.LanguageModel*` global is defined |
| vocab-023 | install-missing-member, install-missing-member-reports-first-only | Install successfully once, then `context.evaluateScript("delete globalThis.__vscodeLanguageModelVocabulary.LanguageModelChatMessage; delete globalThis.__vscodeLanguageModelVocabulary.LanguageModelDataPart;")`, then call `installLanguageModelVocabulary(in: context)` again | Returns `nil`; the logged error names `LanguageModelChatMessage` only (declared before `LanguageModelDataPart` in `languageModelVocabularyMemberNames`), not `LanguageModelDataPart` |
| vocab-024 | cache-write-optional | `context.evaluateScript("Object.defineProperty(globalThis, '__vscodeLanguageModelVocabulary', { value: 1, writable: false, configurable: false });")` before ever calling install, then call `installLanguageModelVocabulary(in: context)` | Returns a non-`nil` dictionary with all eight members for this one call (the fresh evaluation's own return value), even though the trailing cache-write `Object.defineProperty` inside the source throws on the already-non-configurable key and is silently caught |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `context` | `JSContext` | none (required) | `installLanguageModelVocabulary(in:)` takes the target context explicitly; there is no ambient or singleton context. |
| `languageModelVocabularyGlobalName` | `String` (fixed constant) | `"__vscodeLanguageModelVocabulary"` | The global key `installLanguageModelVocabulary(in:)` caches the built container under; not settable per call. |
| `languageModelVocabularyMemberNames` | `[String]` (fixed constant) | the eight names in `vscode.d.ts`'s declared order | Used both to validate the resolved container's shape and, on a missing member, to name the first one missing in the log; not settable per call. |
| `mime` (`LanguageModelDataPart.json`'s 2nd argument) | JS string or `undefined` | `'text/x-json'` when omitted | Explicit values are used verbatim, per **data-part-explicit-mime-override**. |
| `mime` (`LanguageModelDataPart.text`'s 2nd argument) | JS string or `undefined` | `'text/plain'` when omitted | Explicit values are used verbatim, per **data-part-explicit-mime-override**. |
| `mime` (`LanguageModelDataPart.image`'s 2nd argument) | JS string or `undefined` | none — passed straight through, `undefined` if omitted | Unlike `.json`/`.text`, `.image` applies no default, per **data-part-image-factory**. |
| `name` (`LanguageModelChatMessage`'s 3rd constructor argument, and `.User`/`.Assistant`'s 2nd) | JS string or `undefined` | `undefined` when omitted | Per **chat-message-name-defaults-undefined**. |

## Deep Linking

Not applicable: `LanguageModelMessageVocabulary.swift` defines no URL, route, or navigable destination — it installs JS value-type constructors and has no navigation surface of its own.

## Localization

- **hardcoded-log-strings**: The two `logger.error` messages in `installLanguageModelVocabulary(in:)` (an evaluate failure, and a missing container member) are hardcoded English `Logger` interpolated strings with no localization key or `String(localized:)` call. Unlike `DiagnosticTypes.swift`'s equivalent installer, this file's inner catch never surfaces the underlying JavaScript error's own message, so there is no third, error-message-carrying log variant to localize.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `Could not install the 'vscode' language-model message vocabulary in context '<name>'; every member stays the shim's not-implemented stub` | `installLanguageModelVocabulary(in:)`, logged when `context.evaluateScript(languageModelVocabularySource)` returns `nil` or a non-object. |
| (none — literal only) | `The 'vscode' language-model message vocabulary in context '<name>' is missing '<memberName>'; every member stays the shim's not-implemented stub` | `installLanguageModelVocabulary(in:)`, logged when the container is missing an expected member. |

## Accessibility Options

Not applicable: `LanguageModelMessageVocabulary.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; the eight declarations it installs are always available once `installLanguageModelVocabulary(in:)` succeeds for a context.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; its only telemetry-adjacent calls are the two `logger.error` lines covered under Logging, which are diagnostic logging, not analytics events.

## Privacy

- **Data collected**: `LanguageModelMessageVocabulary.swift` collects no data of its own; it constructs value objects out of whatever `role`, `content`, `name`, `callId`, `input`, `data`, and `mimeType` values an extension already supplies, without retaining a copy beyond the returned instance and the per-context class cache.
- **Storage**: this file performs no persistent storage of its own; a constructed `LanguageModelChatMessage`/`LanguageModelDataPart`/etc. is only as persistent as whatever the caller (outside this file's given sources) does with it.
- **Transmission**: this file makes no network call; it neither sends nor receives anything over a network. The message and part values it constructs may later be transmitted to a language model by code outside this file's scope (5.7a-ii/5.7b), which this recipe does not cover.
- **Retention**: nothing in this file is retained beyond the lifetime of one function call's local variables, except the per-context installed-class cache (`__vscodeLanguageModelVocabulary`), which holds only the eight constructor/enum objects, never a message's or part's data.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `VSCodeAPI` (the shared logger declared once in `VSCodeAPI.swift` and reused by every `VSCodeAPI` extension file, including this one)

| Event | Level | Message |
|-------|-------|---------|
| `context.evaluateScript(languageModelVocabularySource)` returns `nil` or a non-object | error | `Could not install the 'vscode' language-model message vocabulary in context '<name>'; every member stays the shim's not-implemented stub` |
| The resolved container is missing one of the eight expected members | error | `The 'vscode' language-model message vocabulary in context '<name>' is missing '<memberName>'; every member stays the shim's not-implemented stub` |

No other event in this file is logged: the failed cache-write `Object.defineProperty` inside `languageModelVocabularySource` is caught and silently ignored (per **cache-write-optional**), and no constructor in this file throws or logs on any input, since none of the eight members validates its arguments.

## Platform Notes

- **SwiftUI**: not applicable to this file — `LanguageModelMessageVocabulary.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing here renders or observes view state.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/LanguageModelMessageVocabulary.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is an extension of the `@MainActor` `VSCodeAPI` enum; its confirmed consumers among the repository's other files are `ExtensionHost.installRuntime`, which installs the eight members eagerly on every activation via the shared, sorted `installVSCodeMembers(_:onto:)` loop, and `MainThreadLanguageModels.swift`'s `vscode.lm` adaptor, which calls `installLanguageModelVocabulary(in:)` again per streamed request to read the cached container back — both outside this recipe's scope.
- **Compose**: model the eight members as Kotlin: `LanguageModelChatMessageRole` as an enum class with an explicit numeric `value` property (Kotlin enums do not compile to the bidirectional-mapping object shape a JS numeric enum can; this type has no reverse mapping to reproduce, only the two forward values). Model the seven constructor functions as `data class`es whose constructors perform no validation, matching **tool-call-part-stores-fields** / **tool-result-part-stores-fields** / etc. Model `LanguageModelChatMessage.content` as a Kotlin property with a custom setter performing the same `is String` coercion into a single-element `LanguageModelTextPart` list, matching **chat-message-content-setter-string-coercion**; a `data class`'s freeze-after-construction is not directly reproducible on the class itself (Kotlin has no `Object.freeze` analogue for a class), so the "frozen class" contract (**classes-frozen-after-construction**) has no direct Kotlin equivalent beyond documenting it as an implementation note.
- **React/Web**: this is closest to the actual runtime shape — extension code in the real VS Code product already runs against the genuine `vscode.d.ts` declarations this file mirrors. A React/Web host embedding a similar extension bridge would construct the same eight shapes directly as plain ES classes (no `JSContext` boundary to cross), and would reproduce the "single evaluation, shared lexical scope" requirement (**single-evaluation-builds-all-eight**) simply by defining all eight in one module.
- **WinUI 3**: model `LanguageModelChatMessageRole` as `public enum LanguageModelChatMessageRole { User = 1, Assistant = 2 }` — a real C# enum gives the forward mapping directly, matching **role-enum-shape**. Model the seven constructor-function equivalents as plain mutable classes (not `init`-only `record`s, which would make properties immutable after construction and violate **instances-not-frozen**) with public settable properties and no constructor-time validation. Model `LanguageModelChatMessage.Content`'s coercing setter as an ordinary C# property setter that checks `is string` and wraps it in a single-element `List<LanguageModelTextPart>`, the direct analogue of **chat-message-content-setter-string-coercion**; `Role` and `Name` stay plain auto-properties, matching **chat-message-role-name-not-accessors**. Model `LanguageModelDataPart.Json`/`.Text` as static factory methods using `System.Text.Json.JsonSerializer.Serialize` for the payload and `System.Text.Encoding.UTF8.GetBytes` for the bytes — note that `JsonSerializerOptions.WriteIndented` defaults to two-space indentation, not tabs, so matching **data-part-json-factory-serialization** byte-for-byte requires a custom `JsonWriterOptions` with a tab `IndentCharacter`; `Encoding.UTF8.GetBytes` already replaces an unpaired surrogate with U+FFFD by default, reproducing **utf8-encoder-unpaired-surrogate** with no extra code. There is no `Object.freeze` equivalent in .NET; a WinUI 3 port has no way to reproduce **classes-frozen-after-construction**'s "the class itself is frozen" contract and would need to document that gap explicitly rather than silently drop it.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/LanguageModelMessageVocabulary.swift` |

## Design Decisions

**Decision**: All eight members are constructed inside one evaluated IIFE rather than eight independent `evaluateScript` calls, one per member.
**Rationale**: `LanguageModelChatMessage`'s `content` setter constructs a `LanguageModelTextPart`, and `LanguageModelDataPart.json`/`.text` construct a `LanguageModelDataPart` through the shared `utf8EncodeToUint8Array` function; all three need to see each other as ordinary lexical bindings inside the same closure rather than re-finding one another off `globalThis` on every call, which would also reintroduce the exact per-call re-lookup cost the single-cached-container pattern (shared with `Uri.swift`'s `installUriClass(in:)`) exists to avoid.
**Approved**: pending

**Decision**: `LanguageModelDataPart.image` applies no default `mime` when the argument is omitted, while `.json` and `.text` both default theirs.
**Rationale**: not stated in the source's comments beyond the line-by-line `vscode.d.ts`/`extHostTypes.ts` citations for the file as a whole; there is no single natural default MIME type for arbitrary image bytes the way `'text/x-json'` and `'text/plain'` serve `.json`/`.text`, and the given sources include no upstream citation specific to `.image`'s own default behavior. This recipe states the observed behavior — no default is applied — as a requirement (**data-part-image-factory**) rather than inferring a rationale the source does not give.
**Approved**: pending

**Decision**: a present-but-malformed value is never checked by any of the eight members' constructors — `input`, `content`, `data`, and `value` are all stored exactly as given, with no `TypeError` path anywhere in this file, unlike the validating constructors in `DiagnosticTypes.swift`.
**Rationale**: matches `extHostTypes.ts`'s own implementation for these eight declarations, none of which validates its constructor arguments (only `Diagnostic` and `DiagnosticRelatedInformation`, in a different file, do). Adding validation here that upstream does not have would diverge from the vocabulary this file exists to mirror.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because this file's only responsibility is installing eight JS declarations in a `JSContext`; it defines no UI, no networking, and no persistence, and depends on nothing outside `Foundation`/`JavaScriptCore`/`OSLog`/`AgenticToolkitCore`. `unit-test-coverage` passes: `LanguageModelMessageVocabularyTests.swift`'s nineteen test methods exercise all ten of the task brief's numbered mutation points plus several additional property checks (the four previously-unread constructors' field storage, the UTF-8 surrogate-pair and unpaired-surrogate branches, and `.image`'s pass-through), per that file's own header. `explicit-error-handling` is partial: the failure is signalled — `installLanguageModelVocabulary(in:)` logs an error and every member stays the shim's not-implemented stub — but the inner `try`/`catch` discards the caught JavaScript `error`, so the log cannot say which member failed or why. `secure-log-output` passes: both logged messages carry only the context's own name (already `privacy: .public` in the source) and a member name drawn from a fixed, non-secret constant list; neither message can carry a credential, token, or extension-authored PII. `no-hardcoded-strings` fails because both `logger.error` messages are English literals with no localization mechanism (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
