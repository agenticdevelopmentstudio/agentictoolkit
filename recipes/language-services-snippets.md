---
id: 06a425eb-e854-440b-97bc-0df5070ed72f
title: Language Services Snippets
domain: agentictoolkit://recipes/language-services-snippets
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Types that read, model, and serve VS Code-style extension snippet files as
  LSP completion items, keyed by language.
platforms:
- swift
- macos
tags:
- extensions
- contribution-point
- snippets
- completion
- mainactor
depends-on: []
related:
- agentictoolkit://recipes/extension-host-core-extensions-contribution-point
- agentictoolkit://recipes/extension-host-core-extensions-extension-resource-path
- agentictoolkit://recipes/extension-host-core-extensions-extension-manifest
references: []
approved-by: ''
approved-date: ''
---

# Language Services Snippets

## Overview

Three files under `packages/apple/AgenticToolkit/Language/Snippets/` implement the `contributes.snippets` contribution point: `ExtensionSnippet.swift` models one snippet an extension contributes and converts it to an LSP `CompletionItem`; `SnippetFile.swift` reads one VS Code `.json`/`.code-snippets` file's bytes into `[ExtensionSnippet]`; `SnippetStore.swift` is the `@MainActor` `ContributionPoint` (agentictoolkit://recipes/extension-host-core-extensions-contribution-point) that reads every snippet file a loaded extension declares, buckets the results by language, and answers `snippets(forLanguage:)` for the editor's completion path. `ExtensionSnippet.body` is deliberately left as raw LSP snippet syntax, per `ExtensionSnippet.swift`'s own doc comment, because a snippet contributed by an extension *is* already an LSP concept — `LanguageServerProtocol`'s `Snippet` parser and `LSPCompletionDelegate` already know how to insert one, so no separate insertion code is written for extension snippets. `SnippetStore` is consumed by `ExtensionsCoordinator` (which constructs it) and by `LSPCompletionDelegate.completionSuggestionsRequested`, which calls `snippets?.snippets(forLanguage: languageId).map { $0.completionItem() }` to fold extension snippets into the same completion list a language server's own snippet completions travel through.

## Behavioral Requirements

