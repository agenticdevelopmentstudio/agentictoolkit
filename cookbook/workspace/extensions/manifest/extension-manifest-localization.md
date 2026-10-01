---
id: 24e1710c-a805-4f6e-b720-fbd869472ca9
title: Extension Manifest Localization
domain: agentictoolkit://cookbook/workspace/extensions/manifest/extension-manifest-localization
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Resolves %key% placeholders in a VS Code package.json against package.nls*.json
  tables beside it; a missing or malformed table never fails the resolve, and leaves
  unresolved keys visible.
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
- agentictoolkit://cookbook/workspace/extensions/manifest/extension-manifest
references:
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionManifestLocalization.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/ExtensionManifestLocalizationTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Extension Manifest Localization

## Overview

This component resolves the `%key%` placeholders a VS Code `package.json`
uses in place of the strings a person reads. An extension that ships
translations does not put English in `package.json` at all — it writes
`"displayName": "%name%"` and puts the English in `package.nls.json` beside
it, the German in `package.nls.de.json`, and so on. The localization
function is the single entry point both of the manifest's readers call
before decoding — the component that reads an installed extension's
manifest, and the component that reads a manifest it is about to install —
so translation resolution happens exactly once, at the one place the bytes
become a decoded manifest, rather than at each place a manifest string is
later displayed. A missing, unreadable, or malformed table never fails the
resolve: it costs the extension its translations and nothing else.

## Behavioral Requirements

- **placeholder-substitution**: the localization function MUST return the
  manifest bytes with every `%key%` placeholder that the merged
  localization table for the manifest's directory/locale can answer
  replaced by the string that key stands for.
- **no-throw-contract**: the localization function MUST NOT be able to
  fail outright, and MUST return a value for every input; a missing,
  unreadable, or malformed localization table MUST cost the manifest its
  translations and nothing else, and MUST NOT propagate an error to its
  caller.
- **unchanged-when-no-table**: the localization function MUST return the
  manifest bytes unchanged, byte for byte, without parsing or
  re-serializing them, when the merged table for the directory/locale is
  empty.
- **unchanged-when-unparseable-input**: the localization function MUST
  return the manifest bytes unchanged when the manifest's own bytes cannot
  be parsed as JSON/JSONC.
- **unchanged-when-unserializable-output**: the localization function MUST
  return the manifest bytes unchanged when the substituted tree cannot be
  re-serialized to JSON.
- **default-locale-is-current**: the localization function's locale
  parameter MUST default to the reader's current locale when the caller
  supplies none.
- **table-search-order**: The table filenames searched for a given
  locale, least specific first, MUST be `package.nls.json`, then
  `package.nls.<language>.json` when the locale has a language code, then
  `package.nls.<language>-<region>.json` when the locale additionally has a
  region.
- **language-code-absent-limits-search**: the table-name lookup MUST
  return only `["package.nls.json"]` when the locale has no resolvable
  language code.
- **default-table-not-overwritten**: A key present only in the default
  (`package.nls.json`) table MUST remain available in the merged table even
  when a more specific table for the same locale is also present.
- **more-specific-table-wins**: For a key present in more than one table
  that applies to the locale, the value from the most specific table
  (region-and-language over bare-language over default) MUST be the one
  the merged table returns.
- **table-filename-case-insensitive**: A table file on disk MUST be
  matched against its expected name without regard to case.
- **missing-table-file-contributes-nothing**: A table filename with no
  case-insensitively matching entry in the directory's contents MUST be
  skipped, contributing no entries and not failing the merge.
- **unreadable-directory-yields-no-tables**: the directory-listing step
  MUST yield no tables at all when it cannot list the directory's
  contents, so a nonexistent or unreadable directory MUST be treated
  identically to one with no localization tables at all.
- **unreadable-table-file-contributes-nothing**: reading one table's
  entries MUST yield none when the table's bytes cannot be read from its
  location.
- **malformed-table-contributes-nothing**: reading one table's entries
  MUST yield none when the table's contents cannot be parsed as
  JSON/JSONC, or when the parsed value is not a string-keyed object.
- **table-supports-jsonc**: A table file MUST be parsed with JSONC
  tolerance, so a table written with `//` comments or a trailing comma
  MUST be read the same as strict JSON.
