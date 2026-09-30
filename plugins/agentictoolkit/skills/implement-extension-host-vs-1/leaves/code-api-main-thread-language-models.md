<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-language-models · source: extension-host-vs-code-api-main-thread-language-models.md -->

# MainThreadLanguageModels

## Overview

`MainThreadLanguageModels.swift` is the `vscode.lm` namespace adaptor's shell: it installs `vscode.lm.selectChatModels`, the readonly `LanguageModelChat` object that call hands back (itself carrying `sendRequest` and `countTokens`), `vscode.lm.onDidChangeChatModels`, and the per-request response object `sendRequest`'s promise resolves with. It owns no chat model or provider of its own — every `LanguageModelChatDescriptor` and every streamed `ExtensionLanguageModelResponsePart` comes from an injected `ExtensionLanguageModelProviding` seam (the production conformer, `AIPluginLanguageModelProvider`, is a sibling recipe) — but it owns everything the seam does not: `vscode.LanguageModelChatSelector` matching, the readonly JS object-handback shape, `sendRequest` argument parsing and role/option validation, teeing one single-consumption provider stream into the two independent async iterables (`stream` and `text`) `vscode.LanguageModelChatResponse` declares, `CancellationToken` handling, the id-set comparison `onDidChangeChatModels` fires on, and recording unimplemented request options and the unimplemented `System` message role into a shared `NotImplementedLedger`.

