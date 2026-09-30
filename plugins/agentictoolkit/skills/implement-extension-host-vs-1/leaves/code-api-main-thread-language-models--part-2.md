<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-language-models--part-2 · source: extension-host-vs-code-api-main-thread-language-models.md -->

# MainThreadLanguageModels — continued (part 2)

**Rules** (cite as `implement-extension-host-vs-1/code-api-main-thread-language-models--part-2#<slug>`):

- `main-actor-isolation` MUST
- `provider-seam-injected` MUST
- `chat-descriptor-fields` MUST
- `message-role-vocabulary` MUST
- `response-part-cases` MUST
- `snapshot-seeded-at-init` MUST
- `dispose-marks-disposed-first` MUST
- `dispose-rejects-outstanding-waiters` MUST
- `dispose-cancels-pumps` MUST
- `dispose-removes-event-listener` MUST
- `dispose-retains-live-requests` MUST
- `select-chat-models-torn-down-response` MUST
- `select-chat-models-empty-result` MUST
- `selector-absent-matches-all` MUST
- `selector-empty-object-matches-all` MUST
- `selector-non-object-matches-all` MUST
- `selector-fields-are-a-conjunction` MUST
- `chat-model-object-readonly-getters` MUST
- `chat-model-object-dropped-on-bridge-failure` MUST
- `count-tokens-string-argument` MUST
- `count-tokens-message-argument` MUST
- `count-tokens-content-string-fallback` MUST
- `count-tokens-empty-fallback` MUST
- `array-length-bound` MUST
- `array-length-real-arrays-only` MUST
- `send-request-torn-down-response` MUST
- `send-request-context-unavailable` MUST
- `send-request-role-validation` MUST
- `send-request-role-exact-integer` MUST
- `send-request-system-role-ledgered` MUST
- `send-request-justification-passthrough` MUST
- `send-request-degraded-options-ledgered` MUST
- `send-request-cancelled-before-start` MUST
- `send-request-cancellation-duck-typed` MUST
- `send-request-seam-throw-rejects` MUST
- `send-request-response-object-build-failure` MUST
- `send-request-stored-before-pump` MUST
- `response-object-two-members` MUST
- `tee-single-pump` MUST
- `tee-independent-cursors` MUST

## Behavioral Requirements

