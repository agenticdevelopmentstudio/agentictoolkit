---
id: bda54815-6dd8-4a7c-abfe-8cb0065824b2
title: MainThreadLanguages
domain: agentictoolkit://recipes/extension-host-vs-code-api-main-thread-languages
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The vscode.languages adaptor validating, translating, storing and disposing
  setLanguageConfiguration calls, and answering getLanguages from an injected vocabulary.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- languages
- language-configuration
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadLanguages.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadLanguagesTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadLanguagesVocabularyTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/HostLanguageVocabulary.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/LanguageContributionPoint.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Host/NotImplementedLedger.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

# MainThreadLanguages

## Overview

`MainThreadLanguages.swift` is the `vscode.languages` namespace adaptor's shell (`VSCodeAPI`'s fifth namespace adaptor) and, so far, its only two members: `setLanguageConfiguration` and `getLanguages` (`vscode.d.ts:15301` and `:14733`). `setLanguageConfiguration` validates its arguments, translates the JavaScript configuration object into a Swift `LanguageConfiguration` through a family of value types that mirror `vscode.d.ts:6486-6739`'s `LanguageConfiguration` and its nested shapes (`CommentRule`, `IndentationRule`, `OnEnterRule`, `AutoClosingPair`, and the `SerializedRegExp` every regex-bearing field decodes to), stores the result in an injected `LanguageConfigurationStore` keyed by an opaque handle, and hands back a `Disposable` that removes exactly that registration. `getLanguages` answers a resolved promise built from an injected `ExtensionLanguageVocabulary`'s `languageIdentifiers`, read fresh on every call. Per the file's own doc comment (its "Ruling 8"), this adaptor validates, translates, stores, and hands back — it applies nothing to any editor; nothing among the given sources reads a stored `LanguageConfiguration` back out today, which is why `LanguageConfigurationStore` exists at all — so `dispose()` has something real to undo — rather than because any consumer needs the stored value. `HostLanguageVocabulary` (`HostLanguageVocabulary.swift`, read for context, not part of this file) is the production `ExtensionLanguageVocabulary`: it composes CodeEditLanguages' built-in language catalogue with `LanguageContributionPoint.contributedLanguageIdentifiers`. This file depends only on the `ExtensionLanguageVocabulary` protocol, never on that composition directly, and a test hands it a double instead.

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
- **indent-action-raw-values**: `IndentAction` MUST expose `none == 0`, `indent == 1`, `indentOutdent == 2`, and `outdent == 3`, matching `vscode.d.ts:6539-6558`'s declared numeric values exactly.
- **enter-action-requires-indent-action**: `EnterAction.make(from:)` MUST return `nil` for the entire action when `indentAction` is not a JS number whose exact integer value maps to a defined `IndentAction` case, and MUST independently decode the optional `appendText` (a string) and `removeText` (an integer) fields only when `indentAction` decodes successfully.
- **integer-fields-read-via-exact-conversion**: `EnterAction.make(from:)`'s reads of `indentAction` and `removeText`, and `wordPatternRefusal`'s downstream numeric comparisons, MUST convert a JS number to a Swift integer using `Int32(exactly:)`, never `toInt32()`; a value whose `ToInt32` wraparound happens to land on a valid range (for example `4294967297` wrapping to `1`) MUST be refused rather than silently accepted as that in-range value.
- **on-enter-rule-requires-before-text-and-action**: `OnEnterRule.make(from:)` MUST return `nil` for the entire rule when `beforeText` fails to decode as a `SerializedRegExp` or `action` fails to decode as an `EnterAction`, and MUST independently decode the optional `afterText` and `previousLineText` fields only when both required fields are present.
- **on-enter-rule-array-drops-invalid-entries**: `OnEnterRule.makeArray(from:)` MUST drop any array element that fails `OnEnterRule.make(from:)`'s own decode while keeping every valid sibling element, rather than failing the whole array when one entry is malformed.
- **syntax-token-type-raw-values**: `SyntaxTokenType` MUST expose `other == 0`, `comment == 1`, `string == 2`, and `regEx == 3`, matching `vscode.d.ts:6603-6620`'s declared numeric values exactly.
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
- **get-languages-rejects-when-torn-down**: `getLanguages` MUST be installed via `VSCodeAPI.member` with `whenTornDown: .rejectedPromise`, so a call reaching a `MainThreadLanguages` instance that has already been deallocated MUST resolve to a rejected `Thenable` rather than a raised exception, matching `vscode.d.ts:14733`'s `Thenable<string[]>` return type.
- **get-languages-answers-fresh-from-vocabulary**: `handleGetLanguages()` MUST read `vocabulary.languageIdentifiers` anew on every call and MUST wrap the result in an already-resolved promise via `VSCodeAPI.resolvedPromise(with:in:)`; it MUST NOT cache the vocabulary's answer across calls.
- **get-languages-ignores-extra-arguments**: `handleGetLanguages()` MUST NOT read or validate any call arguments, matching `vscode.d.ts:14733`'s declaration of `getLanguages()` with no parameters.
- **get-languages-answer-is-independent-per-call**: each call to `getLanguages` MUST produce a JS array distinct from any array returned by a prior call, so that an extension mutating one call's resolved array (push, sort, or otherwise) MUST NOT change what a subsequent call resolves with.
- **set-language-configuration-requires-string-id**: `handleSetLanguageConfiguration()` MUST raise a JavaScript error with the exact message `setLanguageConfiguration requires a string language id.` and MUST NOT add a registration to `store` when the first argument is absent or is not a JS string.
- **set-language-configuration-accepts-empty-or-missing-second-argument**: `handleSetLanguageConfiguration()` MUST treat a call with no second argument identically to one whose second argument is `undefined`, `null`, or a non-object primitive — all read via `LanguageConfiguration.make(from:)` as an all-`nil` configuration, with the call MUST NOT raising for that reason alone.
- **set-language-configuration-raises-when-torn-down**: `setLanguageConfiguration` MUST be installed via `VSCodeAPI.member` with `whenTornDown: .raisedException`, so a call reaching an already-deallocated `MainThreadLanguages` instance MUST raise a synchronous exception rather than answering a rejected promise, matching `vscode.d.ts:15301`'s synchronous `Disposable` return type.
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

