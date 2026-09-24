---
id: 24e1710c-a805-4f6e-b720-fbd869472ca9
title: ExtensionManifestLocalization
domain: agentictoolkit://recipes/extension-host-core-extensions-extension-manifest-localization
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Resolves %key% placeholders in a VS Code package.json against package.nls*.json
  tables beside it; never throws, leaves unresolved keys visible.
platforms:
- swift
- macos
tags:
- extensions
- manifest
- localization
- package-json
- jsonc
depends-on: []
related:
- agentictoolkit://recipes/extension-host-core-extensions-extension-manifest
references:
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionManifestLocalization.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/ExtensionManifestLocalizationTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# ExtensionManifestLocalization

## Overview

`ExtensionManifestLocalization` is a Foundation-only, caseless `public enum`
in `AgenticToolkitCore`
(`packages/apple/AgenticToolkit/Core/Extensions/ExtensionManifestLocalization.swift`,
a macOS-only framework target per `project.yml`) that resolves the `%key%`
placeholders a VS Code `package.json` uses in place of the strings a person
reads. An extension that ships translations does not put
English in `package.json` at all — it writes `"displayName": "%name%"` and
puts the English in `package.nls.json` beside it, the German in
`package.nls.de.json`, and so on. `localize(_:forManifestIn:locale:)` is the
single entry point both of the manifest's readers call before decoding —
`ExtensionRegistry`, which decodes an installed extension, and
`VSIXInstaller`, which decodes one it is about to install — so translation
resolution happens exactly once, at the one place the bytes become an
`ExtensionManifest`, rather than at each place a manifest string is later
displayed (`ExtensionRegistry.swift`;
`VSIXInstaller.swift`). It never throws: a missing, unreadable, or
malformed table costs the extension its translations and nothing else.

## Behavioral Requirements

- **placeholder-substitution**: `localize(_:forManifestIn:locale:)` MUST
  return `json` with every `%key%` placeholder that the merged localization
  table for `directory`/`locale` can answer replaced by the string that key
  stands for.
- **no-throw-contract**: `localize` MUST NOT declare `throws` and MUST
  return a value for every input; a missing, unreadable, or malformed
  localization table MUST cost the manifest its translations and nothing
  else, and MUST NOT propagate an error to the caller (doc
  comment).
- **unchanged-when-no-table**: `localize` MUST return `json` unchanged, byte
  for byte, without parsing or re-serializing it, when the merged table for
  `directory`/`locale` is empty (`noTableMeansNoChange`).
- **unchanged-when-unparseable-input**: `localize` MUST return `json`
  unchanged when `JSONCPreprocessor.jsonObject(from:)` throws for `json`
  itself.
- **unchanged-when-unserializable-output**: `localize` MUST return `json`
  unchanged when `JSONSerialization.data(withJSONObject:)` throws while
  re-serializing the substituted tree.
- **default-locale-is-current**: `localize`'s `locale` parameter MUST
  default to `Locale.current` when the caller supplies none.
- **table-search-order**: The table filenames searched for a given
  `locale`, least specific first, MUST be `package.nls.json`, then
  `package.nls.<language>.json` when the locale has a language code, then
  `package.nls.<language>-<region>.json` when the locale additionally has a
  region.
- **language-code-absent-limits-search**: `tableNames(for:)` MUST return
  only `["package.nls.json"]` when `locale.language.languageCode` is `nil`.
- **default-table-not-overwritten**: A key present only in the default
  (`package.nls.json`) table MUST remain available in the merged table even
  when a more specific table for the same `locale` is also present (82-84; `theDefaultTableFillsTheGapsInATranslation`).
- **more-specific-table-wins**: For a key present in more than one table
  that applies to `locale`, the value from the most specific table
  (region-and-language over bare-language over default) MUST be the one the
  merged table returns (96-104; `theReadersLanguageWins`,
  `aRegionalTableWins`).
- **table-filename-case-insensitive**: A table file on disk MUST be matched
  against its expected name without regard to case.
- **missing-table-file-contributes-nothing**: A table filename with no
  case-insensitively matching entry in `directory`'s contents MUST be
  skipped, contributing no entries and not failing the merge (`anUntranslatedLanguageFallsBack`).