- **main-actor-isolation**: `MainThreadLanguageModels`, `ExtensionLanguageModelProviding`, `LanguageModelCancellation`, and `LanguageModelResponseRequest` MUST be `@MainActor`-isolated, with every stored property read, mutation, and method body confined to the main actor.
- **provider-seam-injected**: `init(provider:notImplementedLedger:extensionIdentifier:)` MUST store the given `ExtensionLanguageModelProviding` conformer as the sole source of chat models and streamed responses; this file MUST NOT construct or reach a model provider of its own.
- **chat-descriptor-fields**: `LanguageModelChatDescriptor` MUST be `Sendable` and `Equatable` and MUST expose exactly six stored properties — `name`, `id`, `vendor`, `family`, `version`, `maxInputTokens` — mirroring `vscode.LanguageModelChat`'s six readonly properties.
- **message-role-vocabulary**: `ExtensionLanguageModelMessage.Role` MUST have exactly two cases, `.user` (raw value `1`) and `.assistant` (raw value `2`), matching `vscode.LanguageModelChatMessageRole`'s two implemented values.
- **response-part-cases**: `ExtensionLanguageModelResponsePart` MUST have exactly three cases — `.text(String)`, `.toolCall(id:name:argumentsJSON:)`, and `.end(stopReason:)` — and each MUST be `Sendable`.
- **snapshot-seeded-at-init**: `init(provider:notImplementedLedger:extensionIdentifier:)` MUST seed `lastModelIdentifiers` from `provider.availableChatModels` at construction time; it MUST NOT leave that snapshot empty and rely on the first `availableChatModelsDidChange()` call to populate it.
- **dispose-marks-disposed-first**: `dispose()` MUST set `isDisposed = true` before performing any other teardown step.
- **dispose-rejects-outstanding-waiters**: `dispose()` MUST reject every live request's outstanding `next()` waiter, on both the `stream` and `text` cursors, with the torn-down wording, before cancelling any pump.
- **dispose-cancels-pumps**: `dispose()` MUST cancel every live request's pump task after rejecting its outstanding waiters.
- **dispose-removes-event-listener**: `dispose()` MUST remove this adaptor's own subscription from `onDidChangeChatModelsEmitter`.
- **dispose-retains-live-requests**: `dispose()` MUST NOT clear `liveRequests`; a request whose promise already resolved MUST stay reachable so a `next()` call issued after `dispose()` gets a proper rejection rather than an answer built on deallocated state.
- **select-chat-models-torn-down-response**: `vscode.lm.selectChatModels`'s implementation MUST reject its returned promise, never raise or answer, when invoked after `dispose()` or after this adaptor has deallocated.
- **select-chat-models-empty-result**: When no chat model matches the given selector, `selectChatModels` MUST resolve with an empty array; it MUST NOT reject, throw, or record a `NotImplementedLedger` access.
- **selector-absent-matches-all**: `selectChatModels()` called with no argument MUST match every model in `provider.availableChatModels`.
- **selector-empty-object-matches-all**: `selectChatModels({})` MUST also match every model, through the same "every field unconstrained" path as the no-argument call.
- **selector-non-object-matches-all**: A selector argument that is present but not a JS object MUST be treated as imposing no constraint, matching every model, rather than causing an error.
- **selector-fields-are-a-conjunction**: `LanguageModelChatSelectorCriteria.matches(_:)` MUST require every field the criteria value actually sets (`vendor`, `family`, `version`, `id`) to equal the model's corresponding property; a model matching only some of the set fields MUST be excluded.
- **chat-model-object-readonly-getters**: `makeChatModelObject(for:of:in:)` MUST install `name`, `id`, `vendor`, `family`, `version`, and `maxInputTokens` as readonly getter properties on the returned JS object; assigning to any of the six from JavaScript MUST be a silent no-op that leaves the original value unchanged.
- **chat-model-object-dropped-on-bridge-failure**: When `JSValue(newObjectIn:)` fails to build the JS object for a matched model, `handleSelectChatModels` MUST log an error and drop that model from the resolved array rather than failing the whole `selectChatModels` call.
- **count-tokens-string-argument**: `countTokens` called with a bare JS string MUST count that string's whitespace-delimited words as `approximateTokenCount`'s result.
- **count-tokens-message-argument**: `countTokens` called with a `LanguageModelChatMessage`-shaped object MUST read its `content` property as an array and sum the whitespace-delimited word counts of every element whose `value` is a string; it MUST NOT read `content` as a plain string when the argument is a message object.
- **count-tokens-content-string-fallback**: When a message-shaped argument's `content` property is itself a JS string rather than an array, `extractedText(from:)` MUST count that string directly rather than treating it as an empty array.
- **count-tokens-empty-fallback**: `extractedText(from:)` MUST return an empty string for an absent argument, a non-string non-object argument, or an object with no `content` property, so `countTokens` answers `0` rather than raising.
- **array-length-bound**: `arrayElements(of:)` MUST decline to read any JS value whose reported `length` exceeds `VSCodeAPI.maximumDecodableArrayLength` (100,000), answering `nil` rather than reserving unbounded capacity.
- **array-length-real-arrays-only**: `arrayElements(of:)` MUST require the argument to satisfy `isArray`; an object that merely carries a numeric `length` property (including a JS string) MUST read as absent, not as that many `undefined` elements.
- **send-request-torn-down-response**: `sendRequest` MUST return a rejected promise, never a synchronous throw, when called after `dispose()`.
- **send-request-context-unavailable**: When no `JSContext` is current at the moment `sendRequest` is invoked, `handleSendRequest(for:)` MUST return `nil`, since there is no context in which to construct even a rejected promise.
- **send-request-role-validation**: `sendRequest` MUST reject the whole call when any message's `role` is neither `1` nor `2`; it MUST NOT process a partial message list or silently skip the offending message.
- **send-request-role-exact-integer**: A message `role` MUST be read via an exact `Int32` conversion (`Int32(exactly:)`) of its numeric value, never `toInt32()`; a fractional value or a value outside `Int32`'s range that would wrap under ECMA-262 `ToInt32` semantics MUST be rejected as unsupported rather than rounded or wrapped into a valid role.
- **send-request-system-role-ledgered**: When a message's `role` is exactly `3` (`vscode.LanguageModelChatMessageRole.System`, declared upstream but unimplemented here), the rejection path MUST additionally record that role into `notImplementedLedger` for this adaptor's `extensionIdentifier`; no other unsupported role value MUST be recorded.
- **send-request-justification-passthrough**: `sendRequest`'s `options.justification`, when present, MUST be passed to `provider.streamResponse(for:messages:justification:extensionIdentifier:)` unchanged; nothing in this file interprets or gates on its content.
- **send-request-degraded-options-ledgered**: When `options.modelOptions`, `options.tools`, or `options.toolMode` is present (not absent, `undefined`, or `null`), `sendRequest` MUST record the corresponding member path into `notImplementedLedger`; presence alone is recorded, never the option's content, and an honoured `CancellationToken` MUST NOT be recorded as a degraded option.
- **send-request-cancelled-before-start**: A `CancellationToken` that is already cancelled when `sendRequest` is called MUST reject the returned promise before `provider.streamResponse` is invoked.
- **send-request-cancellation-duck-typed**: `LanguageModelCancellation` MUST read a cancellation token by duck-typing exactly the two members `isCancellationRequested` and `onCancellationRequested`; a token that is absent, is not an object, or whose `onCancellationRequested` is not callable MUST leave the request permanently un-cancelled rather than failing the call.
- **send-request-seam-throw-rejects**: When `provider.streamResponse` throws, `sendRequest`'s promise MUST reject with that error's description; it MUST NOT propagate as a synchronous throw.
- **send-request-response-object-build-failure**: When `LanguageModelResponseRequest.makeResponseObject(in:)` returns `nil`, `sendRequest` MUST remove the request from `liveRequests` and reject the promise, and MUST NOT start the pump.
- **send-request-stored-before-pump**: A `LanguageModelResponseRequest` MUST be inserted into `liveRequests` before its pump `Task` is started, so a part arriving on the pump's first loop iteration always has a live owner to record into.
- **response-object-two-members**: The object `sendRequest`'s promise resolves with MUST expose exactly two members, `stream` and `text`, each an async-iterable built by `makeAsyncIterable(kind:in:)`.
- **tee-single-pump**: `startPump(consuming:)` MUST run exactly one `Task` per request that drains the provider's stream into `buffer`; `stream` and `text` MUST read from that same buffer through independent cursors rather than each consuming the provider's stream directly.
- **tee-independent-cursors**: Iterating only one of `stream`/`text` to completion, or neither, MUST leave the other cursor's completion state unaffected; a cursor that is never iterated MUST NOT block or alter delivery on the cursor that is.