- **extension-snippet-fields**: `ExtensionSnippet` MUST expose `name: String`, `prefix: String`, `body: String`, `description: String?`, `scopes: [String]`, and `extensionIdentifier: String`, and MUST conform to `Sendable` and `Equatable`.
- **body-is-already-lsp-snippet-syntax**: `ExtensionSnippet.body` MUST be the raw LSP snippet string, tabstops and placeholders such as `$1` and `${1:name}` left intact and unparsed, because it is handed directly to `CompletionItem.insertText` for `LSPCompletionDelegate` to interpret.
- **applies-empty-scopes-is-universal**: `applies(to:)` MUST return `true` for every `language` when `scopes` is empty.
- **applies-nonempty-scopes-is-membership**: `applies(to:)` MUST return `true` only when `scopes` contains `language` exactly, when `scopes` is non-empty; a named scope MUST NOT be treated as narrowing some wider implicit default.
- **completion-item-label**: `completionItem()` MUST set the returned `CompletionItem.label` to `prefix`.
- **completion-item-filter-text**: `completionItem()` MUST set the returned `CompletionItem.filterText` to `prefix`.
- **completion-item-kind**: `completionItem()` MUST set `CompletionItem.kind` to `.snippet`.
- **completion-item-detail**: `completionItem()` MUST set `CompletionItem.detail` to `description` when it is non-nil, and to `name` when `description` is `nil`.
- **completion-item-insert-text**: `completionItem()` MUST set `CompletionItem.insertText` to `body`, unmodified.
- **completion-item-insert-text-format**: `completionItem()` MUST set `CompletionItem.insertTextFormat` to `.snippet`.
- **completion-item-no-text-edit**: `completionItem()` MUST leave `CompletionItem.textEdit` as `nil`, so `LSPCompletionDelegate.insertionText(for:)`'s fallback chain (the `textEdit`'s text, else `insertText`, else the label) supplies the inserted text, since a snippet file has no document range of its own to name.
- **snippet-file-parse-error-case**: `SnippetFileParseError` MUST expose exactly one case, `notAnObject`, for a decoded document whose root is not a JSON object.
- **snippet-file-parse-error-localized**: `SnippetFileParseError` MUST conform to `LocalizedError`, and its `errorDescription` MUST state that the document's root is not a JSON object, rather than Foundation's generic "The operation couldn't be completed" message.
- **snippet-file-accepts-jsonc**: `SnippetFile.parse(_:extensionIdentifier:)` MUST decode its input through `JSONCPreprocessor.jsonObject(from:)`, which strips `//` and `/* */` comments and trailing commas and tries UTF-8, UTF-16, and UTF-32 encodings in turn, so a JSONC-flavored or non-UTF-8 `.code-snippets`/`.json` file still parses.
- **snippet-file-root-must-be-object**: `SnippetFile.parse(_:extensionIdentifier:)` MUST throw `SnippetFileParseError.notAnObject` when the decoded root is not a `[String: Any]` object.
- **snippet-file-unparseable-text-throws**: `SnippetFile.parse(_:extensionIdentifier:)` MUST throw — never return `[]` — for text that is not literally `{}` and does not survive `JSONCPreprocessor` stripping into valid JSON, so "this file contributes nothing" and "this file could not be read" remain distinguishable.
- **snippet-file-name-is-the-key**: Every returned `ExtensionSnippet.name` MUST be the key under which its entry appeared in the root object.
- **snippet-file-order-is-sorted-by-name**: `SnippetFile.parse(_:extensionIdentifier:)` MUST return snippets ordered by an ascending sort of the root object's keys, not by the file's own byte order, since a deserialized JSON object carries no order of its own.
- **snippet-body-accepts-string-or-array**: An entry's `body` MUST be read as one string when its value is a `String`, and as that array's elements joined with `"\n"` when its value is a `[String]`.
- **snippet-body-wrong-type-skips-entry**: An entry whose `body` is absent, or present but neither a `String` nor a `[String]` — including a `[Any]` array with any non-`String` element — MUST be skipped and MUST produce no `ExtensionSnippet`.
- **snippet-prefix-accepts-string-or-array**: An entry's `prefix` MUST be read as one trigger word when its value is a `String`, and as every `String` element of the array, in declaration order, when its value is a `[Any]` array.
- **snippet-prefix-array-element-wise-leniency**: When `prefix` is an array, a non-`String` element MUST cost only that element, never the entry — unlike `body`'s array handling, whose single `as? [String]` cast rejects the whole entry on any non-`String` element.
- **snippet-prefix-empties-dropped**: An empty-string prefix, whether declared alone or as an array element, MUST be dropped and MUST NOT produce an `ExtensionSnippet`.
- **snippet-prefix-empty-after-filtering-skips-entry**: An entry MUST be skipped entirely when no non-empty `String` prefix remains after array leniency and empty-string filtering.
- **snippet-one-snippet-per-prefix**: An entry declaring more than one prefix MUST produce one `ExtensionSnippet` per prefix, in the array's declaration order, each sharing the same `name`, `body`, `description`, `scopes`, and `extensionIdentifier`.
- **snippet-description-optional-and-lenient**: An entry's `description` MUST be `nil` when the key is absent or its value is not a `String`.
- **snippet-scope-split-trimmed-filtered**: An entry's `scope` string MUST be split on `,`, each piece trimmed of leading and trailing whitespace and newlines, and any resulting empty piece dropped, to produce `scopes`.
- **snippet-scope-absent-yields-empty-scopes**: An entry with no `scope` key MUST produce `scopes == []`.
- **snippet-file-unknown-keys-ignored**: An entry object key other than `prefix`, `body`, `description`, or `scope` MUST NOT cause that entry, or the file, to be rejected, because entries are read by key off a deserialized `[String: Any]` rather than decoded through a strict `Codable` type.
- **snippet-file-parse-from-url**: `SnippetFile.parse(contentsOf:extensionIdentifier:)` MUST read `url` with `Data(contentsOf:)` and pass the bytes to `parse(_:extensionIdentifier:)`, propagating whatever error `Data(contentsOf:)` throws for a URL that cannot be read.
- **snippet-file-empty-object-is-empty-result**: `SnippetFile.parse(_:extensionIdentifier:)` MUST return `[]`, without throwing, for an input whose root is `{}`.
- **snippet-file-failure-fields**: `SnippetFileFailure` MUST expose `extensionIdentifier: String`, `path: String`, and `reason: String`, and MUST conform to `Sendable` and `Equatable`.
- **snippet-store-contribution-key**: `SnippetStore.contributionKey` MUST be `"snippets"`.
- **snippet-store-main-actor-class**: `SnippetStore` MUST be a `final class` isolated to `@MainActor`, satisfying `ContributionPoint`'s constraint to `AnyObject`-conforming, `@MainActor`-isolated conformers (agentictoolkit://recipes/extension-host-core-extensions-contribution-point).
- **apply-resolves-path-inside-directory**: `SnippetStore.apply(_:from:at:)` MUST resolve each declared `contributions.snippets` entry's `path` against `directory` through `ExtensionResourcePath.resolve(_:inside:)` (agentictoolkit://recipes/extension-host-core-extensions-extension-resource-path) before reading it.
- **apply-refuses-escaping-path**: `SnippetStore.apply(_:from:at:)` MUST NOT read a file whose resolved path lies outside `directory`; it MUST instead catch the thrown `ExtensionResourcePathError.escapesExtensionDirectory` and record it as a `SnippetFileFailure`.
- **apply-per-entry-error-isolation**: An entry whose path resolution or file parse throws, inside `SnippetStore.apply(_:from:at:)`, MUST NOT prevent any other declared entry for the same extension from being read.
- **apply-failure-path-is-declared-string**: A recorded `SnippetFileFailure.path` MUST be the entry's `path` exactly as the manifest declared it, not the resolved URL.
- **apply-failure-reason-is-localized-description**: A recorded `SnippetFileFailure.reason` MUST be the thrown error's `localizedDescription`.
- **apply-buckets-by-own-scope-or-manifest-language**: `SnippetStore.apply(_:from:at:)` MUST file each parsed snippet under every language named in the snippet's own `scopes` when `scopes` is non-empty, and under the manifest entry's `language` when `scopes` is empty.
- **apply-multi-scope-fan-out**: A snippet whose `scopes` names more than one language MUST be filed under every one of those languages.
- **apply-concatenates-multiple-files-per-language**: Two or more manifest entries declaring the same `language` MUST have their snippets concatenated for that language, in the entries' declaration order.
- **apply-replaces-prior-contribution**: `SnippetStore.apply(_:from:at:)` MUST call `withdraw(extensionIdentifier:)` for the same identifier before reading any of the extension's declared entries.
- **apply-is-idempotent**: Calling `SnippetStore.apply(_:from:at:)` twice with the same manifest and directory MUST leave exactly one copy of each snippet, never two.
- **apply-no-entries-declared-contributes-none**: `SnippetStore.apply(_:from:at:)` MUST leave `snippets(forLanguage:)` returning `[]` for every language, and `failures` unchanged, when `contributions.snippets` is empty.
- **apply-declared-throwing-never-thrown-in-practice**: `SnippetStore.apply(_:from:at:)`'s signature MUST be able to throw, per `ContributionPoint`, but MUST NOT actually throw for any per-entry failure; every per-entry error MUST be caught and recorded as a `SnippetFileFailure` instead.
- **withdraw-removes-snippets-and-failures**: `SnippetStore.withdraw(extensionIdentifier:)` MUST remove every snippet and every `SnippetFileFailure` recorded for that identifier.
- **withdraw-is-safe-on-unknown-identifier**: `SnippetStore.withdraw(extensionIdentifier:)` MUST be safe to call for an identifier that was never applied.
- **withdraw-is-per-extension**: `SnippetStore.withdraw(extensionIdentifier:)` MUST NOT remove another extension's snippets or failures.
- **snippets-for-language-filters-by-applies**: `SnippetStore.snippets(forLanguage:)` MUST return only snippets whose own `applies(to:)` predicate holds for `language`, in addition to that language being one they were filed under.
- **snippets-for-language-ordering**: `SnippetStore.snippets(forLanguage:)` MUST order its result first by the contributing extensions' identifiers sorted ascending, then, within one extension, by the order its snippets were filed for that language.