- **table-entry-two-value-shapes**: A table entry MUST resolve to a string
  when its JSON value is either a bare string or an object with a
  `message` string field, and MUST be dropped from the table for any other
  JSON shape.
- **substitution-walks-full-tree**: Substitution MUST be applied to every
  string value at every depth of the parsed manifest tree, including
  inside arrays and inside objects nested arbitrarily deep — for example, a
  value five levels down at
  `contributes.configuration[].properties.<setting>.description`.
- **object-keys-never-substituted**: Substitution MUST be applied only to
  a JSON object's values, never to its keys, regardless of whether a key's
  text would otherwise match the placeholder pattern.
- **non-string-values-pass-through**: A JSON value that is not a string —
  `null`, a boolean, a number, an array, or an object — MUST be returned
  from substitution with its own kind unchanged, with substitution applied
  only to any string values nested inside it.
- **placeholder-must-be-whole-string**: A string MUST be treated as a
  placeholder reference only when its entire content, not a prefix,
  suffix, or substring, is a single `%…%` token — longer than two
  characters and starting and ending with `%`.
- **placeholder-key-rejects-embedded-percent**: A candidate placeholder
  whose extracted key — the text between the leading and trailing `%` —
  itself contains a `%` character MUST be returned unchanged rather than
  looked up.
- **unresolved-placeholder-left-visible**: A placeholder string whose
  extracted key has no entry in the merged table MUST be returned
  unchanged, leaving the literal `%key%` text visible in the output rather
  than substituting an empty string.
- **identifying-fields-not-reference-shaped**: A manifest string that is
  not itself written in `%key%` form MUST NOT be substituted even when the
  merged table happens to hold an entry whose key equals that string's
  literal text (the whole-string test rejects it before any lookup).

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
| extension-manifest-localization-001 | placeholder-substitution, substitution-walks-full-tree | Manifest with `%extension.title%`/`%extension.blurb%`/`%command.run%`/`%configuration.title%`/`%configuration.mode%`; `package.nls.json` supplying all five | Every one resolves, including the property description five levels down |
| extension-manifest-localization-002 | identifying-fields-not-reference-shaped | `package.nls.json` with keys `"widget"` and `"1.0.0"` matching the manifest's literal `name`/`version` text | `name == "widget"`, `version == "1.0.0"` — neither is replaced by the table's `"NOT THE NAME"`/`"NOT THE VERSION"` |
| extension-manifest-localization-003 | table-search-order, more-specific-table-wins | `package.nls.json` and `package.nls.de.json`, locale `de_DE` | `displayName` resolves from the `de` table, not the default |
| extension-manifest-localization-004 | table-search-order, more-specific-table-wins | `package.nls.json`, `package.nls.pt.json`, `package.nls.pt-BR.json`, locale `pt_BR` | `displayName` resolves from the region table, not the bare-language or default table |
| extension-manifest-localization-005 | default-table-not-overwritten | `package.nls.json` has both keys, `package.nls.de.json` has only one, locale `de_DE` | The key the `de` table lacks still resolves from the default table |
| extension-manifest-localization-006 | missing-table-file-contributes-nothing | Only `package.nls.json` present, locale `ja_JP` | `displayName` resolves from the default table; no failure from the absent `package.nls.ja.json` |
| extension-manifest-localization-007 | table-entry-two-value-shapes | `package.nls.json` with one entry as a bare string and one as `{ "message": ..., "comment": [...] }` | Both resolve to their `message` text |
| extension-manifest-localization-008 | unchanged-when-no-table | No `package.nls*.json` file in the directory at all | Returned bytes equal the input bytes, byte for byte |
| extension-manifest-localization-009 | unresolved-placeholder-left-visible | `package.nls.json` lacks `extension.title`; manifest has `displayName: "%extension.title%"` | `displayName == "%extension.title%"` unchanged |
| extension-manifest-localization-010 | placeholder-must-be-whole-string | `description: "Uses 50% of one core, at most"` | `description` unchanged — no substring lookup of `"of one core, at most" ... "Uses 50"` |
| extension-manifest-localization-011 | malformed-table-contributes-nothing, no-throw-contract | `package.nls.json` contains `{ this is not json` | The localization function does not fail; manifest still decodes with placeholders left visible |
| extension-manifest-localization-012 | non-string-values-pass-through, object-keys-never-substituted | Configuration properties with `number`/`boolean`/`array` defaults alongside a `%configuration.mode%` description | Non-string defaults survive with their own type and value intact; only the string description resolves |
| extension-manifest-localization-013 | table-filename-case-insensitive | Table file on disk named `Package.NLS.JSON` (mixed case) with `{"extension.title": "Widget"}`, locale `en_US` | `displayName == "Widget"` — matched despite the case mismatch against the expected `package.nls.json` |
| extension-manifest-localization-014 | unchanged-when-unparseable-input | `json` is the bytes `{ this is not json`, with a valid `package.nls.json` present in the directory | Returned bytes equal the input bytes unchanged, since the manifest's own bytes cannot be parsed as JSON/JSONC |
| extension-manifest-localization-015 | unchanged-when-unserializable-output | `json` is the bare top-level JSON string `"%name%"` (not an object or array), with a table resolving `name` | Returned bytes equal the input bytes unchanged, because re-serializing a bare top-level string is not supported by the underlying JSON writer |
| extension-manifest-localization-016 | language-code-absent-limits-search | A locale with no resolvable language code (e.g. the empty identifier) | The table-name lookup returns only `["package.nls.json"]` |
| extension-manifest-localization-017 | unreadable-directory-yields-no-tables | The directory argument names a path that does not exist on disk | The directory-listing step yields no tables; the localization function returns the manifest bytes unchanged, identically to the no-table case |
| extension-manifest-localization-018 | placeholder-key-rejects-embedded-percent | Manifest string `"%a%b%"` with a table entry for key `"a%b"` | String returned unchanged — the extracted key `"a%b"` itself contains `%`, so no lookup is attempted |
| extension-manifest-localization-019 | table-supports-jsonc | `package.nls.json` written with a `//` line comment and a trailing comma after its last entry | Entries parse identically to strict JSON |
| extension-manifest-localization-020 | object-keys-never-substituted | Manifest object literally keyed `"%mode%"` (a JSON key, not a value), with a table entry for key `"mode"` | The key text `"%mode%"` is unchanged in the output — substitution is applied only to an object's values, never its keys |