## Appearance

Not applicable — this is a `JSContext` bridge for the `vscode.languages` namespace and its backing configuration store, not a visual component.

## States

Not applicable — this is a `JSContext` bridge for the `vscode.languages` namespace and its backing configuration store, not a visual component. Its only lifecycle-shaped behavior is registration and disposal of individual configurations, captured under Behavioral Requirements (**set-language-configuration-returns-scoped-disposable**, **dispose-removes-only-owned-handles**) rather than as a visual-state table.

## Accessibility

Not applicable — this is a `JSContext` bridge for the `vscode.languages` namespace and its backing configuration store, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| main-thread-languages-001 | word-pattern-empty-match-refusal | `setLanguageConfiguration('plaintext', { wordPattern: { source: 'a*', flags: '' } })` | Raises with message `Invalid language configuration: wordPattern '/a*/' is not allowed to match the empty string.`; `store.configurations(forLanguage: "plaintext")` stays empty — `MainThreadLanguagesTests.wordPatternMatchingEmptyStringIsRefused` |
| main-thread-languages-002 | word-pattern-compile-failure-is-not-a-refusal, regexp-flag-mapping | `setLanguageConfiguration('rust', { wordPattern: /[a-zA-Z_][a-zA-Z0-9_]*/gi })` (a real `RegExp` literal) | No error raised; the stored configuration's `wordPattern.pattern == "[a-zA-Z_][a-zA-Z0-9_]*"` and `.flags == "gi"` — `MainThreadLanguagesTests.wordPatternNotMatchingEmptyStringIsAcceptedFlagsAndAll` |
| main-thread-languages-003 | word-pattern-absent-is-not-refused | `setLanguageConfiguration('plaintext', { brackets: [['(', ')']] })` (no `wordPattern`) | No error raised; stored configuration's `wordPattern == nil` — `MainThreadLanguagesTests.absentWordPatternIsAcceptedAndStaysNil` |
| main-thread-languages-004 | word-pattern-compile-failure-is-not-a-refusal, word-pattern-compile-failure-is-logged | `setLanguageConfiguration('weird', { wordPattern: { source: '(unclosed', flags: '' } })` | No error raised; stored configuration's `wordPattern.pattern == "(unclosed"`; an error is logged — `MainThreadLanguagesTests.wordPatternFailingToCompileIsStoredUnvalidatedNotRefused` |
| main-thread-languages-005 | line-comment-two-shapes | `setLanguageConfiguration('lang-a', { comments: { lineComment: '//' } })` then `setLanguageConfiguration('lang-b', { comments: { lineComment: { comment: ';', noIndent: true } } })` | `lang-a`'s stored `comments.lineComment` decodes to `.string("//")`; `lang-b`'s decodes to `.rule(comment: ";", noIndent: true)` — `MainThreadLanguagesTests.lineCommentRoundTripsBothStringAndRuleShapes` |
| main-thread-languages-006 | syntax-token-type-array-drops-invalid-elements, auto-closing-pair-shape | `setLanguageConfiguration('lang-c', { autoClosingPairs: [{ open: '"', close: '"', notIn: [1, 3] }, { open: '(', close: ')' }] })` | Stored `autoClosingPairs[0].notIn == [.comment, .regEx]`; `autoClosingPairs[1].notIn == nil` — `MainThreadLanguagesTests.autoClosingPairNotInTranslatesToTheMatchingEnumCases` |
| main-thread-languages-007 | indentation-rule-requires-both-patterns | `setLanguageConfiguration('lang-indent', { indentationRules: { increaseIndentPattern: /increase$/g, decreaseIndentPattern: /^decrease/i, indentNextLinePattern: /nextline/, unIndentedLinePattern: /unindented/m } })` | All four patterns' `pattern`/`flags` survive translation exactly as supplied — `MainThreadLanguagesTests.indentationRulesAllFourPatternsSurviveTranslation` |
| main-thread-languages-008 | on-enter-rule-requires-before-text-and-action, integer-fields-read-via-exact-conversion, indent-action-raw-values | `setLanguageConfiguration('lang-enter', { onEnterRules: [{ beforeText: /before$/, afterText: /^after/, previousLineText: /prev/, action: { indentAction: 2, appendText: '  ', removeText: 1 } }] })` | Stored rule's `action.indentAction == .indentOutdent`, `action.appendText == "  "`, `action.removeText == 1` — `MainThreadLanguagesTests.onEnterRuleWithAllFieldsTranslatesIndentActionToIndentOutdent` |
| main-thread-languages-009 | indentation-rule-requires-both-patterns, on-enter-rule-array-drops-invalid-entries | `setLanguageConfiguration('lang-missing', { indentationRules: { decreaseIndentPattern: /^decrease/ }, onEnterRules: [{ afterText: /no-beforeText/, action: { indentAction: 0 } }, { beforeText: /valid$/, action: { indentAction: 1 } }] })` | Stored `indentationRules == nil` (missing required `increaseIndentPattern`); stored `onEnterRules` has exactly one entry, whose `beforeText.pattern == "valid$"` — `MainThreadLanguagesTests.requiredFieldMissingDropsWholeIndentationRuleButOnlyTheOffendingOnEnterRuleEntry` |
| main-thread-languages-010 | deprecated-members-accepted-and-dropped | `setLanguageConfiguration('lang-d', { brackets: [['{', '}']], __electricCharacterSupport: { docComment: {} }, __characterPairSupport: { autoClosingPairs: [] } })` | No error raised; stored `brackets == [CharacterPair(open: "{", close: "}")]` — `MainThreadLanguagesTests.deprecatedMembersAreAcceptedAndTranslateToNothing` |
| main-thread-languages-011 | set-language-configuration-returns-scoped-disposable | `setLanguageConfiguration('lang-e', { brackets: [['[', ']']] })`, then call the returned `Disposable`'s `dispose()` | Before `dispose()`, `store.configurations(forLanguage: "lang-e").count == 1`; after, it is empty — `MainThreadLanguagesTests.disposeRemovesTheRegistrationFromTheStore` |
| main-thread-languages-012 | remove-handle-is-idempotent | Register `lang-f`, dispose it, register `lang-f` again, then call the first `Disposable`'s `dispose()` a second time | The second `dispose()` call does not raise; the later `lang-f` registration is unaffected (`store.configurations(forLanguage: "lang-f").count == 1`, matching the second registration's brackets) — `MainThreadLanguagesTests.disposingTwiceIsANoOpAndDoesNotTouchALaterRegistration` |
| main-thread-languages-013 | language-configuration-store-keyed-by-handle | Register two configurations for `lang-g`, then dispose only the second | `store.configurations(forLanguage: "lang-g").count == 2` immediately after both registrations; `== 1` after disposing the second, and the surviving entry is the first — `MainThreadLanguagesTests.twoConfigurationsForOneLanguageBothSurviveAndDisposingOneLeavesTheOther` |
| main-thread-languages-014 | dispose-removes-only-owned-handles | Two `MainThreadLanguages` instances share one `store`; each registers one language; a third registration is seeded directly via `store.add(languageId:configuration:)`; then call `dispose()` on only the first instance | The first instance's registration is gone; the second instance's and the seeded registration both remain (`store.contains(handle:)` still `true` for the seeded handle) — `MainThreadLanguagesTests.disposeOnOneAdaptorLeavesASharedStoresOtherRegistrationsAlone` |
| main-thread-languages-015 | set-language-configuration-requires-string-id | `setLanguageConfiguration(42, { brackets: [['(', ')']] })` (a number, not a string) | Raises with message `setLanguageConfiguration requires a string language id.`; `store.count == 0` — `MainThreadLanguagesTests.nonStringLanguageIdRaisesRatherThanRegistering` |
| main-thread-languages-016 | language-configuration-never-fails, set-language-configuration-accepts-empty-or-missing-second-argument | `setLanguageConfiguration('lang-null', null)`, `setLanguageConfiguration('lang-undefined')` (one argument), `setLanguageConfiguration('lang-primitive', 'nope')` | None raise; each call returns a `Disposable` (three total); each stored configuration has every member `nil` — `MainThreadLanguagesTests.anUnusableConfigurationArgumentRegistersEveryMemberNilWithoutRaising` |
| main-thread-languages-017 | get-languages-answers-fresh-from-vocabulary | `vocabulary.languageIdentifiers == ["gamma", "alpha", "beta"]`; call `getLanguages()` and await its resolution | Resolves with exactly `["gamma", "alpha", "beta"]`, in that order — `MainThreadLanguagesGetLanguagesTests.getLanguagesResolvesWithTheVocabularysIdentifiersInOrder` |
| main-thread-languages-018 | get-languages-answer-is-independent-per-call | Call `getLanguages()`, `.push('intruder')` and `.sort()` the resolved array, then call `getLanguages()` again | The second call's resolved array equals the original `vocabulary.languageIdentifiers` (`["zeta", "alpha", "mu"]`), unaffected by the first array's mutation — `MainThreadLanguagesGetLanguagesTests.mutatingOneCallsAnswerDoesNotAffectTheNextCall` |
| main-thread-languages-019 | get-languages-rejects-when-torn-down | Drop the only strong reference to a `MainThreadLanguages` instance, then call `getLanguages()` on the still-installed member | The returned `Thenable` rejects with message `vscode.languages.getLanguages is unavailable: this extension's host has been torn down.` — `MainThreadLanguagesGetLanguagesTests.aTornDownAdaptorRejectsGetLanguagesRatherThanAnsweringOrRaising` |

