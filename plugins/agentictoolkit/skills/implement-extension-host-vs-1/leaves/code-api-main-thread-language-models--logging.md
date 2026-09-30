<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-language-models--logging · source: extension-host-vs-code-api-main-thread-language-models.md -->

# MainThreadLanguageModels

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `MainThreadLanguageModels`

| Event | Level | Message |
|-------|-------|---------|
| `JSValue(newObjectIn:)` fails to build a matched model's JS object in `handleSelectChatModels` | error | Names the dropped model; the model is excluded from the resolved array rather than failing the call. |
| A second `next()` call displaces an outstanding waiter on the same cursor | error | Names the one-outstanding-`next()` constraint being violated. |
| A buffered part fails to bridge into a JS value on the `stream` cursor | error | Names the bridging failure that becomes `LanguageModelPartBridgingFailure`. |
| A `.toolCall` part's `argumentsJSON` fails to parse as JSON | error | Names the malformed payload; the part is still delivered with `input: null`. |

No other event in this file is logged: a rejected `selectChatModels`/`sendRequest` call and a raised `onDidChangeChatModels` exception are each surfaced to the caller directly, per **select-chat-models-torn-down-response**, **send-request-torn-down-response**, and **on-did-change-chat-models-torn-down-response**, rather than logged.