## Edge Cases

- **Null/empty input**: the manifest bytes as an empty input MUST be
  returned unchanged — an empty input cannot be parsed as JSON/JSONC, and
  that failure resolves to "leave unchanged" the same way any other
  unparseable input does. A `package.nls.json` whose content is the valid,
  empty object `{}` MUST leave the merged table empty and MUST NOT change
  the localization function's no-table behavior.
- **Boundary values**: A string of exactly two percent signs (`"%%"`) MUST
  NOT be treated as a placeholder — it is too short. A string of exactly
  three characters (`"%x%"`, the shortest possible placeholder) MUST be
  treated as one. A key containing any `%` character, at any position,
  MUST be rejected before lookup.
- **Concurrent access**: This component holds no stored state; every
  function is a pure function of its arguments and touches only local
  values and freshly-read files, never a shared cache. Both of the
  manifest's readers call the localization function from contexts with no
  isolation requirement of their own, and concurrent, independent calls
  with independent directory arguments MUST NOT require external
  synchronization. Two concurrent calls that both name the same directory
  while one of its table files is being modified on disk are not
  independent, and the file system's own read consistency, not this
  component, decides what either call sees.
- **Error states**: A directory that does not exist, cannot be listed, or
  holds a `package.nls*.json` file that cannot be read or does not parse as
  JSON/JSONC MUST NOT fail the localization function; every such failure
  resolves to that file (or the whole table) contributing no entries, per
  **unreadable-directory-yields-no-tables**,
  **unreadable-table-file-contributes-nothing**, and
  **malformed-table-contributes-nothing**. None of these failures is
  surfaced anywhere — not as a thrown error, a return value, or a log line
  (see Logging) — which is a deliberate design choice, not an omission (see
  Design Decisions).
- **Offline/disconnected state**: Not applicable — this component performs
  no network access of any kind; every step operates only on local
  file-system reads against the directory it is given.
- **Cancellation and timeouts**: Not applicable — the localization
  function is a synchronous operation with no cooperative cancellation
  check and no timeout of any kind anywhere in this component; it always
  runs to completion once called.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `json` | manifest bytes | none — required | The bytes of a `package.json`, strict or JSONC, to localize. |
