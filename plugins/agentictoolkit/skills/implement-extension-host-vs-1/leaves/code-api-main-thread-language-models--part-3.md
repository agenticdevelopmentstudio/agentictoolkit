<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-language-models--part-3 · source: extension-host-vs-code-api-main-thread-language-models.md -->

# MainThreadLanguageModels — continued (part 3)

**Rules** (cite as `implement-extension-host-vs-1/code-api-main-thread-language-models--part-3#<slug>`):

- `stream-yields-non-end-parts` MUST
- `text-yields-text-only` MUST
- `end-terminates-both-cursors` MUST
- `end-stop-reason-dropped` MUST
- `source-end-without-end-part` MUST
- `part-after-end-ignored` MUST
- `bridging-failure-fails-cursor` MUST
- `tool-call-json-parse-failure-is-null-not-fatal` MUST
- `json-parse-through-vscodeapi-call` MUST
- `one-outstanding-next-per-cursor` MUST
- `next-settles-synchronously-when-possible` MUST
- `return-marks-only-its-own-cursor` MUST
- `wake-on-stale-context-clears-silently` MUST
- `check-completion-both-cursors` MUST
- `cancellation-token-cancels-source` MUST
- `cancellation-preserves-buffered-parts` MUST
- `cancellation-after-finish-is-a-no-op` MUST
- `on-did-change-chat-models-torn-down-response` MUST
- `available-chat-models-did-change-set-comparison` MUST
- `available-chat-models-did-change-replaces-before-firing` MUST
- `metadata-only-republish-does-not-fire` MUST
- `reorder-does-not-fire` MUST
- `removal-fires` MUST
- `available-chat-models-did-change-guarded-on-disposed` MUST