- **unreadable-directory-yields-no-tables**: `fileNames(in:)` MUST return
  `[:]` when `FileManager.default.contentsOfDirectory(atPath:)` throws for
  `directory`, so a nonexistent or unreadable `directory` MUST be treated
  identically to one with no localization tables at all.
- **unreadable-table-file-contributes-nothing**: `entries(inTableAt:)` MUST
  return `[:]` when `Data(contentsOf:)` throws for the table's `url`.
- **malformed-table-contributes-nothing**: `entries(inTableAt:)` MUST return
  `[:]` when `JSONCPreprocessor.jsonObject(from:)` throws for the table's
  contents, or when the parsed value is not a `[String: Any]` object (`anUnreadableTableIsNotFatal`).
- **table-supports-jsonc**: A table file MUST be parsed via
  `JSONCPreprocessor.jsonObject(from:)`, so a table written with `//`
  comments or a trailing comma MUST be read the same as strict JSON.
- **table-entry-two-value-shapes**: A table entry MUST resolve to a string
  when its JSON value is either a bare string or an object with a `message`
  string field, and MUST be dropped from the table for any other JSON shape
  (`theMessageAndCommentShapeIsUnderstood`).
- **substitution-walks-full-tree**: Substitution MUST be applied to every
  string value at every depth of the parsed manifest tree, including inside
  arrays and inside objects nested arbitrarily deep (`theDefaultTableSuppliesTheStrings`, which resolves a value five levels
  down at `contributes.configuration[].properties.<setting>.description`).
- **object-keys-never-substituted**: Substitution MUST be applied only to a
  JSON object's values, never to its keys, regardless of whether a key's
  text would otherwise match the placeholder pattern.
- **non-string-values-pass-through**: A JSON value that is not a string —
  `null`, a boolean, a number, an array, or an object — MUST be returned
  from `substituting` with its own kind unchanged, with substitution applied
  only to any string values nested inside it (`nonStringValuesSurvive`).
- **placeholder-must-be-whole-string**: A string MUST be treated as a
  placeholder reference only when its entire content, not a prefix, suffix,
  or substring, is a single `%…%` token — `string.count` greater than `2`
  and the string both starting and ending with `%` (`proseIsNotAPlaceholder`).
- **placeholder-key-rejects-embedded-percent**: A candidate placeholder
  whose extracted key — the text between the leading and trailing `%` —
  itself contains a `%` character MUST be returned unchanged rather than
  looked up.
- **unresolved-placeholder-left-visible**: A placeholder string whose
  extracted key has no entry in the merged table MUST be returned unchanged,
  leaving the literal `%key%` text visible in the output rather than
  substituting an empty string (`anUnknownKeyIsLeftVisible`).
- **identifying-fields-not-reference-shaped**: A manifest string that is not
  itself written in `%key%` form MUST NOT be substituted even when the
  merged table happens to hold an entry whose key equals that string's
  literal text (the whole-string test rejects it before any lookup;
  `theIdentifyingFieldsAreUntouched`).

## Appearance

Not applicable — this is a manifest localization resolver, not a visual
component.

## States

Not applicable — this is a manifest localization resolver, not a visual
component.

## Accessibility