| `directory` | a file-system location | none — required | The directory `json` was read from; also where `package.nls*.json` tables are looked for. |
| `locale` | a locale | the reader's current locale | Whose language, and region, to prefer when merging tables. |

No environment variable, settings key, or injected dependency exists
anywhere in this component. Both of the manifest's readers call the
localization function with only the manifest bytes and directory supplied,
relying on the locale default rather than passing one explicitly.

## Deep Linking

Not applicable: this component defines no URL scheme, universal link, or
intent handling of any kind — it reads local files and rewrites in-memory
JSON.

## Localization

This component *is* the localization mechanism, not a consumer of one — it
has no fixed strings of its own to enumerate in a key/default/context table.
Instead, it implements the lookup an extension's own `%key%` placeholders
resolve through:

| Table filename | Applies when | Precedence |
|----------------|--------------|------------|
| `package.nls.json` | Always searched | Least specific — the fallback for any key a more specific table lacks |
| `package.nls.<language>.json` | The locale's language code resolves | Overrides the default table for keys it also defines |
| `package.nls.<language>-<region>.json` | The locale's region also resolves | Most specific — overrides both tables above for keys it also defines |

Matching against the filenames on disk is case-insensitive. Each table's
entries decode in either of two shapes VS Code's ecosystem uses today: a
bare string, or an object with a `message` string field and an ignored
`comment` array meant for a human translator. A manifest value is a
reference only when it is *entirely* one `%key%` token; a key with no
matching entry is left visible on screen exactly as VS Code leaves it,
rather than resolved to an empty string.

## Accessibility Options

Not applicable: this component renders no UI and reads no Reduce Motion,
Increase Contrast, or Differentiate-Without-Color signal — those act on
whatever UI a host later builds from a localized manifest, not on this
resolver.

## Feature Flags

Not applicable: no field, function, or comment in this component reads a
feature-flag key — every leniency and precedence decision in this
component is a fixed, compile-time choice, never a runtime flag.

## Analytics

Not applicable: no part of this component emits a client-side analytics or
telemetry event of any kind.

## Privacy

Not applicable: every value this component reads or rewrites is
extension-authored manifest and translation-table text (placeholder keys
and their translated strings) — no credential, token, or end-user PII is
read, stored, or transmitted by any part of this component.

## Logging

Not applicable: no logging call of any kind appears anywhere in this
component. Unlike the manifest's own typed decoding-failure records, no
structured record of a missing, unreadable, or malformed table is produced
or returned to the caller either — the failure is absorbed entirely inside
the localization function, with no signal of any kind that a table existed
but could not be used (see Design Decisions and the
`explicit-error-handling` row under Compliance).

## Platform Notes

- **Swift (source)**: This component targets macOS today, via the
  `AgenticToolkitCore` framework target (`project.yml`); nothing in it — a
  caseless `enum` of `static func`s over Foundation's `FileManager`,
  `Data`, `JSONSerialization`, and the sibling `JSONCPreprocessor` helper —
  depends on `AppKit`, `UIKit`, or any other platform framework, so the
  same source would run identically if the target grew an iOS platform
  tomorrow. The localization function does not declare `throws`; every
  internal step that can fail (`JSONCPreprocessor.jsonObject(from:)` for
  the manifest or a table, `JSONSerialization.data(withJSONObject:)` for
  the rewritten tree, `FileManager.default.contentsOfDirectory(atPath:)`
  for the directory listing, `Data(contentsOf:)` for one table's bytes) is
  wrapped in `try?` at its call site, converting a thrown error into the
  appropriate empty/unchanged result inline rather than propagating it.
  `JSONSerialization.data(withJSONObject:)` requires a top-level `Array` or
  `Dictionary` and throws for a bare `String`, which is why a manifest
  whose top-level JSON value is a bare string cannot round-trip through the
  substitution path. Both of the manifest's readers (`ExtensionRegistry.read`,
  `VSIXInstaller.readManifest`) call the localization function from
  `nonisolated` contexts, consistent with this component holding no actor
  or `@MainActor` isolation of its own.
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/ExtensionManifestLocalization.swift` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/manifest/. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
