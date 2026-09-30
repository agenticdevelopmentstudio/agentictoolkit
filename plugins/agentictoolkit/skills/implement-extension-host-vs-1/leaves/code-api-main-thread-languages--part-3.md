<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-languages--part-3 · source: extension-host-vs-code-api-main-thread-languages.md -->

# MainThreadLanguages — continued (part 3)

**Rules** (cite as `implement-extension-host-vs-1/code-api-main-thread-languages--part-3#<slug>`):

- `set-language-configuration-requires-string-id` MUST
- `set-language-configuration-accepts-empty-or-missing-second-argument` MUST
- `set-language-configuration-raises-when-torn-down` MUST
- `word-pattern-refusal-order` MUST
- `word-pattern-empty-match-refusal` MUST
- `word-pattern-exempt-patterns-are-source-exact` MUST
- `word-pattern-compile-failure-is-not-a-refusal` MUST
- `word-pattern-compile-failure-is-logged` MUST
- `word-pattern-absent-is-not-refused` MUST
- `set-language-configuration-returns-scoped-disposable` MUST
- `dispose-removes-only-owned-handles` MUST
- `extension-language-vocabulary-contract` MUST
- `languages-member-not-tracked-as-unimplemented` MUST

- **set-language-configuration-requires-string-id**: `handleSetLanguageConfiguration()` MUST raise a JavaScript error with the exact message `setLanguageConfiguration requires a string language id.` and MUST NOT add a registration to `store` when the first argument is absent or is not a JS string.
- **set-language-configuration-accepts-empty-or-missing-second-argument**: `handleSetLanguageConfiguration()` MUST treat a call with no second argument identically to one whose second argument is `undefined`, `null`, or a non-object primitive — all read via `LanguageConfiguration.make(from:)` as an all-`nil` configuration, with the call MUST NOT raising for that reason alone.
- **set-language-configuration-raises-when-torn-down**: `setLanguageConfiguration` MUST be installed via `VSCodeAPI.member` with `whenTornDown: .raisedException`, so a call reaching an already-deallocated `MainThreadLanguages` instance MUST raise a synchronous exception rather than answering a rejected promise, matching `vscode.d.ts`'s synchronous `Disposable` return type.
- **word-pattern-refusal-order**: `handleSetLanguageConfiguration()` MUST evaluate `MainThreadLanguages.wordPatternRefusal(for:)` against the translated `wordPattern` before calling `store.add(languageId:configuration:)`, so a refused `wordPattern` MUST result in no registration being added to `store`.
- **word-pattern-empty-match-refusal**: `wordPatternRefusal(for:)` MUST return the message `Invalid language configuration: wordPattern '<pattern>/<flags>' is not allowed to match the empty string.` (with `<pattern>/<flags>` rendered as `/pattern/flags`) when the `wordPattern` compiles successfully under `NSRegularExpression` and matches the empty string at a zero-length range, unless its `pattern` source is exactly one of `^`, `^$`, `$`, or `^\s*$`.
- **word-pattern-exempt-patterns-are-source-exact**: `wordPatternRefusal(for:)` MUST compare a `wordPattern`'s exempt status against its `pattern` source text verbatim, independent of its `flags`, so a pattern spelled differently but functionally equivalent to one of the four exempt sources MUST NOT be treated as exempt.
- **word-pattern-compile-failure-is-not-a-refusal**: `wordPatternRefusal(for:)` MUST return `nil` (no refusal) when `wordPattern`'s `pattern` fails to compile under `NSRegularExpression`, and the configuration's `wordPattern` MUST still be stored unvalidated in that case rather than the whole `setLanguageConfiguration` call being refused.
- **word-pattern-compile-failure-is-logged**: when a `wordPattern` fails to compile under `NSRegularExpression`, `MainThreadLanguages.logger` MUST log an error including the pattern's `/pattern/flags` rendering and the caught error's localized description.
- **word-pattern-absent-is-not-refused**: `wordPatternRefusal(for:)` MUST return `nil` when the translated configuration's `wordPattern` is `nil`, whether because no `wordPattern` property was supplied or because the supplied value failed to decode as a `SerializedRegExp`.
- **set-language-configuration-returns-scoped-disposable**: on success, `handleSetLanguageConfiguration()` MUST return a `Disposable` whose `dispose()` removes exactly the one handle just added from `store` and from this adaptor's own `ownedHandles`, and MUST insert that handle into `ownedHandles` before returning.
- **dispose-removes-only-owned-handles**: `MainThreadLanguages.dispose()` MUST remove from `store` every handle in this instance's own `ownedHandles` and MUST clear `ownedHandles`, and MUST NOT remove any registration added by a different `MainThreadLanguages` instance sharing the same `store`.
- **extension-language-vocabulary-contract**: `ExtensionLanguageVocabulary` MUST be a `@MainActor`, class-constrained protocol exposing a `languageIdentifiers: [String]` property, deduplicated and in a deterministic order, per the protocol's own documented contract.
- **languages-member-not-tracked-as-unimplemented**: `setLanguageConfiguration` and `getLanguages` MUST NOT be routed through `NotImplementedLedger.record(memberPath:extensionIdentifier:)`, because both members answer every call rather than being absent.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `store` | `LanguageConfigurationStore` | none (required) | Where every registration this adaptor makes lives; not defaulted, so a caller cannot silently receive a private store nothing else can read, per **main-thread-languages-requires-injected-collaborators**. |
| `vocabulary` | `ExtensionLanguageVocabulary` | none (required) | Answers `getLanguages()`; not defaulted, for the same reason as `store`. `HostLanguageVocabulary` is the production conformer; a test hands in a double. |
| `languageId` (1st call argument) | JS string | none (required) | The language identifier `setLanguageConfiguration` registers a configuration under; validated only for `isString`, not non-emptiness or uniqueness. |
| `configurationValue` (2nd call argument) | JS value or absent | treated as "every member absent" | Read via `arguments.count > 1 ? arguments[1] : nil`, then `LanguageConfiguration.make(from:)`, which never fails. |
| `VSCodeAPI.maximumDecodableArrayLength` | `Int` | `100_000` | Declared in `VSCodeAPI.swift`; the ceiling `VSCodeAPI.arrayLength(of:)` enforces for every array this file walks (`brackets`, `onEnterRules`, `autoClosingPairs`, `notIn`). Not settable per call. |
| `MainThreadLanguages.emptyMatchExemptPatterns` | `Set<String>` | `["^", "^$", "$", "^\s*$"]` | The `wordPattern` sources exempt from the empty-match refusal, matched against the pattern's source text verbatim. Not configurable by the caller. |