## Appearance

Not applicable — this is a set of model types and a contribution-point store, not a visual component.

## States

Not applicable — this is a set of model types and a contribution-point store, not a visual component. The applied-versus-withdrawn lifecycle of a snippet contribution is covered under Behavioral Requirements, not as a visual-state table.

## Accessibility

Not applicable — this is a set of model types and a contribution-point store, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| language-services-snippets-001 | extension-snippet-fields, snippet-file-name-is-the-key, snippet-scope-absent-yields-empty-scopes | `SnippetFile.parse` on `{"For Loop": {"prefix": "for", "body": "for (const item of list) { $0 }", "description": "A for-of loop"}}` (traced to `SnippetFileTests.documentedFields`) | One `ExtensionSnippet`: `name == "For Loop"`, `prefix == "for"`, `body == "for (const item of list) { $0 }"`, `description == "A for-of loop"`, `scopes == []` |
| language-services-snippets-002 | snippet-description-optional-and-lenient | `SnippetFile.parse` on `{"Log": {"prefix": "log", "body": "print($1)"}}` (traced to `SnippetFileTests.descriptionIsOptional`) | `description == nil` |
| language-services-snippets-003 | snippet-body-accepts-string-or-array | `SnippetFile.parse` on an entry whose `body` is `["guard let ${1:value} else {", "    return", "}"]` (traced to `SnippetFileTests.arrayBodyIsJoined`) | `body == "guard let ${1:value} else {\n    return\n}"` |
| language-services-snippets-004 | snippet-scope-split-trimmed-filtered | `SnippetFile.parse` on an entry whose `scope` is `"typescript, typescriptreact ,,javascript"` (traced to `SnippetFileTests.scopeIsSplit`) | `scopes == ["typescript", "typescriptreact", "javascript"]` |
| language-services-snippets-005 | snippet-prefix-accepts-string-or-array, snippet-one-snippet-per-prefix | `SnippetFile.parse` on an entry whose `prefix` is `["rfc", "rface"]` (traced to `SnippetFileTests.arrayPrefixBecomesOneSnippetPerTriggerWord`) | Two snippets with `prefix` values `["rfc", "rface"]`, both sharing the entry's `body`, `description`, and `scopes` |
| language-services-snippets-006 | snippet-prefix-array-element-wise-leniency | `SnippetFile.parse` on an entry whose `prefix` is `["log", 7, ""]` (traced to `SnippetFileTests.strayPrefixElementCostsOnlyItself`) | One snippet: `prefix == "log"` |
| language-services-snippets-007 | snippet-prefix-empty-after-filtering-skips-entry | Three entries — `prefix: []`, `prefix: [7]`, and a usable `prefix: "ok"` (traced to `SnippetFileTests.emptyPrefixArrayIsSkipped`) | Only the `"Usable"` entry's snippet is returned |
| language-services-snippets-008 | snippet-body-wrong-type-skips-entry | Four entries — no `body`, `body: 42`, `body: ["line", 2]`, and a usable string `body` (traced to `SnippetFileTests.missingOrWrongTypedBodyIsSkipped`) | Only the `"Usable"` entry's snippet is returned; the mixed-type array entry is skipped in full, unlike a mixed-type prefix array |
| language-services-snippets-009 | snippet-file-unknown-keys-ignored | An entry with `key`, `isFileTemplate`, and the misspelled `descriptison` alongside `prefix`/`body` (traced to `SnippetFileTests.undocumentedKeysAreIgnored`) | One snippet is returned with `description == nil` |
| language-services-snippets-010 | snippet-file-order-is-sorted-by-name | `SnippetFile.parse` on entries keyed `"charlie"`, `"alpha"`, `"bravo"` in that byte order (traced to `SnippetFileTests.stableOrder`) | Returned names are `["alpha", "bravo", "charlie"]` |
| language-services-snippets-011 | snippet-file-accepts-jsonc | A file with a `//` line comment, a `/* */` block comment, and a trailing comma (traced to `SnippetFileTests.jsoncParses`) | One snippet: `prefix == "log"` |
| language-services-snippets-012 | snippet-file-empty-object-is-empty-result | `SnippetFile.parse` on `"{}"` (traced to `SnippetFileTests.emptyObjectIsEmpty`) | `[]`, no error thrown |
| language-services-snippets-013 | snippet-file-root-must-be-object, snippet-file-parse-error-case | `SnippetFile.parse` on `"[]"` (traced to `SnippetFileTests.rootArrayThrows`) | Throws `SnippetFileParseError.notAnObject` |
| language-services-snippets-014 | snippet-file-parse-error-localized | `SnippetFileParseError.notAnObject.localizedDescription` (traced to `SnippetFileTests.parseFailureDescribesItself`) | Non-empty string containing `"JSON object"`, not containing `"couldn't be completed"` |
| language-services-snippets-015 | snippet-file-unparseable-text-throws | `SnippetFile.parse` on a comment-only `.code-snippets` file, and on a file malformed once its commented-out entry is stripped (traced to `SnippetFileTests.commentOnlyFileThrows` and `.malformedAfterStrippingThrows`) | Both throw an error; neither returns `[]` |
| language-services-snippets-016 | snippet-file-parse-from-url | `SnippetFile.parse(contentsOf:extensionIdentifier:)` on a URL that does not exist (traced to `SnippetFileTests.parseMissingFileThrows`) | Throws the underlying file-read error |
| language-services-snippets-017 | completion-item-label, completion-item-filter-text, completion-item-kind, completion-item-detail, completion-item-insert-text, completion-item-insert-text-format, completion-item-no-text-edit | `ExtensionSnippet(name: "Log", prefix: "log", body: "console.log(${1:value})$0", description: "Logs a value", scopes: [], extensionIdentifier: "acme.snippets").completionItem()` (traced to `ExtensionSnippetTests.completionItemMapping`) | `label == "log"`, `kind == .snippet`, `detail == "Logs a value"`, `filterText == "log"`, `insertText == "console.log(${1:value})$0"`, `insertTextFormat == .snippet`, `textEdit == nil` |
| language-services-snippets-018 | completion-item-detail | The same snippet with `description: nil` (traced to `ExtensionSnippetTests.detailFallsBackToName`) | `completionItem().detail == "Log"` |
| language-services-snippets-019 | body-is-already-lsp-snippet-syntax | `Snippet(value: snippet().body).enumerateElements` over `"console.log(${1:value})$0"` (traced to `ExtensionSnippetTests.bodyParsesAsAnLSPSnippet`) | The concatenated `.text`/`.placeholder` elements read `"console.log(value)"`, confirming `body` round-trips through the vendored LSP snippet parser unmodified |
| language-services-snippets-020 | applies-empty-scopes-is-universal | `snippet(scopes: []).applies(to: "swift")` (traced to `ExtensionSnippetTests.unscopedApplies`) | `true` |
| language-services-snippets-021 | applies-nonempty-scopes-is-membership | `snippet(scopes: ["typescript", "javascript"]).applies(to:)` for `"typescript"`, `"javascript"`, and `"swift"` (traced to `ExtensionSnippetTests.scopeIsMembership`) | `true`, `true`, `false` |
| language-services-snippets-022 | snippet-store-contribution-key | `SnippetStore().contributionKey` (traced to `SnippetStoreTests.contributionKey`) | `"snippets"` |
| language-services-snippets-023 | apply-resolves-path-inside-directory, apply-buckets-by-own-scope-or-manifest-language | Apply a manifest declaring `("swift", "./snippets/swift.json")` against a directory containing that file with one unscoped `log` snippet (traced to `SnippetStoreTests.readsRelativeToDirectory`) | `store.snippets(forLanguage: "swift").map(\.prefix) == ["log"]`; `store.failures.isEmpty` |
| language-services-snippets-024 | apply-buckets-by-own-scope-or-manifest-language | Apply the same fixture, then query `snippets(forLanguage: "python")` (traced to `SnippetStoreTests.languageKeying`) | `[]` — the manifest entry's `language` is the only unscoped key |
| language-services-snippets-025 | apply-buckets-by-own-scope-or-manifest-language, snippets-for-language-filters-by-applies | Apply a `typescript`-declared file with one unscoped `"any"` snippet and one `"cmp"` snippet scoped `"typescriptreact"` (traced to `SnippetStoreTests.scopeDecidesTheBucket`) | `snippets(forLanguage: "typescript") == ["any"]`; `snippets(forLanguage: "typescriptreact") == ["cmp"]` |
| language-services-snippets-026 | apply-buckets-by-own-scope-or-manifest-language | A `.code-snippets` file declared under `"javascript"` whose one entry's `scope` is `"typescript"` (traced to `SnippetStoreTests.scopeMayRedirectAwayFromTheManifestLanguage`) | `snippets(forLanguage: "typescript") == ["iface"]`; `snippets(forLanguage: "javascript") == []` |
| language-services-snippets-027 | apply-multi-scope-fan-out | An entry scoped `"javascript,typescript"` declared under `"javascript"` (traced to `SnippetStoreTests.multiScopeSnippetIsFiledUnderEachScope`) | Both `snippets(forLanguage: "javascript")` and `snippets(forLanguage: "typescript")` contain the snippet |
| language-services-snippets-028 | apply-refuses-escaping-path, apply-failure-path-is-declared-string | Apply a manifest entry `("swift", "../outside/secret.json")` naming a real, readable file outside the extension directory (traced to `SnippetStoreTests.escapingPathIsRefused`) | `snippets(forLanguage: "swift").isEmpty`; `failures.map(\.path) == ["../outside/secret.json"]` |
| language-services-snippets-029 | apply-refuses-escaping-path | The same shape against a sibling directory sharing a name prefix (`ext-evil` beside `ext`) (traced to `SnippetStoreTests.siblingWithSharedNamePrefixIsRefused`) | `snippets(forLanguage: "swift").isEmpty`; the escape is still refused, proving containment is not a string-prefix check |
| language-services-snippets-030 | apply-concatenates-multiple-files-per-language | Two manifest entries for `"swift"`, one contributing `"log"` and the other `"guard"` (traced to `SnippetStoreTests.twoFilesOneLanguage`) | `snippets(forLanguage: "swift").map(\.prefix) == ["log", "guard"]` |
| language-services-snippets-031 | apply-is-idempotent, apply-replaces-prior-contribution | `apply(loaded, ...)` called twice with the same manifest and directory (traced to `SnippetStoreTests.applyIsIdempotent`) | `snippets(forLanguage: "swift").count == 1` |
| language-services-snippets-032 | apply-per-entry-error-isolation, apply-failure-reason-is-localized-description | One entry pointing at a comment-only file, one at a good file, both declared for `"swift"` (traced to `SnippetStoreTests.oneBadFileDoesNotSinkTheRest`) | `snippets(forLanguage: "swift").map(\.prefix) == ["log"]`; `failures.count == 1`; the recorded `reason` is non-empty |
| language-services-snippets-033 | apply-per-entry-error-isolation, apply-failure-path-is-declared-string | An entry declaring `"./snippets/absent.json"`, which is not on disk (traced to `SnippetStoreTests.missingFileIsRecorded`) | `snippets(forLanguage: "swift").isEmpty`; `failures.map(\.path) == ["./snippets/absent.json"]` |
| language-services-snippets-034 | withdraw-removes-snippets-and-failures | Apply an extension with one good and one broken file, then `withdraw(extensionIdentifier:)` (traced to `SnippetStoreTests.withdrawRemovesEverything`) | After withdrawal, `snippets(forLanguage: "swift").isEmpty` and `failures.isEmpty` |
| language-services-snippets-035 | withdraw-is-safe-on-unknown-identifier | `withdraw(extensionIdentifier: "nobody.nothing")` on a store nothing was ever applied to (traced to `SnippetStoreTests.withdrawUnknownIsSafe`) | No error; `snippets(forLanguage: "swift").isEmpty` |
| language-services-snippets-036 | withdraw-is-per-extension, snippets-for-language-ordering | Two extensions (`"acme.snippets"` contributing `"log"`, `"more-snippets"` contributing `"guard"`) both apply, then the first is withdrawn (traced to `SnippetStoreTests.withdrawIsPerExtension`, extended per `SnippetStore.snippets(forLanguage:)`'s own `snippetsByExtension.keys.sorted()` implementation) | Before withdrawal, `snippets(forLanguage: "swift") == ["log", "guard"]` (identifiers sorted ascending: `"acme.snippets"` before `"more-snippets"`); after withdrawing `"acme.snippets"`, only `["guard"]` remains |
| language-services-snippets-037 | apply-no-entries-declared-contributes-none | Apply a manifest whose `contributions.snippets` array is empty (traced to `SnippetStoreTests.noSnippetsDeclared`) | `snippets(forLanguage: "swift").isEmpty`; `failures.isEmpty` |
| language-services-snippets-038 | snippet-store-main-actor-class | Inspect the declaration `@MainActor public final class SnippetStore: ContributionPoint` (traced to `SnippetStore.swift`'s own type declaration) | `SnippetStore` is a class, not a struct or enum, and the compiler rejects any call into it from off the main actor with no `await` |

## Edge Cases

- **Null and empty input**: An empty snippets file (`{}`) MUST parse to `[]`, not throw (snippet-file-empty-object-is-empty-result). An extension whose manifest declares no `snippets` entries at all MUST leave the store contributing nothing for it, with no recorded failure (apply-no-entries-declared-contributes-none). An entry's empty-string `prefix`, alone or inside an array, MUST be dropped rather than kept as an unreachable trigger word (snippet-prefix-empties-dropped); an entry left with no prefix at all MUST be skipped (snippet-prefix-empty-after-filtering-skips-entry).
- **Boundary values**: There is no declared minimum or maximum on the number of prefixes an entry may declare, the number of scopes a `scope` string may name, or the number of snippet files one manifest entry may point at — `SnippetFile`, `SnippetStore.apply`, and `snippets(forLanguage:)` all iterate whatever collection they are given with no size check (snippet-one-snippet-per-prefix, apply-multi-scope-fan-out, apply-concatenates-multiple-files-per-language are each exercised with a small fixed count in the tests, but the source imposes no ceiling).
- **Concurrent access**: `SnippetStore` is `@MainActor`-isolated and is not itself declared `Sendable` (snippet-store-main-actor-class), so the compiler serializes every `apply`, `withdraw`, and `snippets(forLanguage:)` call onto the main actor; two calls issued from concurrent tasks run one after the other, never interleaved, and no lock exists in the source because none is needed. `ExtensionSnippet` and `SnippetFileFailure` are immutable, `Sendable` value types (extension-snippet-fields, snippet-file-failure-fields), so a copy of either can cross an actor boundary freely, but neither carries mutable shared state to race over.
- **Error states**: A snippets file that cannot be read (missing, unreadable, or a path that escapes the extension's directory) MUST be recorded as a `SnippetFileFailure` with a human-readable `reason`, and MUST NOT stop any other declared file for the same extension from being read (apply-per-entry-error-isolation, apply-refuses-escaping-path). A file whose text is not `{}` and does not survive JSONC stripping into valid JSON MUST throw out of `SnippetFile.parse`, and `SnippetStore.apply`'s per-entry `do`/`catch` MUST turn that thrown error into the same kind of recorded failure, never letting it escape `apply` itself (snippet-file-unparseable-text-throws, apply-declared-throwing-never-thrown-in-practice).
- **Offline or disconnected state**: Not applicable — `ExtensionSnippet.swift`, `SnippetFile.swift`, and `SnippetStore.swift` read only local files (`Data(contentsOf:)`) and parse in-memory JSON; none imports `Foundation.URLSession` or any networking type, so there is no network connection to lose.
- **A path that escapes the extension's own directory**: `SnippetStore.apply(_:from:at:)` MUST refuse to read it and MUST record the refusal as a failure keyed by the declared path string, whether the escape targets a literal parent directory or a sibling directory whose name merely shares a string prefix with the extension's own folder name (apply-refuses-escaping-path).
- **A file that nests a category name one level too deep**: an entry whose value is itself `{"Inner": {"prefix": "in", "body": "…"}}` rather than a snippet object has no `prefix` or `body` of its own at that level, so it is skipped like any other entry with a missing prefix (snippet-prefix-empty-after-filtering-skips-entry); the inner, well-formed snippet is never read, because `SnippetFile` inspects only the root object's immediate values, and the file's other, flat entries still load.
- **A `prefix` array versus a `body` array with the same shape of mixed-type element**: the two are handled differently on purpose — a bad `prefix` element costs only itself (snippet-prefix-array-element-wise-leniency) while any bad `body` element costs the whole entry (snippet-body-wrong-type-skips-entry); a port MUST NOT assume the two array-typed fields share one leniency rule.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `extensionIdentifier` | `String` | none — required | Passed to `SnippetFile.parse` and `SnippetStore.apply`; identifies which extension a snippet, or a recorded failure, came from. `SnippetStore.apply` supplies `manifest.identifier`. |
| `directory` | `URL` | none — required | Passed to `SnippetStore.apply`; the extension's own installed folder, both the base every declared `path` resolves against and the boundary it may not leave. |
| `contributions.snippets` | `[ExtensionManifest.Contributions.Snippet]` (`language: String`, `path: String` pairs) | `[]` when the manifest's `contributes.snippets` key is absent | The declared entries `SnippetStore.apply` reads; each `path` is resolved relative to `directory` and each `language` is the fallback bucket for a snippet whose own `scope` is empty. |
| `SnippetStore.init()` | initializer, no parameters | — | Constructs a store with no applied snippets and no recorded failures; `ExtensionsCoordinator` calls it once and reuses the instance. |

## Deep Linking

Not applicable: none of `ExtensionSnippet.swift`, `SnippetFile.swift`, or `SnippetStore.swift` defines a URL scheme, route, or navigation target.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `SnippetFileParseError.notAnObject.errorDescription` | "The file's root is not a JSON object. A snippets file is an object whose keys are snippet names." | Recorded verbatim as a `SnippetFileFailure.reason` and shown in the extensions settings panel when a snippets file's root is not a JSON object. |

This is the only user-facing string these three files define, and it is hardcoded English with no localization table entry or lookup key of its own — `SnippetFileFailure.reason` is a plain `String`, not a localization key, so this string ships in one language regardless of the app's locale.

## Accessibility Options

Not applicable: these files have no UI of their own, so they respond to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: none of `ExtensionSnippet.swift`, `SnippetFile.swift`, or `SnippetStore.swift` declares a feature-flag key or conditionally gates a feature on one.

## Analytics

Not applicable: none of these three files contains an analytics or event-emission call.

## Privacy

- **Data collected**: None of `ExtensionSnippet`, `SnippetFileFailure`, or `SnippetStore`'s own state defines a field for a credential or token. `ExtensionSnippet.body`/`.prefix` are values taken verbatim from a snippets file an extension bundles or a user edits by hand; `SnippetFileFailure.path`/`.reason` carry only a manifest-declared file path string and a parse-failure sentence.
- **Storage**: `SnippetStore` holds every applied extension's snippets and failures only in memory, in `snippetsByExtension` and `failures`; none of these three files writes to disk. The snippet files themselves are read from wherever the extension is installed, resolved through `ExtensionResourcePath` (agentictoolkit://recipes/extension-host-core-extensions-extension-resource-path).
- **Transmission**: Not applicable — none of `ExtensionSnippet.swift`, `SnippetFile.swift`, or `SnippetStore.swift` performs network I/O.
- **Retention**: `SnippetStore.withdraw(extensionIdentifier:)` is what removes an extension's snippets and failures from memory (withdraw-removes-snippets-and-failures); nothing here is retained beyond the store's own in-memory lifetime and that call.
- The containment check `apply-refuses-escaping-path` enforces exists precisely to stop a maliciously declared `path` — the escaping-path tests' own comments cite `../../../.ssh/config` as the motivating example — from being read as though it were a snippet and typed into a user's document; `SnippetStore.apply` records that refusal as a failure rather than reading the file.

## Logging

Not applicable: none of `ExtensionSnippet.swift`, `SnippetFile.swift`, or `SnippetStore.swift` calls `os_log`, `Logger`, or `print`. Parse and read failures are recorded into `SnippetStore.failures` for the extensions settings panel to display, not written to a log.

## Platform Notes

- **SwiftUI**: none of these three files imports SwiftUI, Combine, or `Observation`. A SwiftUI-backed consumer reads `SnippetStore.snippets(forLanguage:)` as plain, already-computed data; if a view must react live to a later `withdraw` or `apply`, it needs its own observation wrapper around the store, since `SnippetStore` publishes nothing itself.
- **Compose**: a Kotlin port models `ExtensionSnippet` as a `data class` over the same six fields (its structural equality standing in for `Equatable`), `SnippetFileParseError` as a `sealed class`/exception type, and `SnippetFile` as a Kotlin `object` whose `parse` functions traverse a `JsonObject` (from `kotlinx.serialization.json` or `org.json`), applying the same string-vs-array, element-wise-vs-whole-array leniency distinctions by hand. `SnippetStore` becomes a class confined to a single coroutine dispatcher — the direct analogue of `@MainActor` — holding a `MutableMap<String, MutableMap<String, List<ExtensionSnippet>>>` for `snippetsByExtension` and a `MutableList<SnippetFileFailure>` for `failures`.
- **React/Web**: a TypeScript port models `ExtensionSnippet` as a `readonly` interface, `SnippetFile.parse` as a function that returns `ExtensionSnippet[]` or throws, operating over `JSON.parse`'s `Record<string, unknown>` output after a small JSONC-stripping step (a hand-written scanner, or a library such as `jsonc-parser`, standing in for `JSONCPreprocessor`). `SnippetStore` becomes a plain class, since JavaScript has no actor isolation to declare; the port instead documents, as a convention rather than a compiler guarantee, that every call into one `SnippetStore` instance must originate on the same event-loop turn.
- **AppKit / UIKit**: this is the source. `ExtensionSnippet.swift`, `SnippetFile.swift`, and `SnippetStore.swift` live in `packages/apple/AgenticToolkit/Language/Snippets/`, part of the `AgenticToolkitLanguage` target, which `project.yml` declares macOS-only (`platform: macOS`). `SnippetStore` is constructed once by `ExtensionsCoordinator` and read by `LSPCompletionDelegate.completionSuggestionsRequested` (`snippets?.snippets(forLanguage: languageId).map { $0.completionItem() }`), which is how a snippet's `CompletionItem` reaches the `CodeEditSourceEditor`-backed completion UI. It depends on `ExtensionResourcePath` and `JSONCPreprocessor` from the `AgenticToolkitCore` target, and on `ExtensionManifest.Contributions.Snippet` from the same target.
- **WinUI 3**: a .NET port models `ExtensionSnippet` as an immutable `record` over `Name`, `Prefix`, `Body`, `Description` (`string?`), `Scopes` (`IReadOnlyList<string>`), and `ExtensionIdentifier` (record equality standing in for `Equatable`). `SnippetFile` becomes a static class parsing with `System.Text.Json.JsonDocument`, checking each entry's `JsonElement.ValueKind` before reading it — the direct analogue of the Swift `as?` casts — with a small preprocessor ahead of it for trailing commas, since `System.Text.Json`'s `JsonCommentHandling.Skip` accepts comments but not trailing commas. `SnippetStore` becomes a `sealed class` confined to the UI thread, asserted with `Debug.Assert(DispatcherQueue.HasThreadAccess)` mirroring `@MainActor`, holding `Dictionary<string, Dictionary<string, List<ExtensionSnippet>>>` for its per-extension, per-language buckets and a `List<SnippetFileFailure>` for `Failures`; the path-containment check ports as a call into that platform's `ExtensionResourcePath` equivalent, `Path.GetFullPath` plus a canonicalized-prefix comparison being the direct analogue of `ExtensionResourcePath.resolve`.

## Design Decisions

**Decision**: `prefix`'s array handling drops a bad element and keeps the rest (`compactMap`), while `body`'s array handling (`as? [String]`) rejects the whole entry on any bad element.
**Rationale**: the source's own doc comment on `prefixes(from:)` describes this as "the same string-or-array tolerance `body(from:)` has carried all along, applied to the other half of the pair," which reads as claiming symmetry with `body`'s leniency; `SnippetFileTests.missingOrWrongTypedBodyIsSkipped`'s `"Mixed array body": ["line", 2]` case proves the two are not symmetric — `body` rejects that whole entry rather than keeping `"line"`. A port MUST implement the two independently rather than trusting the comment's implied parity.
**Approved**: pending

**Decision**: `SnippetFile.parse(_:extensionIdentifier:)` sorts by name (root object keys), while `SnippetStore.snippets(forLanguage:)` preserves an extension's own file-declaration order and `prefixes(from:)` preserves an entry's own array-declaration order.
**Rationale**: a deserialized JSON object has no order of its own, so `SnippetFile` imposes a stable one (sorted keys) to keep a completion list from reshuffling between launches; an array, by contrast, already has a real declared order — the manifest's entry list, or a `prefix` array's element order — and the source deliberately preserves that order rather than re-sorting it, because it is information the extension author wrote and not an artifact of decoding.
**Approved**: pending

**Decision**: `SnippetStore.apply(_:from:at:)` can throw per its `ContributionPoint` conformance, but every path that can fail inside it — path resolution, file read, JSON/JSONC parse — is caught locally and turned into a `SnippetFileFailure` instead of being rethrown.
**Rationale**: `SnippetStore.swift`'s own doc comment states the type "never throws in practice," because one bad snippet file must not cost the extension its other, good snippet files (apply-per-entry-error-isolation); `throws` remains in the signature only because `ContributionPoint` declares it and because a future whole-extension failure — one that is not per-file — would have somewhere to go.
**Approved**: pending

**Decision**: `snippetsByExtension[identifier] = byLanguage` is assigned unconditionally after the per-entry loop, even when every entry failed and `byLanguage` is empty, rather than being skipped when nothing was read.
**Rationale**: per `SnippetStore.swift`'s own comment, an extension whose files all parsed to nothing usable is still an extension that contributed; guarding the assignment on `byLanguage.isEmpty` would not change what `snippets(forLanguage:)` returns (`?? []` already covers a missing key) but would leave one more state — "applied but not recorded" versus "applied and recorded empty" — for a reader to reason about for no behavioral benefit.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |

`separation-of-concerns` passes because each file owns one concern — `ExtensionSnippet` is a pure model and LSP conversion, `SnippetFile` is pure parsing, and `SnippetStore` is the only one that touches the file system or the contribution-point lifecycle — while path safety and JSONC decoding are factored into the shared `ExtensionResourcePath` and `JSONCPreprocessor` types rather than duplicated here. `unit-test-coverage` passes: `SnippetFileTests`, `ExtensionSnippetTests`, and `SnippetStoreTests` together exercise every documented parsing leniency, every failure path (missing file, escaping path, malformed JSONC, comment-only file), scope bucketing in both directions, idempotent re-application, and per-extension withdrawal. `explicit-error-handling` passes because `SnippetFileParseError` and the dependency `ExtensionResourcePathError` are explicit, typed, `LocalizedError`-conforming errors, and `SnippetStore.apply` turns every one it catches into a `SnippetFileFailure` with a human-readable `reason` rather than dropping it silently. `idempotent-operations` passes because `apply` is explicitly tested to leave one copy on repeated application (apply-is-idempotent) and `withdraw` is explicitly tested safe on an identifier that was never applied (withdraw-is-safe-on-unknown-identifier).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
