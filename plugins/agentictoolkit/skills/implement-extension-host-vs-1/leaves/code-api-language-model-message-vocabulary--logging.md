<!-- leaf: implement-extension-host-vs-1/code-api-language-model-message-vocabulary--logging · source: extension-host-vs-code-api-language-model-message-vocabulary.md -->

# LanguageModelMessageVocabulary

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `VSCodeAPI` (the shared logger declared once in `VSCodeAPI.swift` and reused by every `VSCodeAPI` extension file, including this one)

| Event | Level | Message |
|-------|-------|---------|
| `context.evaluateScript(languageModelVocabularySource)` returns `nil` or a non-object | error | `Could not install the 'vscode' language-model message vocabulary in context '<name>'; every member stays the shim's not-implemented stub` |
| The resolved container is missing one of the eight expected members | error | `The 'vscode' language-model message vocabulary in context '<name>' is missing '<memberName>'; every member stays the shim's not-implemented stub` |

No other event in this file is logged: the failed cache-write `Object.defineProperty` inside `languageModelVocabularySource` is caught and silently ignored (per **cache-write-optional**), and no constructor in this file throws or logs on any input, since none of the eight members validates its arguments.
