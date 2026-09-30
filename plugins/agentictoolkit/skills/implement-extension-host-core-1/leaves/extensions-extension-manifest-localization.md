<!-- leaf: implement-extension-host-core-1/extensions-extension-manifest-localization · source: extension-host-core-extensions-extension-manifest-localization.md -->

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-manifest-localization#<slug>`):

- `placeholder-substitution` MUST
- `no-throw-contract` MUST
- `unchanged-when-no-table` MUST
- `unchanged-when-unparseable-input` MUST
- `unchanged-when-unserializable-output` MUST
- `default-locale-is-current` MUST
- `table-search-order` MUST
- `language-code-absent-limits-search` MUST
- `default-table-not-overwritten` MUST
- `more-specific-table-wins` MUST
- `table-filename-case-insensitive` MUST
- `missing-table-file-contributes-nothing` MUST
- `unreadable-directory-yields-no-tables` MUST
- `unreadable-table-file-contributes-nothing` MUST
- `malformed-table-contributes-nothing` MUST
- `table-supports-jsonc` MUST
- `table-entry-two-value-shapes` MUST
- `substitution-walks-full-tree` MUST
- `object-keys-never-substituted` MUST
- `non-string-values-pass-through` MUST
- `placeholder-must-be-whole-string` MUST
- `placeholder-key-rejects-embedded-percent` MUST
- `unresolved-placeholder-left-visible` MUST
- `identifying-fields-not-reference-shaped` MUST

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