- **stream-yields-non-end-parts**: The `stream` cursor MUST yield every buffered part except `.end`, bridged into a `LanguageModelTextPart` or `LanguageModelToolCallPart` JS object matching the part's case.
- **text-yields-text-only**: The `text` cursor MUST yield only the string payload of `.text` parts, advancing past `.toolCall` and `.end` parts without yielding them.
- **end-terminates-both-cursors**: A `.end` part MUST terminate both cursors' iteration (`done: true`) without itself being yielded as a value on either cursor.
- **end-stop-reason-dropped**: `.end`'s `stopReason` MUST NOT be surfaced anywhere in the JS-visible response object; `vscode.LanguageModelChatResponse` declares no member to carry it.
- **source-end-without-end-part**: A provider stream that finishes without ever yielding a `.end` part MUST still finish both cursors (`done: true`) once the buffer is exhausted and the source has finished.
- **part-after-end-ignored**: A part the provider stream yields after a `.end` part MUST NOT reach either cursor, since both cursors already finished at the `.end` part.
- **bridging-failure-fails-cursor**: When a buffered part cannot be bridged into a JS value on the `stream` cursor, that cursor MUST fail with `LanguageModelPartBridgingFailure` rather than silently skip the part; a data-loss event MUST NOT masquerade as a successful, shorter response.
- **tool-call-json-parse-failure-is-null-not-fatal**: When a `.toolCall` part's `argumentsJSON` does not parse as JSON, the delivered `LanguageModelToolCallPart`'s `input` MUST be `null` and an error MUST be logged; the part MUST still be delivered and the response MUST NOT fail over one malformed tool call.
- **json-parse-through-vscodeapi-call**: Tool-call argument parsing MUST invoke the context's `JSON.parse` through `VSCodeAPI.call`, not a direct JavaScriptCore call, so the `SyntaxError` a malformed payload throws is caught here and never reaches `ExtensionHost`'s uncaught-exception handler.
- **one-outstanding-next-per-cursor**: Each cursor MUST hold at most one outstanding `next()` waiter at a time; a second `next()` call issued before the first settles MUST log an error and reject the displaced (earlier) waiter's promise before installing the new waiter.
- **next-settles-synchronously-when-possible**: `next(kind:in:)` MUST settle its returned promise synchronously within the promise executor whenever `scan(kind:in:)` can already answer; only when the buffer is exhausted for that cursor and the source has neither failed nor finished MUST the call become a pending waiter, settled later by `wake(_:)`.
- **return-marks-only-its-own-cursor**: A cursor's `return(value)` MUST mark only that cursor finished and resolve that cursor's own outstanding waiter (if any) with `done: true`; it MUST NOT affect the other cursor's completion state.
- **wake-on-stale-context-clears-silently**: When `wake(_:)` finds an outstanding waiter whose promise's `JSContext` has already been released, it MUST clear the waiter without attempting to settle it, and MUST NOT strand it for a later `wake(_:)` call to hit the same condition again.
- **check-completion-both-cursors**: A request MUST be cancelled (`cancelSource()`) and removed from `liveRequests` only once both the `stream` and `text` cursors have finished; a request with one cursor never iterated MUST remain in `liveRequests`, its buffer retained, for the rest of the adaptor's lifetime.
- **cancellation-token-cancels-source**: When the `sendRequest` caller's `CancellationToken` becomes cancelled after streaming has started, `cancelBySourceToken()` MUST stop the pump, set the request's failure to a cancellation error, and mark the source finished, through the same path a thrown provider error takes.
- **cancellation-preserves-buffered-parts**: Parts already buffered before a `CancellationToken` cancellation MUST still be delivered to both cursors before either cursor observes the cancellation failure.
- **cancellation-after-finish-is-a-no-op**: `cancelBySourceToken()` called after the source has already finished MUST NOT overwrite a completed response's outcome with a failure.
- **on-did-change-chat-models-torn-down-response**: `vscode.lm.onDidChangeChatModels`'s implementation MUST raise a JavaScript exception, never reject a promise or answer normally, when invoked after `dispose()` or after this adaptor has deallocated, using the identical message for both causes.
- **available-chat-models-did-change-set-comparison**: `availableChatModelsDidChange()` MUST compare the current `Set` of `provider.availableChatModels` ids against `lastModelIdentifiers` and MUST fire `onDidChangeChatModelsEmitter` only when that set differs.
- **available-chat-models-did-change-replaces-before-firing**: `availableChatModelsDidChange()` MUST replace `lastModelIdentifiers` with the new set before firing the emitter.
- **metadata-only-republish-does-not-fire**: A `provider.availableChatModels` republish that changes some model's `name`, `vendor`, `family`, `version`, or `maxInputTokens` without changing the set of ids MUST NOT fire `onDidChangeChatModels`.
- **reorder-does-not-fire**: A `provider.availableChatModels` republish that reorders the same set of ids MUST NOT fire `onDidChangeChatModels`.
- **removal-fires**: A `provider.availableChatModels` republish that removes an id MUST fire `onDidChangeChatModels`.
- **available-chat-models-did-change-guarded-on-disposed**: `availableChatModelsDidChange()` MUST return immediately, without recomputing the snapshot or firing, when `isDisposed` is `true`.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `provider` | `ExtensionLanguageModelProviding` | none (required) | Sole source of `availableChatModels` and `streamResponse`; not defaulted, per **provider-seam-injected**. |
| `notImplementedLedger` | `NotImplementedLedger` | none (required) | Recorded into for the unimplemented `System` message role and for degraded `sendRequest` options; not defaulted. |
| `extensionIdentifier` | `String` | none (required) | Which extension owns this adaptor; stamped into every ledger record. Not validated for non-emptiness. |
| `selector` (`selectChatModels` argument) | `vscode.LanguageModelChatSelector?` | absent, matches all | `vendor`/`family`/`version`/`id`, each independently optional; a present-but-non-object value is also treated as "match all." |
| `messages` (`sendRequest` argument) | `[ExtensionLanguageModelMessage]` | none (required) | Parsed from `sendRequest`'s first JS argument; a message with an unsupported `role` rejects the whole call. |
| `options.justification` (`sendRequest` argument) | `String?` | `nil` | Forwarded to `provider.streamResponse` unchanged; never interpreted here. |
| `options.modelOptions` / `.tools` / `.toolMode` (`sendRequest` argument) | present or absent | absent | Presence alone is recorded into `notImplementedLedger`; content is never read. |
| `token` (`sendRequest` argument, `CancellationToken`) | duck-typed JS value or absent | uncancelled | Honoured only when it is an object exposing a callable `onCancellationRequested`; otherwise the request is never cancelled. |
| `VSCodeAPI.maximumDecodableArrayLength` | `Int` | `100_000` | Declared in `VSCodeAPI.swift`; the ceiling `arrayElements(of:)` enforces for every array this file walks. Not settable per call. |

