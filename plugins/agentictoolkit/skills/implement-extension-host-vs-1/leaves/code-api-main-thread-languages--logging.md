<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-languages--logging · source: extension-host-vs-code-api-main-thread-languages.md -->

# MainThreadLanguages

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `MainThreadLanguages`

| Event | Level | Message |
|-------|-------|---------|
| A `wordPattern`'s `pattern` fails to compile under `NSRegularExpression` | error | `wordPattern '/pattern/flags' does not compile under NSRegularExpression (<error>); stored unvalidated rather than refused, per Ruling 12` |

No other event in this file is logged: a non-string `languageId`, an empty-match `wordPattern` refusal, and a torn-down adaptor's answer are each surfaced to the caller directly (as a thrown JS error or a rejected promise) rather than logged, per **set-language-configuration-requires-string-id**, **word-pattern-empty-match-refusal**, **get-languages-rejects-when-torn-down**, and **set-language-configuration-raises-when-torn-down**.