## Localization

- **hardcoded-error-messages**: the two JavaScript error messages this file raises — `setLanguageConfiguration requires a string language id.` and the `wordPattern` empty-match refusal (`Invalid language configuration: wordPattern '<pattern>' is not allowed to match the empty string.`) — are hardcoded English string literals with no localization key or `String(localized:)` call. Both are visible to the extension author whose call triggered them, not to the app's own end-user UI.
- **hardcoded-teardown-message**: the torn-down message both members can produce (`"<path> is unavailable: this extension's host has been torn down."`, built by the shared `VSCodeAPI.member`/`tornDown(path:response:)` helper, not by this file directly) is likewise hardcoded English, surfaced through this file's `getLanguages` rejection and `setLanguageConfiguration` exception.
- **hardcoded-log-string**: the one `logger.error` message in `wordPatternRefusal(for:)` (a `wordPattern` that fails to compile) is a hardcoded English `Logger` interpolated string, also unlocalized.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `setLanguageConfiguration requires a string language id.` | `handleSetLanguageConfiguration()`, raised when the first argument is missing or not a string. |
| (none — literal only) | `Invalid language configuration: wordPattern '/pattern/flags' is not allowed to match the empty string.` | `wordPatternRefusal(for:)`, raised when a non-exempt `wordPattern` compiles and matches the empty string. |
| (none — literal only) | `vscode.languages.getLanguages is unavailable: this extension's host has been torn down.` | Shared `VSCodeAPI` teardown helper, produced when `getLanguages` reaches a deallocated adaptor. |
| (none — literal only) | `vscode.languages.setLanguageConfiguration is unavailable: this extension's host has been torn down.` | Shared `VSCodeAPI` teardown helper, produced when `setLanguageConfiguration` reaches a deallocated adaptor. |
| (none — literal only) | `wordPattern '/pattern/flags' does not compile under NSRegularExpression (<error>); stored unvalidated rather than refused, per Ruling 12` | `wordPatternRefusal(for:)`, logged when the pattern fails to compile. |

## Privacy

- **Data collected**: `MainThreadLanguages.swift` collects no data of its own; it stores whatever `languageId` and `LanguageConfiguration` values (comment rules, bracket pairs, word patterns, indentation and on-Enter rules, auto-closing pairs) an extension supplies to `setLanguageConfiguration`, none of which are user personal data or credentials.
- **Storage**: stored configurations live only in the injected `LanguageConfigurationStore`'s in-memory dictionary; nothing here writes to disk, a database, or any persistent store.
- **Transmission**: this file makes no network call; it neither sends nor receives anything over a network.
- **Retention**: a registration persists in `store` until its `Disposable`'s `dispose()` is called or the owning `MainThreadLanguages` instance's own `dispose()` runs; nothing here expires a registration on a timer or on app restart.