## Edge Cases

- **Null/empty input**: a `setLanguageConfiguration` call whose second argument is omitted, `null`, `undefined`, or a non-object primitive MUST decode to a `LanguageConfiguration` with every member `nil` and MUST NOT raise, per **language-configuration-never-fails** and **set-language-configuration-accepts-empty-or-missing-second-argument** (MUST).
- **Null/empty input**: a configuration object's `wordPattern` (or any other member) that is present but not shaped as its declared type MUST decode as absent for that member alone, per **language-configuration-members-decode-independently** (MUST); this is the source's documented "permissive on shape" rule applied uniformly.
- **Null/empty input**: the first argument to `setLanguageConfiguration` being the empty string `""` is not distinguished from any other string by this file's own validation — `handleSetLanguageConfiguration()` checks only `isString`, not non-emptiness — so an empty-string language id is accepted and stored under that exact key, per **set-language-configuration-requires-string-id**'s own scope (MUST, by the absence of any further check).
- **Boundary values**: a `wordPattern` whose `pattern` source is exactly `^`, `^$`, `$`, or `^\s*$` MUST NOT be refused even though each matches the empty string, per **word-pattern-exempt-patterns-are-source-exact** (MUST); a pattern that also matches the empty string but is spelled any other way MUST be refused, per **word-pattern-empty-match-refusal** (MUST).
- **Boundary values**: a `brackets`, `onEnterRules`, `autoClosingPairs`, or `notIn` array of exactly `VSCodeAPI.maximumDecodableArrayLength` (100,000) elements is the largest `VSCodeAPI.arrayLength(of:)` accepts; one element longer MUST cause that array's decode — and, for a top-level member, that member alone — to fail, per **character-pair-array-drops-invalid-elements**'s and **auto-closing-pair-array-drops-invalid-elements**'s shared dependency on `VSCodeAPI.arrayLength(of:)` (MUST).
- **Boundary values**: `indentAction`, `notIn` elements, and `removeText` are each read through `Int32(exactly:)`; a JS number whose `ToInt32` wraparound would coincidentally land on a valid case (for example `4294967297` wrapping to `1`) MUST be refused rather than accepted, per **integer-fields-read-via-exact-conversion** (MUST).
- **Concurrent access**: not applicable in the sense of requiring synchronization — every type and function in this file is `@MainActor`-isolated (per **main-actor-confinement**), so there is no path by which two `setLanguageConfiguration` or `getLanguages` calls execute concurrently against the same `store`; the compiler enforces this rather than any lock or queue in the source (MUST, per each type's own `@MainActor` declaration).
- **Concurrent access**: two `MainThreadLanguages` instances MAY share one `LanguageConfigurationStore`; disposing one instance MUST remove only the handles that instance itself added, leaving the other instance's and any directly seeded registrations untouched, per **dispose-removes-only-owned-handles** (MUST).
- **Error states**: a non-string first argument to `setLanguageConfiguration` MUST raise synchronously with a fixed message and MUST NOT add a registration, per **set-language-configuration-requires-string-id** (MUST).
- **Error states**: a `wordPattern` that compiles and matches the empty string MUST raise synchronously with a fixed message naming the pattern, and MUST NOT add a registration for that call, per **word-pattern-empty-match-refusal** and **word-pattern-refusal-order** (MUST).
- **Error states**: a `wordPattern` that fails to compile under `NSRegularExpression` MUST NOT raise and MUST NOT block registration; the malformed pattern is stored unvalidated and an error is logged instead, per **word-pattern-compile-failure-is-not-a-refusal** and **word-pattern-compile-failure-is-logged** (MUST) — this is a deliberate divergence from treating every regex failure as a refusal, since `NSRegularExpression` (ICU) and V8 do not accept identical pattern syntax.
- **Error states**: a call to `setLanguageConfiguration` or `getLanguages` reaching a `MainThreadLanguages` instance that has already been deallocated MUST answer per that member's declared teardown response — a raised exception for `setLanguageConfiguration`, a rejected promise for `getLanguages` — per **set-language-configuration-raises-when-torn-down** and **get-languages-rejects-when-torn-down** (MUST).
- **Offline or disconnected state**: not applicable — this file makes no network call and opens no file; every input it processes arrives already resident in the `JSContext` as a `JSValue`, and `vocabulary.languageIdentifiers` is an in-memory read.
- **Cancellation and timeouts**: not applicable — every function in this file is synchronous (`getLanguages`'s `Thenable` resolves immediately from an already-computed array); there is no long-running operation to cancel or time out.
- **Missing file or unreachable server**: not applicable — this file has no filesystem or network dependency of its own; the injected `store` and `vocabulary` are both in-memory collaborators.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `store` | `LanguageConfigurationStore` | none (required) | Where every registration this adaptor makes lives; not defaulted, so a caller cannot silently receive a private store nothing else can read, per **main-thread-languages-requires-injected-collaborators**. |
| `vocabulary` | `ExtensionLanguageVocabulary` | none (required) | Answers `getLanguages()`; not defaulted, for the same reason as `store`. `HostLanguageVocabulary` is the production conformer; a test hands in a double. |
| `languageId` (1st call argument) | JS string | none (required) | The language identifier `setLanguageConfiguration` registers a configuration under; validated only for `isString`, not non-emptiness or uniqueness. |
| `configurationValue` (2nd call argument) | JS value or absent | treated as "every member absent" | Read via `arguments.count > 1 ? arguments[1] : nil`, then `LanguageConfiguration.make(from:)`, which never fails. |
| `VSCodeAPI.maximumDecodableArrayLength` | `Int` | `100_000` | Declared in `VSCodeAPI.swift`; the ceiling `VSCodeAPI.arrayLength(of:)` enforces for every array this file walks (`brackets`, `onEnterRules`, `autoClosingPairs`, `notIn`). Not settable per call. |
| `MainThreadLanguages.emptyMatchExemptPatterns` | `Set<String>` | `["^", "^$", "$", "^\s*$"]` | The `wordPattern` sources exempt from the empty-match refusal, matched against the pattern's source text verbatim. Not configurable by the caller. |

## Deep Linking

Not applicable: `MainThreadLanguages.swift` defines no URL, route, or navigable destination — it registers and enumerates language configurations, with no navigation surface of its own.

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

## Accessibility Options

Not applicable: `MainThreadLanguages.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; both members are always available once a `MainThreadLanguages` instance is installed on a host.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; its only telemetry-adjacent call is the one `logger.error` line covered under Logging, which is diagnostic logging, not an analytics event.

## Privacy

- **Data collected**: `MainThreadLanguages.swift` collects no data of its own; it stores whatever `languageId` and `LanguageConfiguration` values (comment rules, bracket pairs, word patterns, indentation and on-Enter rules, auto-closing pairs) an extension supplies to `setLanguageConfiguration`, none of which are user personal data or credentials.
- **Storage**: stored configurations live only in the injected `LanguageConfigurationStore`'s in-memory dictionary; nothing here writes to disk, a database, or any persistent store.
- **Transmission**: this file makes no network call; it neither sends nor receives anything over a network.
- **Retention**: a registration persists in `store` until its `Disposable`'s `dispose()` is called or the owning `MainThreadLanguages` instance's own `dispose()` runs; nothing here expires a registration on a timer or on app restart.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `MainThreadLanguages`

| Event | Level | Message |
|-------|-------|---------|
| A `wordPattern`'s `pattern` fails to compile under `NSRegularExpression` | error | `wordPattern '/pattern/flags' does not compile under NSRegularExpression (<error>); stored unvalidated rather than refused, per Ruling 12` |

No other event in this file is logged: a non-string `languageId`, an empty-match `wordPattern` refusal, and a torn-down adaptor's answer are each surfaced to the caller directly (as a thrown JS error or a rejected promise) rather than logged, per **set-language-configuration-requires-string-id**, **word-pattern-empty-match-refusal**, **get-languages-rejects-when-torn-down**, and **set-language-configuration-raises-when-torn-down**.

## Platform Notes

- **SwiftUI**: not applicable to this file — `MainThreadLanguages.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing here renders or observes view state.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadLanguages.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is installed onto an `ExtensionHost`'s `vscode.languages` namespace via `defineVSCodeMember(namespacePath:name:implementation:)`, the same seam every other `VSCodeAPI` adaptor in this directory uses.
- **Compose**: model `LanguageConfiguration` and its nested types as Kotlin `data class`es built by plain factory functions performing the same field-by-field decode this file's `make(from:)` functions perform, rejecting a required field's absence by returning `null` from the whole factory rather than throwing. Model `IndentAction` and `SyntaxTokenType` as Kotlin enum classes with an explicit numeric `value` property, since a Kotlin `enum class` has no automatic reverse numeric lookup; add a small companion-object map from `Int` to the matching case, mirroring **indent-action-raw-values** and **syntax-token-type-raw-values**. Model `LanguageConfigurationStore` as a class holding a `MutableMap<Int, Registration>` plus a monotonic counter, matching **language-configuration-store-keyed-by-handle** and **handle-assignment-is-monotonic** exactly.
- **React/Web**: this is closest to the actual runtime shape — extension code in the real VS Code product already calls `vscode.languages.setLanguageConfiguration`/`getLanguages` against the genuine `vscode.d.ts` declarations these types mirror. A React/Web extension host implementing the same bridge would decode the same configuration shape across whatever serialization boundary (for example `postMessage` to a worker) replaces this file's `JSContext` boundary, and would need the same per-member "refuse the whole member on a malformed required field, drop only the malformed element of an array" discipline this file's `make(from:)`/`makeArray(from:)` pairs apply throughout.
- **WinUI 3**: model `LanguageConfigurationStore` as a plain C# class over a `Dictionary<int, Registration>` with an `int` counter field, exposing `Add(string languageId, LanguageConfiguration configuration)`, `Remove(int handle)`, `Contains(int handle)`, and `Configurations(string languageId)` returning an `IReadOnlyList<LanguageConfiguration>` ordered by ascending key — the direct analogue of **language-configuration-store-keyed-by-handle** and **configurations-for-language-ordering**. Model `IndentAction` and `SyntaxTokenType` as `public enum IndentAction { None = 0, Indent = 1, IndentOutdent = 2, Outdent = 3 }`-shaped C# enums, where `Enum.IsDefined` replaces this file's `Int32(exactly:)`-then-`IndentAction(rawValue:)` pattern for refusing an out-of-range or non-integral value, matching **integer-fields-read-via-exact-conversion**. Model the `SerializedRegExp` pair (`pattern`, `flags`) as a small `record SerializedRegExp(string Pattern, string Flags)`, translating `flags` to `System.Text.RegularExpressions.RegexOptions` the same restricted way **regexp-flag-mapping** does (`i` to `IgnoreCase`, `m` to `Multiline`, `s` to `Singleline`, with `g`/`y`/`u`/`d`/`v` having no `RegexOptions` equivalent), and catching `RegexParseException` from `new Regex(pattern, options)` to reproduce **word-pattern-compile-failure-is-not-a-refusal**'s "store unvalidated, log instead" branch rather than treating a .NET-vs-V8 regex dialect mismatch as a hard refusal. `Task.FromResult`/`async Task<IReadOnlyList<string>>` is the WinUI analogue of `getLanguages`'s already-resolved promise, since this host has no process boundary to amortize either.

## Design Decisions

**Decision**: `LanguageConfigurationStore` keys registrations by an opaque incrementing handle rather than by `languageId`.
**Rationale**: upstream VS Code allows more than one configuration per language, each with its own `Disposable` (`extHostLanguageFeatures.ts`'s own handle-minting pair). An id-keyed store could not express two extensions configuring the same language without one silently overwriting the other, and could not implement `dispose()` correctly when they do; keying by handle, as this file does, lets both survive and lets each be disposed independently.
**Approved**: pending

**Decision**: `wordPatternRefusal(for:)` treats "fails to compile under `NSRegularExpression`" and "compiles and matches the empty string" as two different outcomes — only the second is a refusal — rather than collapsing both into a single "invalid pattern" refusal.
**Rationale**: `NSRegularExpression` (ICU) and V8 (upstream's own regex engine) do not accept identical pattern syntax; a pattern real VS Code accepts can fail to compile under ICU for reasons that have nothing to do with the actual refusal upstream implements (`extHostLanguageFeatures.ts:3009-3012`'s empty-match check). Inventing a second refusal for an engine mismatch would reject configurations upstream itself allows, so a non-compiling pattern is stored unvalidated and logged instead.
**Approved**: pending

**Decision**: numeric fields this file reads from JavaScript (`indentAction`, `notIn` elements, `removeText`) are converted with `Int32(exactly:)`, never `toInt32()`.
**Rationale**: `toInt32()` implements ECMAScript's `ToInt32`, which wraps modulo 2³² and truncates fractions, so a value like `4294967297` would read as the in-range integer `1` and be silently accepted as a valid `IndentAction`/`SyntaxTokenType`/`removeText` when it is none of those things. `Int32(exactly:)` answers `nil` for any value that is not exactly representable, so this file refuses the whole field (or the whole rule, when the field is required) instead of accepting a value JavaScript never actually meant.
**Approved**: pending

**Decision**: `__electricCharacterSupport` and `__characterPairSupport` are accepted without raising and their values are discarded with no deprecation report.
**Rationale**: upstream reports both through its own deprecation-reporting mechanism and then forwards them to its wire unchanged; this bridge has neither that reporter nor a wire for either member to reach, so storing a value nothing here ever reads would be worse than an honest absence. An extension that still sets either member gets silence rather than the warning real VS Code gives it, because there is nowhere in this bridge to send that warning — a deliberate, documented divergence from upstream rather than a description of it.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because this file's responsibilities stay cleanly divided across three layers: the value-type decoders (`SerializedRegExp` through `AutoClosingPair`) that only translate JS shapes to Swift, `LanguageConfigurationStore` that only holds registrations, and `MainThreadLanguages` that only wires the two `vscode.languages` members to them — none of the three reaches into the vocabulary composition (`HostLanguageVocabulary`) that a real `ExtensionLanguageVocabulary` conformer performs elsewhere. `unit-test-coverage` passes: `MainThreadLanguagesTests.swift`'s twelve test methods and `MainThreadLanguagesVocabularyTests.swift`'s further suites exercise every documented mutation point in this file — both `wordPattern` refusal branches, both required-vs-optional decode granularities for `IndentationRule` and `OnEnterRule`, the `LineComment` union, the `notIn` enum mapping, the deprecated-member no-op, both `Disposable` idempotence cases, the shared-store ownership boundary, the non-string-id refusal, the unusable-configuration-argument path, and `getLanguages`'s resolution, per-call freshness, and teardown rejection. `explicit-error-handling` is partial: the non-string-id and empty-match-`wordPattern` failures are real, typed JS errors with specific messages, and `getLanguages`'s teardown answer is an explicit rejection — but a `wordPattern` that fails to compile is only logged, never surfaced to the calling extension in any form, so that specific failure is observable only in the host's own log, not to the code that triggered it. `input-sanitization` passes because every decoder in this file checks a value's JS type (`isString`, `isNumber`, `isArray`, exact-integer conversion) before trusting it, rather than assuming a duck-typed shape from untrusted extension-authored JavaScript is well-formed; malformed input is dropped at the smallest scope its own decoder governs (see **language-configuration-members-decode-independently**, **on-enter-rule-array-drops-invalid-entries**). `no-hardcoded-strings` fails because the two thrown-error messages, the one log message, and the two shared teardown messages this file surfaces are all English literals with no localization mechanism (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
