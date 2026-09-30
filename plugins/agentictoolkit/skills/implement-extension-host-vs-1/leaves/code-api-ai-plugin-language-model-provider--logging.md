<!-- leaf: implement-extension-host-vs-1/code-api-ai-plugin-language-model-provider--logging · source: extension-host-vs-code-api-ai-plugin-language-model-provider.md -->

# AIPluginLanguageModelProvider

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `AIPluginLanguageModelProvider`

| Event | Level | Message |
|-------|-------|---------|
| An extension calls `streamResponse` with a non-nil `justification` | info | `extension <extensionIdentifier, privacy: .public> requested a language model, justification: <justification, privacy: .private>` |

No other event in this file is logged: neither `ProviderError.unknownModel` nor `ProviderError.pluginUnavailable` is logged at the point it is thrown — both are facts the code surfaces to the caller as thrown errors instead, per **plugin-resolution-failure** and **model-id-parse-failure**/**model-id-unknown-configuration**.
