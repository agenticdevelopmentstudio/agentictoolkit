<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-languages--part-2 · source: extension-host-vs-code-api-main-thread-languages.md -->

# MainThreadLanguages — continued (part 2)

**Rules** (cite as `implement-extension-host-vs-1/code-api-main-thread-languages--part-2#<slug>`):

- `main-actor-confinement` MUST
- `array-decoders-are-main-actor` MUST
- `decoded-value-types-are-sendable` MUST
- `serialized-regexp-decode` MUST
- `serialized-regexp-verbatim-storage` MUST
- `regexp-flag-mapping` MUST
- `line-comment-two-shapes` MUST
- `comment-rule-requires-one-member` MUST
- `character-pair-shape` MUST
- `character-pair-array-drops-invalid-elements` MUST
- `indentation-rule-requires-both-patterns` MUST
- `indent-action-raw-values` MUST
- `enter-action-requires-indent-action` MUST
- `integer-fields-read-via-exact-conversion` MUST
- `on-enter-rule-requires-before-text-and-action` MUST
- `on-enter-rule-array-drops-invalid-entries` MUST
- `syntax-token-type-raw-values` MUST
- `syntax-token-type-array-drops-invalid-elements` MUST
- `auto-closing-pair-shape` MUST
- `auto-closing-pair-array-drops-invalid-elements` MUST
- `language-configuration-never-fails` MUST
- `language-configuration-members-decode-independently` MUST
- `deprecated-members-accepted-and-dropped` MUST
- `language-configuration-store-keyed-by-handle` MUST
- `handle-assignment-is-monotonic` MUST
- `remove-handle-is-idempotent` MUST
- `configurations-for-language-ordering` MUST
- `main-thread-languages-requires-injected-collaborators` MUST
- `get-languages-rejects-when-torn-down` MUST
- `get-languages-answers-fresh-from-vocabulary` MUST
- `get-languages-ignores-extra-arguments` MUST
- `get-languages-answer-is-independent-per-call` MUST

## Behavioral Requirements