Not applicable — this is a manifest localization resolver, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-manifest-localization-001 | placeholder-substitution, substitution-walks-full-tree | Manifest with `%extension.title%`/`%extension.blurb%`/`%command.run%`/`%configuration.title%`/`%configuration.mode%`; `package.nls.json` supplying all five | Every one resolves, including the property description five levels down (`theDefaultTableSuppliesTheStrings`) |
| extension-manifest-localization-002 | identifying-fields-not-reference-shaped | `package.nls.json` with keys `"widget"` and `"1.0.0"` matching the manifest's literal `name`/`version` text | `name == "widget"`, `version == "1.0.0"` — neither is replaced by the table's `"NOT THE NAME"`/`"NOT THE VERSION"` (`theIdentifyingFieldsAreUntouched`) |
| extension-manifest-localization-003 | table-search-order, more-specific-table-wins | `package.nls.json` and `package.nls.de.json`, locale `de_DE` | `displayName` resolves from the `de` table, not the default (`theReadersLanguageWins`) |
| extension-manifest-localization-004 | table-search-order, more-specific-table-wins | `package.nls.json`, `package.nls.pt.json`, `package.nls.pt-BR.json`, locale `pt_BR` | `displayName` resolves from the region table, not the bare-language or default table (`aRegionalTableWins`) |
| extension-manifest-localization-005 | default-table-not-overwritten | `package.nls.json` has both keys, `package.nls.de.json` has only one, locale `de_DE` | The key the `de` table lacks still resolves from the default table (`theDefaultTableFillsTheGapsInATranslation`) |
| extension-manifest-localization-006 | missing-table-file-contributes-nothing | Only `package.nls.json` present, locale `ja_JP` | `displayName` resolves from the default table; no failure from the absent `package.nls.ja.json` (`anUntranslatedLanguageFallsBack`) |
| extension-manifest-localization-007 | table-entry-two-value-shapes | `package.nls.json` with one entry as a bare string and one as `{ "message": ..., "comment": [...] }` | Both resolve to their `message` text (`theMessageAndCommentShapeIsUnderstood`) |
| extension-manifest-localization-008 | unchanged-when-no-table | No `package.nls*.json` file in `directory` at all | Returned `Data` is `==` the input `Data`, byte for byte (`noTableMeansNoChange`) |
| extension-manifest-localization-009 | unresolved-placeholder-left-visible | `package.nls.json` lacks `extension.title`; manifest has `displayName: "%extension.title%"` | `displayName == "%extension.title%"` unchanged (`anUnknownKeyIsLeftVisible`) |
| extension-manifest-localization-010 | placeholder-must-be-whole-string | `description: "Uses 50% of one core, at most"` | `description` unchanged — no substring lookup of `"of one core, at most" ... "Uses 50"` (`proseIsNotAPlaceholder`) |
| extension-manifest-localization-011 | malformed-table-contributes-nothing, no-throw-contract | `package.nls.json` contains `{ this is not json` | `localize` does not throw; manifest still decodes with placeholders left visible (`anUnreadableTableIsNotFatal`) |
| extension-manifest-localization-012 | non-string-values-pass-through, object-keys-never-substituted | Configuration properties with `number`/`boolean`/`array` defaults alongside a `%configuration.mode%` description | Non-string defaults survive with their own type and value intact; only the string description resolves (`nonStringValuesSurvive`) |
| extension-manifest-localization-013 | table-filename-case-insensitive | Table file on disk named `Package.NLS.JSON` (mixed case) with `{"extension.title": "Widget"}`, locale `en_US` | `displayName == "Widget"` — matched despite the case mismatch against the expected `package.nls.json` (derived from `fileNames(in:)`/`table(in:for:)`; no dedicated test in the given suite) |
| extension-manifest-localization-014 | unchanged-when-unparseable-input | `json` is the bytes `{ this is not json`, with a valid `package.nls.json` present in `directory` | Returned `Data` equals the input bytes unchanged, since `JSONCPreprocessor.jsonObject(from: json)` throws for the manifest itself (derived from the source; no dedicated test in the given suite) |
| extension-manifest-localization-015 | unchanged-when-unserializable-output | `json` is the bare top-level JSON string `"%name%"` (not an object or array), with a table resolving `name` | Returned `Data` equals the input bytes unchanged, because `JSONSerialization.data(withJSONObject:)` requires a top-level `Array`/`Dictionary` and throws for a bare `String` (derived from the source and Foundation's documented `JSONSerialization` contract; no dedicated test in the given suite) |
| extension-manifest-localization-016 | language-code-absent-limits-search | `Locale(identifier: "")`, whose `language.languageCode` is `nil` | `tableNames(for:)` returns only `["package.nls.json"]` (derived from the source; no dedicated test in the given suite) |
| extension-manifest-localization-017 | unreadable-directory-yields-no-tables | `directory` argument names a path that does not exist on disk | `fileNames(in:)` returns `[:]`; `localize` returns `json` unchanged, identically to the no-table case (derived from the source; no dedicated test in the given suite) |
| extension-manifest-localization-018 | placeholder-key-rejects-embedded-percent | Manifest string `"%a%b%"` with a table entry for key `"a%b"` | String returned unchanged — the extracted key `"a%b"` itself contains `%`, so no lookup is attempted (derived from the source; no dedicated test in the given suite) |
| extension-manifest-localization-019 | table-supports-jsonc | `package.nls.json` written with a `//` line comment and a trailing comma after its last entry | Entries parse identically to strict JSON, via `entries(inTableAt:)`'s `JSONCPreprocessor.jsonObject(from:)` call (derived from the source; no dedicated test in the given suite) |
| extension-manifest-localization-020 | object-keys-never-substituted | Manifest object literally keyed `"%mode%"` (a JSON key, not a value), with a table entry for key `"mode"` | The key text `"%mode%"` is unchanged in the output — `substituting` maps only a `[String: Any]`'s values, never its keys (derived from the source; no dedicated test in the given suite) |

## Edge Cases

- **Null/empty input**: `json` as empty `Data` MUST be returned unchanged —
  `JSONCPreprocessor.jsonObject(from:)` throws for empty bytes, which the
  `try?` in `localize` catches. A `package.nls.json` whose content
  is the valid, empty object `{}` MUST leave the merged table empty and
  MUST NOT change `localize`'s no-table behavior. MUST.
- **Boundary values**: A string of exactly `"%%"` (`count == 2`) MUST NOT be
  treated as a placeholder — the `string.count > 2` guard rejects it. A string of exactly `"%x%"` (`count == 3`, the shortest possible
  placeholder) MUST be treated as one. A key containing any `%` character,
  at any position, MUST be rejected before lookup. MUST.
- **Concurrent access**: `ExtensionManifestLocalization` is a caseless enum
  with no stored state; every function is a `static` function of its
  arguments and touches only local values and freshly-read files, never a
  shared cache. `ExtensionRegistry.read` and `VSIXInstaller.readManifest`
  both call `localize` from `nonisolated` contexts (`ExtensionRegistry.swift`'s `private nonisolated static func read`), and concurrent,
  independent calls with independent `directory` arguments MUST NOT require
  external synchronization. Two concurrent calls that both name the *same*
  `directory` while one of its table files is being modified on disk are not
  independent, and the file system's own read consistency, not this file,
  decides what either call sees. MUST.
- **Error states**: A `directory` that does not exist, cannot be listed, or
  holds a `package.nls*.json` file that cannot be read or does not parse as
  JSON/JSONC MUST NOT fail `localize` — every such failure resolves to that
  file (or the whole table) contributing no entries, per
  **unreadable-directory-yields-no-tables**,
  **unreadable-table-file-contributes-nothing**, and
  **malformed-table-contributes-nothing**. None of these failures is
  surfaced anywhere — not as a thrown error, a return value, or a log line
  (see Logging) — which is a deliberate design choice, not an omission (see
  Design Decisions). MUST.
- **Offline/disconnected state**: Not applicable — this file performs no
  network access of any kind; `localize`, `table`, `entries`, and
  `fileNames` operate only on `FileManager`/`Data(contentsOf:)` calls
  against the local file system named by `directory`.
- **Cancellation and timeouts**: Not applicable — `localize` is a
  synchronous, non-`async` function with no `Task`, no cooperative
  cancellation check, and no timeout of any kind anywhere in this file; it
  always runs to completion once called.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `json` | `Data` | none — required | The bytes of a `package.json`, strict or JSONC, to localize. |
| `directory` | `URL` | none — required | The directory `json` was read from; also where `package.nls*.json` tables are looked for. |
| `locale` | `Locale` | `Locale.current` | Whose language, and region, to prefer when merging tables. |

No environment variable, settings key, or injected dependency exists
anywhere in this file. `ExtensionRegistry.read` and
`VSIXInstaller.readManifest` both call `localize` with only `json` and
`directory` supplied, relying on the `locale` default rather than passing
one explicitly (`ExtensionRegistry.swift`; `VSIXInstaller.swift`).

## Deep Linking

Not applicable: this file defines no URL scheme, universal link, or intent
handling of any kind — it reads local files and rewrites in-memory JSON.

## Localization

This component *is* the localization mechanism, not a consumer of one — it
has no fixed strings of its own to enumerate in a key/default/context table.
Instead, it implements the lookup an extension's own `%key%` placeholders
resolve through:

| Table filename | Applies when | Precedence |
|----------------|--------------|------------|
| `package.nls.json` | Always searched | Least specific — the fallback for any key a more specific table lacks |
| `package.nls.<language>.json` | `locale.language.languageCode` resolves | Overrides the default table for keys it also defines |
| `package.nls.<language>-<region>.json` | `locale.region` also resolves | Most specific — overrides both tables above for keys it also defines |

Matching against the filenames on disk is case-insensitive. Each table's entries decode in either of two shapes VS Code's
ecosystem uses today: a bare string, or an object with a `message` string
field and an ignored `comment` array meant for a human translator. A manifest value is a reference only when it is *entirely* one
`%key%` token; a key with no matching entry is left visible on
screen exactly as VS Code leaves it, rather than resolved to an empty string.

## Accessibility Options

Not applicable: this file renders no UI and reads no Reduce Motion, Increase
Contrast, or Differentiate-Without-Color signal — those act on whatever UI a
host later builds from a localized manifest, not on this resolver.

## Feature Flags

Not applicable: no field, function, or comment in
`ExtensionManifestLocalization.swift` reads a feature-flag key — every
leniency and precedence decision in this file is a fixed, compile-time
choice, never a runtime flag.

## Analytics

Not applicable: no file in this component emits a client-side analytics or
telemetry event of any kind.

## Privacy

Not applicable: every value this file reads or rewrites is
extension-authored manifest and translation-table text (placeholder keys and
their translated strings) — no credential, token, or end-user PII is read,
stored, or transmitted by any function in
`ExtensionManifestLocalization.swift`.

## Logging

Not applicable: no `print`, `os_log`, `Logger`, or `NSLog` call appears
anywhere in `ExtensionManifestLocalization.swift`. Unlike `ExtensionManifest`'s
`DecodingFailure` array, no structured record of a missing, unreadable, or
malformed table is produced or returned to the caller either — the failure
is absorbed entirely inside `localize`, with no signal of any kind that a
table existed but could not be used (see Design Decisions and the
`explicit-error-handling` row under Compliance).

## Platform Notes

- **Swift (source)**: This file targets macOS today, via the
  `AgenticToolkitCore` framework target (`project.yml`); nothing in it —
  plain `enum`/`static func` over Foundation's `FileManager`, `Data`,
  `JSONSerialization`, and the sibling `JSONCPreprocessor` helper — depends
  on `AppKit`, `UIKit`, or any other platform framework, so the same source
  would run identically if the target grew an iOS platform tomorrow.
- **Compose/Android (Kotlin)**: `java.io.File.listFiles()` replaces
  `FileManager.default.contentsOfDirectory(atPath:)`; `java.util.Locale` (or
  Android's `LocaleListCompat`) replaces `Locale`; `kotlinx.serialization`'s
  `JsonElement` tree (`JsonPrimitive`/`JsonArray`/`JsonObject`) replaces the
  `Any`-typed tree this file walks, and a recursive `when` over those three
  cases is the equivalent of `substituting(_:using:)`.
- **React/Web/TypeScript**: Node's `fs.readdirSync`/`fs.readFileSync`
  replace the `FileManager` calls; `Intl.Locale` (or a plain BCP-47 string)
  replaces `Locale`; `JSON.parse` plus a recursive walk that branches on
  `typeof value` (`"string"` versus `Array.isArray(value)` versus a plain
  object) replaces `substituting`, and `value.startsWith("%") &&
  value.endsWith("%") && value.length > 2` is the direct equivalent of the
  whole-string placeholder test.
- **WinUI 3 (C#)**: `System.IO.Directory.GetFiles`/`File.ReadAllBytes`
  replace the `FileManager` calls; `System.Globalization.CultureInfo`
  replaces `Locale`, with `CultureInfo.TwoLetterISOLanguageName` and
  `CultureInfo.Name`'s region subtag standing in for
  `locale.language.languageCode`/`locale.region`; `System.Text.Json.Nodes.JsonNode`
  (`JsonObject`/`JsonArray`/`JsonValue`) replaces the `Any`-typed tree, and a
  recursive method matching on `JsonNode.GetValueKind()` is the equivalent of
  `substituting(_:using:)`, writing back through `JsonNode.ToJsonString()` in
  place of `JSONSerialization.data(withJSONObject:)`. One genuine platform
  difference: NTFS resolves filenames case-insensitively by default, so the
  explicit lower-casing this file does in `fileNames(in:)` to
  match `package.nls.pt-BR.json` against a request for `package.nls.pt-br.json`
  is redundant on Windows — `File.Exists`/`Directory.GetFiles` already treat
  the two names as the same file, and a WinUI 3 port can rely on that instead
  of building its own case-folded lookup table.

## Design Decisions

**Decision**: `localize` never throws, and every failure mode — a missing
`directory`, an unreadable or malformed table file, an unserializable
rewritten tree — degrades to "this manifest keeps its placeholders" rather
than to an error the caller must handle.
**Rationale**: The source's own doc comment states the reasoning directly:
refusing the manifest over a table's typo would turn "a typo in a file
nobody executes into an extension that has vanished," and an unresolved
`%key%` visible on screen is itself the diagnostic signal — it says the
extension's own table is incomplete, where a blank field would say nothing
at all.
**Approved**: pending

**Decision**: The default (`package.nls.json`) table's entries stay in the
merged result even when a more specific table for the same locale is also
present; only overlapping keys are overridden.
**Rationale**: A translation is nearly always less complete than the
English it was made from. Replacing the default table outright, rather than
merging under it, would turn every key the translation omits back into a
visible placeholder — "worse than not translating at all".
**Approved**: pending

**Decision**: When the merged table is empty, `localize` returns the input
`Data` unchanged rather than parsing and re-serializing it.
**Rationale**: Most extensions ship no translations at all, and the source's
doc comment states they "should not pay for a round-trip — nor risk one": a re-serialized document is not byte-identical to what came
in (key order and number formatting can change), so skipping the round-trip
entirely is also what keeps an untranslated manifest's bytes exactly as its
author wrote them.
**Approved**: pending

**Decision**: `substituting` maps only a JSON object's values, never its
keys.
**Rationale**: A key is a name the host matches on elsewhere — a command
id, a setting id, a language id. Substituting a key that happened to look
like a placeholder would make that name resolve to a word nothing else in
the host uses, silently breaking the match.
**Approved**: pending

**Decision**: Table filenames are matched against the names on disk without
regard to case.
**Rationale**: Real extensions on the registry are inconsistent about
casing — `package.nls.pt-BR.json` and `package.nls.zh-CN.json` both ship
with exactly that capitalization — and a locale-derived name is not a
promise about the file's actual case either, so an exact-case match would
silently miss real tables.
**Approved**: pending

**Decision**: A string is a placeholder reference only when its *entire*
content is one `%key%` token; a percent sign anywhere else in a string never
triggers a lookup.
**Rationale**: The source's own doc comment gives the counter-example this
guards against — "Uses 50% of one core" is prose, not a lookup of `of one
core, at most" … "Uses 50`, and this is the same rule VS Code itself applies.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | failed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |

`explicit-error-handling` is **failed**: every failure this file can
encounter — an unreadable directory, an unreadable table file, malformed
JSON/JSONC, an unserializable rewritten tree — is caught with `try?` and
discarded with no signal of any kind, not a thrown error, not a return
value, and not a `DecodingFailure`-style record the way `ExtensionManifest`
produces for its own decode failures (see Logging and Design Decisions).
`fault-tolerance` **passed**: `localize` never throws and every one of its
internal helpers has a defined, total fallback for every failure mode.
`data-integrity` is **partial**: when a table is present, the manifest is
rewritten by parsing and re-serializing through `JSONSerialization`, which
is not a byte-identical round trip — key order and number formatting can
change — though this is only exercised when at least one placeholder needs
resolving (**unchanged-when-no-table** avoids it entirely otherwise).
`idempotent-operations` **passed**: `localize` is a pure function of its
three arguments and the current contents of `directory`; two calls with
unchanged inputs produce identical output. `separation-of-concerns`
**passed**: this file's sole responsibility is placeholder resolution,
sitting beside the manifest it serves and shared by both of its readers
rather than duplicated in each. `unit-test-coverage`
**passed**: `ExtensionManifestLocalizationTests.swift` exercises the default
table, language and region preference, gap fill-in from the default table,
fallback to the default for an untranslated locale, both table-entry
shapes, the byte-identical no-op path, an unresolved key staying visible, a
non-placeholder string containing `%` being left alone, an unreadable table
not sinking the manifest, and non-string values surviving the rewrite.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