- **main-actor-confinement**: `LanguageConfigurationStore`, `MainThreadLanguages`, and `ExtensionLanguageVocabulary` MUST be `@MainActor`-isolated, with every stored property read, mutation, and method body confined to the main actor.
- **array-decoders-are-main-actor**: `CharacterPair.makeArray(from:)`, `OnEnterRule.makeArray(from:)`, `SyntaxTokenType.makeArray(from:)`, `AutoClosingPair.make(from:)`, and `AutoClosingPair.makeArray(from:)` MUST be `@MainActor`-isolated, because each calls `VSCodeAPI.arrayLength(of:)`, which is itself confined to that actor.
- **decoded-value-types-are-sendable**: `SerializedRegExp`, `LineCommentRule`, `LineComment`, `CommentRule`, `CharacterPair`, `IndentationRule`, `IndentAction`, `EnterAction`, `OnEnterRule`, `SyntaxTokenType`, `AutoClosingPair`, `LanguageConfiguration`, and `LanguageConfigurationStore.Registration` MUST each be declared `Sendable` and `Equatable`, so a decoded configuration MAY cross an actor boundary once it has left the `JSContext` and its owning `JSValue`.
- **serialized-regexp-decode**: `SerializedRegExp.make(from:)` MUST return a value carrying `pattern` set to the source value's string-valued `source` property and `flags` set to its string-valued `flags` property, and MUST return `nil` for `undefined`, `null`, or any value missing either property as a string.
- **serialized-regexp-verbatim-storage**: `SerializedRegExp` MUST store `pattern` and `flags` as the two plain strings read from the JavaScript `RegExp`, never as a compiled `NSRegularExpression`, so the exact `flags` string JavaScript supplied is preserved and can still be inspected later.
- **regexp-flag-mapping**: `SerializedRegExp.nsRegularExpressionOptions` MUST map an `i` flag to `.caseInsensitive`, an `m` flag to `.anchorsMatchLines`, and an `s` flag to `.dotMatchesLineSeparators`, and MUST NOT set any `NSRegularExpression.Options` member for a `g`, `y`, `u`, `d`, or `v` flag, none of which has an equivalent option.
- **line-comment-two-shapes**: `LineComment.make(from:)` MUST decode a JS string value to `.string(...)`, MUST decode an object carrying a string-valued `comment` property to `.rule(...)` with `noIndent` read from the object's `noIndent` property and defaulted to `false` when absent or not a boolean, and MUST return `nil` for `undefined`, `null`, or any other shape.
- **comment-rule-requires-one-member**: `CommentRule.make(from:)` MUST return `nil` when the source value is not an object, and MUST also return `nil` when both `lineComment` and `blockComment` fail to decode, even though each is independently optional in `vscode.d.ts`.
- **character-pair-shape**: `CharacterPair.make(from:)` MUST return `nil` unless the source value is a JS array whose index `0` and index `1` are both strings, read into `open` and `close` respectively.
- **character-pair-array-drops-invalid-elements**: `CharacterPair.makeArray(from:)` MUST use `VSCodeAPI.arrayLength(of:)` to bound the walk and MUST drop any element that fails `CharacterPair.make(from:)`'s own decode rather than failing the whole array.
- **indentation-rule-requires-both-patterns**: `IndentationRule.make(from:)` MUST return `nil` for the entire rule when either `decreaseIndentPattern` or `increaseIndentPattern` fails to decode as a `SerializedRegExp`, and MUST independently decode `indentNextLinePattern` and `unIndentedLinePattern` as optional fields when the two required patterns are present.
- **indent-action-raw-values**: `IndentAction` MUST expose `none == 0`, `indent == 1`, `indentOutdent == 2`, and `outdent == 3`, matching `vscode.d.ts`'s declared numeric values exactly.
- **enter-action-requires-indent-action**: `EnterAction.make(from:)` MUST return `nil` for the entire action when `indentAction` is not a JS number whose exact integer value maps to a defined `IndentAction` case, and MUST independently decode the optional `appendText` (a string) and `removeText` (an integer) fields only when `indentAction` decodes successfully.
- **integer-fields-read-via-exact-conversion**: `EnterAction.make(from:)`'s reads of `indentAction` and `removeText`, and `wordPatternRefusal`'s downstream numeric comparisons, MUST convert a JS number to a Swift integer using `Int32(exactly:)`, never `toInt32()`; a value whose `ToInt32` wraparound happens to land on a valid range (for example `4294967297` wrapping to `1`) MUST be refused rather than silently accepted as that in-range value.
- **on-enter-rule-requires-before-text-and-action**: `OnEnterRule.make(from:)` MUST return `nil` for the entire rule when `beforeText` fails to decode as a `SerializedRegExp` or `action` fails to decode as an `EnterAction`, and MUST independently decode the optional `afterText` and `previousLineText` fields only when both required fields are present.
- **on-enter-rule-array-drops-invalid-entries**: `OnEnterRule.makeArray(from:)` MUST drop any array element that fails `OnEnterRule.make(from:)`'s own decode while keeping every valid sibling element, rather than failing the whole array when one entry is malformed.
- **syntax-token-type-raw-values**: `SyntaxTokenType` MUST expose `other == 0`, `comment == 1`, `string == 2`, and `regEx == 3`, matching `vscode.d.ts`'s declared numeric values exactly.
- **syntax-token-type-array-drops-invalid-elements**: `SyntaxTokenType.makeArray(from:)` MUST read each element through `Int32(exactly:)` and drop any element that is not a JS number mapping to a defined `SyntaxTokenType` case, rather than failing the whole array.
- **auto-closing-pair-shape**: `AutoClosingPair.make(from:)` MUST return `nil` unless the source value is an object with string-valued `open` and `close` properties, and MUST decode an optional `notIn` array via `SyntaxTokenType.makeArray(from:)`, leaving `notIn` `nil` when that array is absent or entirely invalid.
- **auto-closing-pair-array-drops-invalid-elements**: `AutoClosingPair.makeArray(from:)` MUST drop any array element that fails `AutoClosingPair.make(from:)`'s own decode while keeping every valid sibling element.
- **language-configuration-never-fails**: `LanguageConfiguration.make(from:)` MUST return a `LanguageConfiguration` with every member `nil` — never raise, never return an optional — when the source value is `undefined`, `null`, or not an object, so that an unusable second argument to `setLanguageConfiguration` reads as "nothing configured" rather than propagating a JavaScriptCore exception.
- **language-configuration-members-decode-independently**: `LanguageConfiguration.make(from:)` MUST decode each of `comments`, `brackets`, `wordPattern`, `indentationRules`, `onEnterRules`, and `autoClosingPairs` independently from the source object's own like-named property, so a failure decoding one member MUST NOT prevent any other member from decoding successfully.
- **deprecated-members-accepted-and-dropped**: `LanguageConfiguration.make(from:)` MUST accept a configuration object carrying `__electricCharacterSupport` or `__characterPairSupport` without raising, and MUST NOT store either member's value anywhere or report it through any deprecation channel.
- **language-configuration-store-keyed-by-handle**: `LanguageConfigurationStore` MUST key its registrations by an opaque, monotonically increasing integer handle assigned by `add(languageId:configuration:)`, never by `languageId`, so two registrations for the same `languageId` MUST both persist as independent entries.
- **handle-assignment-is-monotonic**: `LanguageConfigurationStore`'s internal `nextHandle` MUST start at `0` and increment by exactly `1` on every `add(languageId:configuration:)` call, and a handle removed via `remove(handle:)` MUST NOT be reassigned to a later registration.
- **remove-handle-is-idempotent**: `LanguageConfigurationStore.remove(handle:)` MUST be a no-op — MUST NOT raise or otherwise fail — when `handle` does not currently name a live registration, including when it names one already removed.
- **configurations-for-language-ordering**: `LanguageConfigurationStore.configurations(forLanguage:)` MUST return every registration currently stored for the given `languageId`, ordered by ascending handle (oldest registration first), and MUST return an empty array when none are registered.
- **main-thread-languages-requires-injected-collaborators**: `MainThreadLanguages.init(store:vocabulary:)` MUST take both `store` and `vocabulary` as required parameters with no default value, so a caller cannot silently receive a private store or an empty vocabulary in place of the host's real ones.
- **get-languages-rejects-when-torn-down**: `getLanguages` MUST be installed via `VSCodeAPI.member` with `whenTornDown: .rejectedPromise`, so a call reaching a `MainThreadLanguages` instance that has already been deallocated MUST resolve to a rejected `Thenable` rather than a raised exception, matching `vscode.d.ts`'s `Thenable<string[]>` return type.
- **get-languages-answers-fresh-from-vocabulary**: `handleGetLanguages()` MUST read `vocabulary.languageIdentifiers` anew on every call and MUST wrap the result in an already-resolved promise via `VSCodeAPI.resolvedPromise(with:in:)`; it MUST NOT cache the vocabulary's answer across calls.
- **get-languages-ignores-extra-arguments**: `handleGetLanguages()` MUST NOT read or validate any call arguments, matching `vscode.d.ts`'s declaration of `getLanguages()` with no parameters.
- **get-languages-answer-is-independent-per-call**: each call to `getLanguages` MUST produce a JS array distinct from any array returned by a prior call, so that an extension mutating one call's resolved array (push, sort, or otherwise) MUST NOT change what a subsequent call resolves with.
