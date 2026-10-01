---
id: 0e35ddf2-3e87-4a5a-9fd9-24bafc7325b6
title: Theme Engine
domain: agentictoolkit://cookbook/ui/theme/theme-engine
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'This toolkit''s own layer of the theme engine: VS Code theme import,
  per-role syntax-style overrides that travel with a theme, and settings-backed
  theme storage.'
platforms:
- swift
- macos
tags:
- theming
- color
- persistence
- import
- logic
depends-on:
- agenticdevelopertoolkit://recipes/theme-engine
- agentictoolkit://cookbook/foundation/settings-storage
- agentictoolkit://cookbook/foundation/formats/jsonc-preprocessor
- agentictoolkit://cookbook/workspace/extensions/manifest/extension-resource-path
related:
- agentictoolkit://cookbook/ui/settings/rows/theme-picker-view
- agentictoolkit://cookbook/ui/settings/rows/theme-preview-view
references:
- https://code.visualstudio.com/api/extension-guides/color-theme
approved-by: ''
approved-date: ''
---

# Theme Engine

## Overview

This recipe covers this toolkit's own half of the theme engine, layered on
top of a shared model — a theme, its color roles, and the semantic palette
that derives colors from it — specified separately by
[Theme Engine (shared model)](agenticdevelopertoolkit://recipes/theme-engine).
This layer adds four things on top of that model, each in its own concern:

- a syntax-role vocabulary (the ten syntax attributes a source editor
  paints), a syntax style (color + bold + italic), and the
  `syntax.<role>[.bold][.italic]` key grammar that stores those styles
  inside a theme's free-form override map;
- an importer that parses a VS Code color-theme JSON(C) file into a theme:
  palette, appearance, six semantic role overrides, syntax styles derived
  from `tokenColors` rules, and `include`-chain resolution with a
  containment root and a depth bound. It also adds an operation that stores
  the imported result as a locked, already-imported theme;
- a storage backing that persists custom themes and the active theme id
  through this app's settings storage under the historical keys, plus a
  no-argument convenience construction for the theme store;
- on desktop platforms, the wiring from that storage to the platform's own
  appearance/dark-mode signal, also available as a no-argument convenience
  construction for the theme manager.

Use it when a host needs VS Code themes, per-role syntax colors that travel
with a theme, or a theme catalog persisted in the app's settings storage. It
has no visual surface of its own.

## Behavioral Requirements

### Syntax roles and styles

- **syntax-role-vocabulary**: The syntax-role vocabulary MUST have exactly ten roles, named `keywords`, `commands`, `types`, `attributes`, `variables`, `values`, `numbers`, `strings`, `characters` and `comments`, in that declaration order.
- **syntax-role-names**: Each syntax role's name MUST equal the name of the corresponding syntax field of the editor's own theme model verbatim, so a consumer maps a role across without a translation table.
- **syntax-style-shape**: A syntax style MUST carry exactly a color, a bold flag and an italic flag; it MUST NOT carry underline or strikethrough.
- **syntax-style-defaults**: Constructing a syntax style from a color alone MUST default its bold and italic flags to `false`.
- **syntax-value-semantics**: A syntax role and a syntax style MUST be safe to pass across concurrency boundaries and compare for equality.

### The roleOverrides key grammar

- **override-key-spelling**: Computing the override key for a role and a bold/italic combination MUST return `syntax.` + the role's name, then `.bold` when bold is requested, then `.italic` when italic is requested — so the only four shapes written are `syntax.<role>`, `syntax.<role>.bold`, `syntax.<role>.italic` and `syntax.<role>.bold.italic`.
- **override-key-flag-order**: When reading, the grammar MUST treat the trailing segments as a set, so `syntax.comments.italic.bold` MUST parse identically to `syntax.comments.bold.italic`.
- **override-key-prefix**: A key MUST be recognised as a syntax key only when splitting it on `.` (keeping empty segments) yields at least two segments and the first segment is exactly `syntax`.
- **override-key-role**: A key whose second segment is not exactly a syntax role's name (case-sensitive) MUST NOT be recognised as a syntax key.
- **override-key-flag-vocabulary**: A key with any trailing segment other than `bold` or `italic` — including an empty segment — MUST NOT be recognised as a syntax key.
- **override-key-flag-once**: A key that states `bold` twice or `italic` twice MUST NOT be recognised as a syntax key.
- **override-key-no-throw**: An unrecognised key MUST be ignored — never treated as an error — and MUST NOT prevent a well-formed syntax key in the same map from being read.
- **override-key-collision-free**: The `syntax` namespace MUST NOT collide with the theme's semantic-role keys; the source relies on those role names being identifiers that cannot contain a dot.

### Reading and writing syntax styles

- **syntax-styles-read**: Reading a theme's syntax styles MUST return one style per role that has at least one recognised key in its override map, with the key's color and the bold/italic flags the key names.
- **syntax-styles-empty**: Reading a theme's syntax styles MUST return an empty map for a theme with no recognised syntax key.
- **syntax-styles-tiebreak**: When more than one recognised key names the same role, reading syntax styles MUST resolve to the lexicographically greatest key (so `syntax.keywords.italic` beats `syntax.keywords.bold`, which beats `syntax.keywords`), independent of map iteration or insertion order.
- **syntax-styles-invisible-to-roles**: Syntax keys MUST NOT cause the semantic palette to report any semantic role as declared, because the palette looks roles up strictly by role name.
- **syntax-styles-travel**: Syntax keys MUST survive a theme serialize/deserialize round trip unchanged, because they live in the theme's override map, which the theme's own encoding covers; this is what carries them through exporting a theme and duplicating a theme.
- **with-syntax-styles-replace**: Replacing a theme's syntax styles MUST remove every key the grammar recognises as a syntax key before writing the new styles, so the result carries exactly the given styles and no stale shape survives.
- **with-syntax-styles-preserve**: Replacing syntax styles MUST leave every other override-map entry unchanged, including a `syntax.`-prefixed key the grammar rejects (for example `syntax.keywords.underline`).
- **with-syntax-styles-write**: Replacing syntax styles MUST write each style under its computed override key, with the style's color as the value.
- **with-syntax-styles-clear**: Replacing syntax styles with an empty set MUST remove every recognised syntax key and nothing else.
- **with-syntax-styles-copy**: Replacing syntax styles MUST return a modified copy and MUST NOT mutate the original theme.
- **syntax-grammar-shared**: Reading syntax styles and replacing them MUST use the same parser, so the set of keys one reads is exactly the set the other replaces.

### VS Code import: entry points

- **import-bytes-entry**: Parsing from raw bytes MUST produce a theme or fail with an error.
- **import-jsonc**: Both parsing entry points MUST accept JSONC — `//` and block comments and trailing commas — and MUST produce the same theme a strict-JSON spelling of the same document produces.
- **import-encodings**: Both parsing entry points MUST accept UTF-8, UTF-8 with a byte-order mark, and UTF-16 payloads (including UTF-16 JSONC), producing the same theme as the UTF-8 spelling, decoded through the shared JSONC preprocessor (see [JSONC Preprocessor](agentictoolkit://cookbook/foundation/formats/jsonc-preprocessor)).
- **import-bytes-ignores-include**: Parsing from raw bytes MUST NOT resolve an `include` key and MUST NOT reject a document for carrying one; the result MUST equal the result for the same document without the key.
- **import-file-entry**: Parsing from a file location MUST read the file, resolve its `include` chain, and parse the merged document.
- **import-file-default-root**: When no containment root is given, the containment root MUST be the theme file's own directory.
- **import-file-url-precondition**: The top-level file location is a caller precondition: the importer MUST NOT containment-check it — only `include` targets are checked. The shipping caller resolves the manifest's declared path against the extension's resource-path rules before calling (see [Extension Resource Path](agentictoolkit://cookbook/workspace/extensions/manifest/extension-resource-path)).
- **import-name-from-label**: The imported theme's name MUST be the given label; the theme file's own `name` and `type` keys MUST be ignored.
- **import-lock-flags**: Parsing MUST return a theme that is neither built-in nor already marked imported, carrying a freshly generated identifier.

### VS Code import: validation and errors

- **import-validation-order**: The importer MUST check, in this order, and fail on the first failure: root is an object; `colors` is an object; `editor.foreground` is present and parses; `editor.background` is present and parses; foreground differs from background; all sixteen ANSI keys are present and parse.
- **import-syntax-error-passthrough**: When no candidate encoding yields a parseable JSON document, the importer MUST propagate the underlying JSON-parsing error for the raw bytes unchanged; it is not wrapped in an import-specific error.
- **import-root-object**: A document whose root is not a JSON object MUST fail with a not-an-object error.
- **import-colors-object**: A document whose `colors` member is absent, `null`, or not an object MUST fail with a missing-colors error.
- **import-foreground-required**: An absent or unparseable `editor.foreground` MUST fail with a missing-color error naming `editor.foreground`.
- **import-background-required**: An absent or unparseable `editor.background` MUST fail with a missing-color error naming `editor.background`.
- **import-foreground-background-distinct**: A theme whose parsed foreground equals its parsed background MUST fail with a foreground-matches-background error.
- **import-ansi-complete**: When any of the sixteen `terminal.ansi*` keys is absent or unparseable, the importer MUST fail with a missing-ANSI-colors error carrying every missing key, in ANSI slot order; it MUST NOT synthesise a missing slot.
- **import-ansi-order**: The sixteen ANSI colours MUST be stored in the slot order `terminal.ansiBlack`, `Red`, `Green`, `Yellow`, `Blue`, `Magenta`, `Cyan`, `White`, then the eight `terminal.ansiBright*` keys in the same colour order.
- **import-file-errors**: A file-read failure for the top-level file or any included file MUST propagate the underlying read error unchanged.
- **import-error-descriptions**: An import error MUST NOT provide a localized description of its own; a caller that requests one gets a generic, non-localized description of the failure case.

### VS Code import: palette mapping

- **import-appearance**: `uiTheme` MUST decide appearance: `vs-dark` and `hc-black` MUST yield dark; `vs` and `hc-light` MUST yield light.
- **import-appearance-fallback**: Any other `uiTheme` value MUST yield dark when the parsed background is dark and light otherwise.
- **import-cursor**: The cursor color MUST be `editorCursor.foreground` when present and parseable, and the foreground otherwise.
- **import-selection-source**: The declared selection MUST be `editor.selectionBackground` when present and parseable, else `editor.inactiveSelectionBackground` when present and parseable.
- **import-selection-opaque**: A declared selection MUST be stored composited over the background, so the stored value is opaque (alpha byte `FF`).
- **import-selection-fallback**: With neither selection key usable, the selection MUST be the background blended 20% toward the foreground.
- **import-role-overrides**: The importer MUST map exactly these six keys to semantic theme role overrides: `sideBar.background` → `surface`, `editorWidget.background` → `elevatedSurface`, `input.background` → `controlBackground`, `descriptionForeground` → `secondaryText`, `input.placeholderForeground` → `placeholderText`, `focusBorder` → `outline`.
- **import-role-overrides-present-only**: A mapped key MUST become an override only when it is present and parses; an absent or unparseable key MUST write nothing.
- **import-no-other-roles**: The importer MUST NOT write an override for any other semantic theme role — in particular not `windowBackground`, `primaryText`, `selection`, `accent`, `danger`, `border` or `warning` — even when a tempting VS Code key (`textLink.foreground`, `errorForeground`, `contrastBorder`, `editorWarning.foreground`) is present.

### VS Code import: colour decoding

- **hex-forms**: A colour string MUST parse, with or without a leading `#`, when it has 3, 4, 6 or 8 hex digits: 3 and 4 digits MUST be expanded by doubling each digit, and a 6-digit value MUST receive an opaque `FF` alpha.
- **hex-invalid-absent**: A colour value that is not a string, or a string of any other length or containing non-hex characters (a named colour, an odd digit count), MUST count as absent — never as an error of its own.
- **hex-shared**: `colors` values and `tokenColors` `foreground` values MUST go through the same normaliser.

### VS Code import: syntax styles from tokenColors

- **token-rules-source**: Syntax rules MUST be read from the root-level `tokenColors` array; a `tokenColors` that is absent or not an array MUST yield no rules.
- **token-rule-usable**: A `tokenColors` entry MUST become rules only when it is an object whose `settings` is an object whose `foreground` is a string that parses as a colour; any other entry — including one with only a `fontStyle` — MUST be skipped without affecting the others.
- **token-scope-forms**: An entry's `scope` MUST be accepted as an array (taking each string element and skipping non-strings) or as a single string split on commas; any other `scope`, including an absent one, MUST yield no rules for that entry.
- **token-selector-clean**: Each selector MUST be trimmed of surrounding whitespace and newlines; an empty selector, or one still containing whitespace (a descendant selector such as `meta.tag entity.name`), MUST be dropped without dropping the entry's other selectors.
- **token-emphasis**: `fontStyle` MUST be split on whitespace; the style MUST be bold when a token equals `bold` and italic when a token equals `italic`; every other token (`underline`, `strikethrough`, `normal`, `regular`, unknown words) MUST be ignored.
- **token-match**: A rule MUST apply to a queried scope when its selector equals the scope or is a dot-separated ancestor of it (the scope begins with selector + `.`).
- **token-specificity**: Among applicable rules the longest selector MUST win regardless of declaration order.
- **token-tiebreak**: Among applicable rules of equal selector length, the one later in document order MUST win.
- **token-scope-chain**: Each role MUST be resolved from this ordered scope chain: `keywords` ← `keyword.control`; `commands` ← `entity.name.function`; `types` ← `entity.name.type`, then `support.type`; `attributes` ← `entity.other.attribute-name`; `variables` ← `variable.other`; `values` ← `constant.language`; `numbers` ← `constant.numeric`; `strings` ← `string.quoted.double`; `characters` ← `constant.character`; `comments` ← `comment.line`.
- **token-chain-first-match**: A later scope in a role's chain MUST be consulted only when no rule applies to any earlier scope; an ancestor-only match on an earlier scope (for example a rule for `entity` matching `entity.name.type`) MUST win over an exact match on a later scope.
- **token-unmatched-role**: A role no rule matches MUST get no syntax style, leaving the consumer's ANSI derivation in charge.
- **token-no-throw**: Nothing in `tokenColors` handling MUST fail with an error; a malformed `tokenColors` yields no styles and the rest of the theme is unchanged.
- **token-stored-as-overrides**: The resolved syntax styles MUST be stored by replacing syntax styles, so they appear as `syntax.*` keys in the override map alongside the six role overrides and change no palette field.

### VS Code import: include chains

- **include-detect**: A document MUST be treated as including another only when its `include` value is a non-empty string; any other value MUST be treated as no include.
- **include-resolve**: An include path MUST be resolved relative to the including file's directory and MUST stay inside the containment root (see [Extension Resource Path](agentictoolkit://cookbook/workspace/extensions/manifest/extension-resource-path)).
- **include-containment**: An include that resolves outside the containment root MUST fail with an escapes-containment-root error.
- **include-depth-bound**: The importer MUST follow at most 8 include hops; a document at depth 8 that still names an include MUST fail with an include-chain-too-deep error (limit 8).
- **include-cycle**: A cycle (`a.json` including `b.json` including `a.json`) MUST be stopped by the depth bound and fail with the same include-chain-too-deep error (limit 8); there is no visited-set.
- **include-merge-colors**: When both files carry a `colors` object, the merged `colors` MUST be the base's keys overlaid key by key with the including file's, the including file winning.
- **include-merge-tokens**: When either file carries a `tokenColors` array, the merged `tokenColors` MUST be the base's entries followed by the including file's.
- **include-merge-other**: Every other top-level key of the including file MUST override the base's value outright.
- **include-consumed**: The `include` key MUST NOT appear in the merged document.

### Storing an imported theme

- **store-import**: Importing a VS Code theme into storage MUST parse the file using the default containment root, mark the result as imported, append it to the theme store, and return the stored theme.
- **store-import-locked**: The stored theme MUST report itself as locked and not editable.
- **store-import-failure**: When parsing fails, importing MUST propagate the error and MUST NOT write to storage.
- **store-import-no-rename**: Importing MUST NOT de-duplicate the theme's name against existing themes; the name is the given label verbatim.

### Concurrency

- **importer-isolation**: The importer holds no shared mutable state, so its parse operations MUST be callable from any thread and MUST run synchronously on the calling thread, including any blocking file reads.
- **importer-no-limits**: The importer MUST NOT impose a timeout, a file-size limit or cancellation; a parse runs to completion or fails.
- **store-isolation**: Importing a theme into the theme store MUST run on the store's single designated thread, so its file reads block that thread.
- **storage-isolation**: The settings-backed storage MUST confine every property access to that same single designated thread.

### UserSettings-backed storage

- **storage-custom-themes-key**: The custom-themes storage property MUST read and write the settings store's custom-themes setting — key `theme.custom_themes`, a JSON-encoded list of themes, default an empty list — in whichever provider the settings store holds (see [Settings Storage](agentictoolkit://cookbook/foundation/settings-storage)).
- **storage-active-key**: The active-theme-id storage property MUST read and write the settings store's active-theme-id setting — key `theme.active_theme_id`, a plain string, default the built-in catalog's default theme id.
- **storage-legacy-compatible**: The keys and encodings MUST NOT change; a value written by an earlier build under either key MUST read back unchanged, and a write MUST land under the historical key as a plain string for the active id.
- **storage-nil-write**: Clearing the active-theme-id property MUST store the built-in catalog's default theme id, never leave it empty.
- **storage-read-non-nil**: Reading the active-theme-id property MUST always return a string — the stored value, or the built-in catalog's default theme id when nothing is stored.
- **storage-observers-lazy**: The storage MUST NOT observe either setting until an external-change callback is set to a non-empty value, and MUST release both observers when the callback is cleared.
- **storage-observers-rebuilt**: Each time a non-empty external-change callback is assigned, it MUST replace both observers with fresh ones.
- **storage-change-any-writer**: Once hooked, the external-change callback MUST fire on every change to either setting — including a write made through this storage itself — not only on writes from outside this storage seam.
- **storage-change-deferred**: The external-change callback MUST be delivered on the main work queue after the new value has landed, not synchronously inside the write.
- **storage-change-no-initial**: Hooking the external-change callback MUST NOT invoke it for the values already stored.
- **storage-weak-owner**: The observers MUST NOT keep the storage alive on their own, so once the storage no longer exists, no further callbacks are delivered.

### Convenience initialisers

- **store-default-init**: Constructing the theme store with no explicit storage MUST be equivalent to constructing it with the settings-backed storage.
- **manager-default-init**: On a desktop platform, constructing the theme manager with no explicit storage or appearance driver MUST be equivalent to constructing it with the settings-backed storage and that platform's own appearance driver, whose automatic-appearance signal reads the settings store's appearance-mode setting fresh each time it is consulted.
- **manager-default-reads-disk**: A theme id stored under the active-theme-id key by an earlier build MUST be the current theme of a freshly constructed default theme manager.

## Appearance

Not applicable — this is a theme import, syntax-style and persistence engine, not a visual component.

## States

Not applicable — this is a theme import, syntax-style and persistence engine, not a visual component.

## Accessibility

Not applicable — this is a theme import, syntax-style and persistence engine, not a visual component.

## Conformance Test Vectors

Vectors derived from `SyntaxRoleOverridesTests.swift`,
`VSCodeThemeImporterTests.swift`, `LegacyThemePersistenceTests.swift` and
`ExternalThemeChangeObservationTests.swift` are marked (test). "Minimal theme"
means a document with `editor.foreground` `#D8DEE9`, `editor.background`
`#2E3440`, `editorCursor.foreground` `#FF00FF`, `editor.selectionBackground`
`#4C566A` and all sixteen ANSI keys.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| theme-engine-001 | syntax-role-vocabulary | The full set of syntax roles | 10 roles, named `keywords` … `comments`, in declaration order |
| theme-engine-002 | syntax-style-defaults, syntax-style-shape | Construct a syntax style from a color alone | bold is false, italic is false |
| theme-engine-003 | override-key-spelling (test) | Compute the override key for the `keywords` role with no flags, bold only, italic only, and both flags | `syntax.keywords`, `syntax.keywords.bold`, `syntax.keywords.italic`, `syntax.keywords.bold.italic`, respectively |
| theme-engine-004 | syntax-styles-read, override-key-spelling (test) | For every role × flag combination, a theme whose only override key is that role/flag combination's computed key, mapped to color c | Reading syntax styles returns exactly that role mapped to a style of color c with the matching bold/italic flags |
| theme-engine-005 | override-key-flag-order (test) | Override map holds `syntax.comments.italic.bold` → c | Reading syntax styles returns `comments` mapped to a style of color c, bold and italic both set |
| theme-engine-006 | override-key-prefix, override-key-role, override-key-flag-vocabulary, override-key-flag-once, override-key-no-throw (test) | Each of `syntax.nope`, `syntax.keywords.underline`, `syntax.keywords.bold.bold`, `syntax`, `syntax.`, `keywords`, `syntaxkeywords`, `prefix.syntax.keywords` → c1, alone and beside `syntax.strings` → c2 | Alone: reading syntax styles is empty. Beside: reading syntax styles returns only `strings` mapped to color c2 |
| theme-engine-007 | syntax-styles-empty | Theme with an override map of `["accent": c]` | Reading syntax styles is empty |
| theme-engine-008 | syntax-styles-tiebreak (test) | `syntax.keywords` → c1, `syntax.keywords.bold` → c2, `syntax.keywords.italic` → c3, in every insertion order | Reading syntax styles always returns `keywords` mapped to a style of color c3, italic set |
| theme-engine-009 | syntax-styles-invisible-to-roles (test) | Theme whose override map is one syntax key per role (10 keys) | The semantic palette reports every semantic role as undeclared, and each role's color equals its derived (non-override) color |
| theme-engine-010 | syntax-styles-travel (test) | Theme carrying all four key shapes plus an `accent` override, serialized then deserialized | Its override map and syntax styles equal the original's; only `accent` is a declared semantic role |
| theme-engine-011 | with-syntax-styles-replace, with-syntax-styles-preserve, with-syntax-styles-write (test) | Overrides `syntax.keywords.bold` → c1, `syntax.keywords.underline` → c8, `accent` → c9; replace syntax styles with `keywords` mapped to a style of color c2 | `syntax.*` keys are exactly `syntax.keywords`, `syntax.keywords.underline`; the rejected underline key is still c8; reading syntax styles returns `keywords` mapped to color c2; `accent` is still c9 |
| theme-engine-012 | with-syntax-styles-clear (test) | Syntax keys plus `accent` → c9; replace syntax styles with an empty set | Reading syntax styles is empty; the override map holds only `accent` → c9 |
| theme-engine-013 | with-syntax-styles-copy | Replace syntax styles on a copy of a theme (`comments` mapped to style s) | The original theme's override map is unchanged |
| theme-engine-014 | import-bytes-entry, import-name-from-label, import-lock-flags, import-appearance (test) | Parse the minimal theme from bytes with label `"Acme Dark"` and uiTheme `"vs-dark"` | Name is `"Acme Dark"`, appearance is dark, not built-in, not already marked imported, foreground `#D8DEE9FF`, background `#2E3440FF`, cursor `#FF00FFFF`, selection `#4C566AFF`, 16 ANSI colours, valid palette |
| theme-engine-015 | import-ansi-order (test) | Minimal theme whose ANSI slot n is `#0n0000` | ANSI slot 0 is `#000000FF`, slot 5 is `#050000FF`, slot 15 is `#0F0000FF` |
| theme-engine-016 | import-jsonc (test) | Minimal theme with comments and trailing commas vs its strict-JSON spelling | Identical palette, name, appearance and override map |
| theme-engine-017 | import-encodings (test) | Minimal theme as UTF-16, as UTF-16 JSONC, and as UTF-8 with BOM | Each parses to the UTF-8 result |
| theme-engine-018 | import-bytes-ignores-include (test) | Minimal theme plus `"include": "./base.json"`, parsed from bytes | Same palette as without the key; no failure |
| theme-engine-019 | import-root-object (test) | Bytes `[1, 2, 3]` | Fails with a not-an-object error |
| theme-engine-020 | import-syntax-error-passthrough | Bytes `{ "colors": ` (truncated) | Fails with the underlying JSON-parsing error, not an import-specific error |
| theme-engine-021 | import-colors-object (test) | `colors` missing, `null`, or `"x"` | Fails with a missing-colors error |
| theme-engine-022 | import-foreground-required, import-background-required, hex-invalid-absent (test) | `editor.foreground` missing; then `editor.background` missing; then `editor.foreground` `"red"` | Missing-color error naming `editor.foreground`; missing-color error naming `editor.background`; missing-color error naming `editor.foreground` |
| theme-engine-023 | import-validation-order | Both `editor.foreground` and `editor.background` missing | Fails with a missing-color error naming `editor.foreground` |
| theme-engine-024 | import-ansi-complete (test) | Minimal theme minus `terminal.ansiGreen`; then minus several keys | Missing-ANSI-colors error naming `terminal.ansiGreen`; then naming every missing key, in slot order |
| theme-engine-025 | import-foreground-background-distinct (test) | Foreground and background both `#2E3440` | Fails with a foreground-matches-background error |
| theme-engine-026 | import-appearance, import-appearance-fallback (test) | Minimal theme (dark background) with `uiTheme` `vs`, `hc-light`, `vs-dark`, `hc-black`, `aurora`; then background `#FFFFFF` with `aurora` | light, light, dark, dark, dark, respectively; then light |
| theme-engine-027 | import-cursor (test) | Minimal theme without `editorCursor.foreground` | Cursor color equals the foreground color |
| theme-engine-028 | import-selection-opaque (test) | Background `#011627`, `editor.selectionBackground` `#3392FF44` | Selection color equals `#3392FF44` composited over `#011627FF`; the stored value's alpha byte is `FF` |
| theme-engine-029 | import-selection-source, import-selection-fallback (test) | Only `editor.inactiveSelectionBackground` `#1D3B53`; then neither selection key | Selection color is `#1D3B53FF`; then selection is the background blended 20% toward the foreground |
| theme-engine-030 | import-role-overrides, import-role-overrides-present-only (test) | All six mapped keys present | Override map has exactly 6 entries, each at its mapped semantic role, each reported as declared |
| theme-engine-031 | import-no-other-roles (test) | `textLink.foreground`, `errorForeground`, `contrastBorder`, `editorWarning.foreground` present, no mapped key | Override map is empty; `accent`, `danger`, `border`, `warning`, `windowBackground`, `primaryText`, `selection` are all reported undeclared |
| theme-engine-032 | hex-forms (test) | fg `#ABCDEF12`, bg `123456`, cursor `#F0A`, `focusBorder` `#1234`, `input.background` `ABCDEF` | `#ABCDEF12`, `#123456FF`, `#FF00AAFF`, outline `#11223344`, controlBackground `#ABCDEFFF` |
| theme-engine-033 | hex-invalid-absent (test) | `editorCursor.foreground` `null`, a mapped role key as an array or a number | Cursor equals foreground; override map empty; no failure |
| theme-engine-034 | token-scope-forms (test) | Same rules as `scope: ["a", "b"]` and as `scope: "a, b"` | Identical syntax styles |
| theme-engine-035 | token-specificity (test) | Rules `keyword` → `#111111` and `keyword.control` → `#222222`, in both orders | `keywords` colour `#222222FF` both times |
| theme-engine-036 | token-tiebreak (test) | Two `keyword.control` rules, `#111111` then `#222222` bold | `keywords` = `#222222FF` + bold |
| theme-engine-037 | token-selector-clean (test) | `meta.tag entity.name.function` → c1 and `entity.name` → `#111111`; then the descendant rule alone | `commands` = `#111111FF`; then no `commands` style |
| theme-engine-038 | token-selector-clean (test) | `scope: "meta.tag entity.name.function, constant.numeric"` → `#333333` | `numbers` = `#333333FF`; no `commands` style |
| theme-engine-039 | token-emphasis (test) | `fontStyle` `italic`, `bold italic`, `italic bold`, `bold`, `underline`, `normal`, `regular`, `bold underline`, empty, absent on `#C792EA` | `+italic`, `+bold+italic`, `+bold+italic`, `+bold`, plain, plain, plain, `+bold`, plain, plain |
| theme-engine-040 | token-scope-chain, token-chain-first-match (test) | Only `support.type` → `#FFCB8B`; then `entity.name.type` → `#ADDB67` and `support.type` → `#FFCB8B` | `types` = `#FFCB8BFF`; then `#ADDB67FF` |
| theme-engine-041 | token-chain-first-match | Rules `entity` → c1 and `support.type` → c2 | `types` = c1 |
| theme-engine-042 | token-rule-usable, hex-shared (test) | `keyword.control` with foreground `"nope"`, with only `fontStyle`, with foreground `42`, each beside `keyword` → `#111111`; then foreground `#ABC` on `string.quoted.double` | `keywords` = `#111111FF` each time; `strings` = `#AABBCCFF` |
| theme-engine-043 | token-rules-source, token-no-throw, token-unmatched-role (test) | `tokenColors` absent, `"keyword.control"`, `{ "scope": "keyword" }`, `null`, `[]` | No failure; syntax styles empty; palette identical to the minimal theme |
| theme-engine-044 | token-stored-as-overrides (test) | Minimal theme with a `comment.line` rule vs without | Palette identical; non-`syntax.` overrides identical; syntax styles' keys are exactly `[comments]` |
| theme-engine-045 | import-file-entry, include-merge-colors (test) | `variant.json` `{"include": "./base.json", "colors": {"editor.background": "#111111"}}`; `base.json` is the minimal theme | foreground `#D8DEE9FF`, background `#111111FF`, cursor `#FF00FFFF`, 16 ANSI |
| theme-engine-046 | include-merge-tokens (test) | Base and variant each with a `comment.line` rule; variant also `keyword.control` → `#222222` | `comments` from the variant (`#333333FF`); `keywords` `#222222FF` |
| theme-engine-047 | include-cycle, include-depth-bound (test) | `a.json` includes `./b.json`, `b.json` includes `./a.json` | Fails with an include-chain-too-deep error (limit 8) |
| theme-engine-048 | include-containment, import-file-default-root (test) | `themes/variant.json` includes `../outside/secret.json`, no containment root given | Fails with an escapes-containment-root error |
| theme-engine-049 | include-resolve (test) | Same files, containment root set to the parent directory | Parses; foreground `#D8DEE9FF` |
| theme-engine-050 | include-detect, import-file-entry (test) | Minimal theme on disk with no `include` | Same palette as parsing the same bytes directly |
| theme-engine-051 | include-merge-other, include-consumed | Base `{"x": 1, ...}`, variant `{"include": "./base.json", "x": 2}` | Merged document has `x == 2` and no `include` key |
| theme-engine-052 | import-file-errors | Parse a file at a path that does not exist | Fails with the file-read error; nothing parsed |
| theme-engine-053 | store-import, store-import-locked (test) | A theme store over in-memory storage; import the minimal theme file with label `"Acme Dark"` and uiTheme `"vs-dark"` | Returned theme's name is `"Acme Dark"`, marked imported, locked, not editable; the custom-themes list holds exactly its id; the full theme catalog contains it |
| theme-engine-054 | store-import-failure | Import a file whose `colors` is missing | Fails with a missing-colors error; the custom-themes list is unchanged |
| theme-engine-055 | store-import-no-rename | Import the same file twice with the same label | Two custom themes, both named the label, with different ids |
| theme-engine-056 | storage-active-key, storage-legacy-compatible (test) | The settings store already holds `theme.active_theme_id` = the Dracula theme's id, written the pre-seam way | A freshly constructed settings-backed storage's active-theme-id reads back the Dracula theme's id |
| theme-engine-057 | storage-legacy-compatible (test) | Set the storage's active-theme-id to the Nord theme's id | The settings store's `theme.active_theme_id` key holds the Nord theme's id |
| theme-engine-058 | storage-nil-write, storage-read-non-nil | Clear the storage's active-theme-id, then read it back | Reads the built-in catalog's default theme id |
| theme-engine-059 | storage-custom-themes-key | Set the storage's custom-themes list to `[t]`, then read the settings store's custom-themes setting directly | `[t]` |
| theme-engine-060 | storage-change-any-writer, storage-change-deferred (test) | A theme manager over this storage; write the settings store's active-theme-id setting directly to the Dracula theme's id | After the main work queue drains, a change notification fires and the manager's current theme is the Dracula theme |
| theme-engine-061 | storage-change-any-writer (test) | Rewrite the settings store's custom-themes setting with the active custom theme renamed | Notification fires; the manager's current theme has the new name |
| theme-engine-062 | storage-change-any-writer (test) | Select the Dracula theme through the manager | Exactly one change notification fires (the storage callback fires, but the manager's reload de-duplicates) |
| theme-engine-063 | storage-observers-lazy, storage-change-no-initial | Set the external-change callback to a counter, drain the main work queue, then clear the callback and write both settings | Counter stays 0 |
| theme-engine-064 | store-default-init, manager-default-init, manager-default-reads-disk (test) | The settings store already holds `theme.active_theme_id` = the Gruvbox Dark theme's id; construct a default theme manager | Current theme is Gruvbox Dark |

## Edge Cases

- **Empty or missing theme data**: Parsing empty bytes MUST fail with the underlying JSON-parsing error; a document `{}` MUST fail with a missing-colors error; `"colors": {}` MUST fail with a missing-color error naming `editor.foreground`.
- **A variant file on its own**: a per-variant file that restates a few colours and relies on `include` MUST fail with a missing-color error naming `editor.foreground` when parsed from bytes, and MUST parse when read through the file-based entry point — which is why production callers use the file entry point.
- **Empty or non-string include**: `"include": ""`, `"include": 3` or `"include": null` MUST be treated as no include (MUST).
- **Include one level too deep**: a chain of 9 files (8 hops) MUST parse; a 10th file (9th hop) MUST fail with an include-chain-too-deep error (limit 8) (MUST).
- **Non-object colors in one link of a chain**: when the including file's `colors` is not an object but the base's is, the merged `colors` MUST be the base's (the non-object value is replaced by the merge); the same holds for a non-array `tokenColors` (MUST).
- **Symlinked include**: containment is decided on the symlink-resolved path; a symlink that lands outside the root MUST fail with an escapes-containment-root error (MUST).
- **Unreadable optional colour**: a named colour, a 5- or 7-digit value, or a non-string for any optional key MUST count as absent and fall back (cursor → foreground, selection → blend, role → no override) (MUST).
- **Translucent required colours**: `editor.foreground` and `editor.background` MUST be stored with their declared alpha; only selection is composited (MUST).
- **Foreground equal to background only after normalisation**: `#FFF` and `#FFFFFFFF` MUST be treated as equal and fail with a foreground-matches-background error (MUST).
- **tokenColors entry with a `scope` array holding `null`**: the `null` element MUST be skipped and the entry's other selectors kept (MUST).
- **Scope absent**: an entry with no `scope` (VS Code's "applies to everything") MUST produce no rule, so it cannot falsely match the first role queried (MUST).
- **No rule matches any role**: syntax styles MUST be empty and no `syntax.` key written (MUST).
- **Hand-edited duplicate syntax keys**: two keys for one role MUST resolve to the lexicographically greatest; replacing syntax styles MUST remove both (MUST).
- **Rejected `syntax.` key**: it MUST be preserved when replacing syntax styles and ignored when reading them and by the semantic palette (MUST).
- **Concurrent access**: the importer has no shared state, so concurrent parses on different threads MUST NOT interfere (MUST). The theme store and its settings-backed storage are confined to a single designated thread, so their calls are serialised and cannot interleave (MUST).
- **Write followed by callback**: a write through the settings-backed storage MUST produce an external-change callback on a later main-queue turn; a consumer that also reacts synchronously sees two notifications unless it de-duplicates, as the theme manager's reload does (MUST).
- **Storage never hooked**: a theme store used without a theme manager MUST allocate no observers (MUST).
- **Corrupt stored themes**: what the custom-themes setting returns when the stored JSON does not decode is owned by the active settings-storage provider (see [Settings Storage](agentictoolkit://cookbook/foundation/settings-storage)); this storage returns whatever the setting holds without further validation (MUST).
- **Large theme file**: the importer MUST read the whole file into memory with no size cap and no timeout (MUST); when importing into the theme store, this blocks that store's designated thread for the read.
- **Cancellation**: no parse can be cancelled once started (MUST).
- **Error states**: every failure MUST surface to the caller as an error — an import error, a resource-path error, a file-read error, or the underlying JSON-parsing error — and nothing is stored (MUST).
- **Offline or disconnected state**: not applicable; the component reads local files and local settings only and performs no network I/O.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Theme bytes | Raw bytes | — | Raw theme bytes for byte-based parsing; JSONC, UTF-8/UTF-16, optional BOM. |
| Theme file location | File location | — | Theme file for file-based parsing and importing into storage; the caller vouches for it (not containment-checked). |
| Label | Text | — | The manifest entry's `label`; becomes the theme's name. |
| UI theme | Text | — | The manifest entry's `uiTheme` (`vs`, `vs-dark`, `hc-light`, `hc-black`); decides appearance. |
| Containment root | File location (optional) | The theme file's own directory | Root every `include` must stay inside; the theme contribution point passes the extension's folder. |
| Maximum include depth | Whole number (internal constant) | `8` | Include hops followed before failing with an include-chain-too-deep error. |
| `theme.custom_themes` | Settings-store key, JSON-encoded list of themes | Empty list | Where the settings-backed storage keeps custom and imported themes. |
| `theme.active_theme_id` | Settings-store key, text | The built-in catalog's default theme id | The selected theme's id. |
| Appearance-mode setting | Settings-store setting | host-defined | Read by the default theme manager's automatic-appearance signal for auto-appearance themes. |
| External-change callback | Optional callback | Absent | Callback the theme manager installs; setting it allocates the two setting observers. |
| Settings-store provider | injected provider | host-configured | Backend both keys are persisted in. |

## Deep Linking

Not applicable: the sources define no URL scheme, route or deep-link handler; the engine is reached only through direct calls.

## Localization

Not applicable: the sources contain no user-facing strings. Import errors provide no localized description of their own, so a caller that requests one gets a generic, non-localized description of the failure case (see import-error-descriptions); the theme name is the manifest's `label`, passed through verbatim.

## Accessibility Options

Not applicable: the engine renders nothing and reads no Reduce Motion, Increase Contrast or Differentiate Without Color setting; only the default theme manager reads the appearance-mode setting for auto-appearance themes.

## Feature Flags

Not applicable: no part of this engine reads a feature flag; every code path is unconditional.

## Analytics

Not applicable: the sources emit no analytics events.

## Privacy

Not applicable: the engine handles colour themes and a theme id only — no personal data, credentials or tokens — and transmits nothing off the device.

## Logging

Not applicable: this engine logs nothing; every failure is reported to the caller as an error instead.

## Platform Notes

- **SwiftUI**: The source is Swift and platform-neutral except the macOS manager-wiring file. The syntax-role/key-grammar and VS Code importer files are Foundation-only; the settings-backed storage file depends on this toolkit's settings store (which declares the two keys) and a settings-change observer that delivers on the main dispatch queue after skipping the first, already-current value. A SwiftUI host holds a theme manager and observes its change notification; nothing here is SwiftUI-specific.
- **Compose**: Port the syntax-role vocabulary as a Kotlin `enum class` with the same lowercase names and the syntax style as a `data class`. Parse with `kotlinx.serialization.json.Json { isLenient = true; allowTrailingComma = true; allowComments = true }` into a `JsonObject` and read by key, as the source does, rather than a strict `@Serializable` model. Resolve includes with `java.nio.file.Path.resolve(...).toRealPath()` plus a `startsWith(root)` check. Back the storage seam with Jetpack `DataStore<Preferences>` under the same two keys; the external-change callback becomes collecting the DataStore `Flow` with `drop(1)`, dispatched on `Dispatchers.Main`.
- **React/Web**: Port the importer as a pure TypeScript module over `JSON.parse` after a JSONC strip (`jsonc-parser`'s `parse` with `allowTrailingComma`); `Map` iteration order is insertion order, but keep the lexicographic tie-break so the result does not depend on it. File access and include containment only exist in Node/Electron (`fs.readFileSync`, `path.resolve` + `fs.realpathSync` + a prefix check); a browser port accepts bytes only, like the byte-based entry point. Persist with `localStorage` under the same keys; the cross-tab `storage` event is the external-change-callback equivalent, and it does not fire in the writing tab — unlike the source, which fires for its own writes too.
- **AppKit / UIKit**: This is the source's own platform, and Swift throughout. The shared model types (`ColorTheme`, `RGBAColor`, `ThemeRole`, `SemanticPalette`) ship from AgenticDeveloperToolkit; this layer adds `SyntaxRole`/`SyntaxStyle` (`SyntaxRoleOverrides.swift`), `VSCodeThemeImporter` (a caseless `enum` of non-isolated static functions with no mutable state), `UserSettingsThemeStorage` (a `@MainActor final class` conforming to `ThemeStorage`), and, on macOS, `ThemeManager+UserSettings.swift`. `SyntaxRole` raw values equal `EditorTheme`'s field names verbatim (syntax-role-names); `SyntaxRole.overrideKey(bold:italic:)` computes the key grammar; `ColorTheme.syntaxStyles` reads it and `ColorTheme.withSyntaxStyles(_:)` replaces it, both operating on `roleOverrides`. `SyntaxRole` and `SyntaxStyle` are `Sendable`, `Equatable` value types. Errors are `VSCodeThemeParseError` cases — `.notAnObject`, `.missingColors`, `.missingColor(String)`, `.foregroundMatchesBackground`, `.missingANSIColors([String])`, `.includeChainTooDeep(limit:)` — plus `ExtensionResourcePathError.escapesExtensionDirectory` for include-containment failures; `VSCodeThemeParseError` does not conform to `LocalizedError` (import-error-descriptions), so `localizedDescription` falls back to Foundation's generic enum description. The two entry points are `VSCodeThemeImporter.parse(_:label:uiTheme:)` (bytes) and `.parse(contentsOf:label:uiTheme:containedIn:)` (file, resolving `include` via `ExtensionResourcePath.resolve(_:relativeTo:containedIn:)`); decoding goes through `JSONCPreprocessor.jsonObject(from:)`. `ThemeStore.importVSCodeTheme(contentsOf:label:uiTheme:)` wraps the file entry point and calls `ThemeStore.add(_:)`; it and every other `ThemeStore` member run on `@MainActor` because `ThemeStore` is `@MainActor`-isolated, so `importVSCodeTheme`'s file reads block the main actor. `UserSettingsThemeStorage.customThemes`/`.activeThemeID` read and write `UserSettings.customThemes`/`.activeThemeID` (declared in `UserSettings+Theme.swift`); assigning `nil` to `activeThemeID` stores `BuiltInThemes.defaultID` because the backing `UserSetting<String>` is non-optional. The external-change callback is backed by `UserSettingObserver`, which delivers on `DispatchQueue.main` after `dropFirst()` and holds the storage `weak`, so a deallocated storage receives no callback. `ThemeStore()` is sugar for `ThemeStore(storage: UserSettingsThemeStorage())`; on macOS, `ThemeManager()` installs `AppKitAppearanceDriver` with `autoAppearance` reading `UserSettings.appearanceMode.currentValue.nsAppearance`, read fresh on each call; a UIKit port swaps in a driver that sets `overrideUserInterfaceStyle` on the window scene instead. `ThemeManager.reload()` compares the resolved theme against `currentTheme` and returns early when unchanged, which is what keeps `didChangeNotification` from firing twice for one user-initiated selection (`selectTheme(id:)`). `hasValidPalette`, `composited(over:)` and `blended(withFraction:of:)` are the `ColorTheme`/`RGBAColor` members behind the palette-validity gate and the selection-colour derivation; `InMemoryThemeStorage` is the test double used by the storage-related test vectors. `ThemeContributionPoint.swift` is the production caller of `parse(contentsOf:…containedIn:)`, resolving the manifest's `path` through `ExtensionResourcePath.resolve(_:inside:)` first; `ThemeSettingsPanelViewController` is where a user duplicates an imported theme to edit it.
- **WinUI 3**: Port the model as C# `record` types (`SyntaxStyle(Color, bool Bold, bool Italic)`) and the syntax role as an `enum` with a lowercase-name mapping. Parse with `System.Text.Json.JsonDocument.Parse(bytes, new JsonDocumentOptions { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true })` and walk `JsonElement`s by key (`TryGetProperty`, `ValueKind`) to keep the source's "read by key, absent on wrong type" rule; detect UTF-16 with `StreamReader`'s BOM detection before parsing. Read files with `Windows.Storage.StorageFile.GetFileFromPathAsync` + `FileIO.ReadBufferAsync`, or `System.IO.File.ReadAllBytes` in an unpackaged app; do include containment with `Path.GetFullPath` plus a case-insensitive `StartsWith(root)` check, resolving reparse points with `FileSystemInfo.ResolveLinkTarget(true)`. Where the source is synchronous, expose `Task<ColorTheme> ParseAsync(...)` so the UI thread is not blocked. Back the storage seam with `Windows.Storage.ApplicationData.Current.LocalSettings.Values["theme.active_theme_id"]` (a string) and a JSON string (or a `LocalFolder` file, since a settings value is capped at 8 KB) for `theme.custom_themes`; implement change notification with `INotifyPropertyChanged` on a storage class and dispatch the callback through `DispatcherQueue.TryEnqueue` to match the source's deferred main-queue delivery. Expose the catalog as an `ObservableCollection<ColorTheme>` for a `ListView` theme picker.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Theme/SyntaxRoleOverrides.swift` |
| apple | `packages/apple/AgenticToolkit/Core/Theme/UserSettingsThemeStorage.swift` |
| apple | `packages/apple/AgenticToolkit/Core/Theme/VSCodeThemeImporter.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/Theme/ThemeManager+UserSettings.swift` |

## Design Decisions

**Decision**: Syntax styles are stored inside `ColorTheme.roleOverrides` under a `syntax.` key namespace instead of a separate field or side store.
**Rationale**: Per the `syntaxStyles` doc comment, `ColorTheme` is the unit that travels, and `ColorTheme.init(from:)` decodes a fixed key list, so anything stored beside it is silently dropped by `exportJSON(_:)` and `duplicate(_:)`; duplicating an imported theme would then repaint the editor. `SemanticPalette` looks roles up by `ThemeRole.rawValue`, so the extra keys are invisible to it.
**Approved**: pending

**Decision**: Duplicate syntax keys for one role resolve to the lexicographically greatest key.
**Rationale**: Only a hand-edited theme can carry two; dictionary iteration order is not stable, so "last seen wins" would give different answers for two reads of the same theme. A total order makes the answer stable.
**Approved**: pending

**Decision**: `withSyntaxStyles(_:)` replaces rather than merges, and leaves grammar-rejected `syntax.` keys in place.
**Rationale**: Re-importing must not leave a stale shape behind (a stale `syntax.keywords.bold` would outrank a fresh `syntax.keywords`); sharing one parser with `syntaxStyles` keeps the two from disagreeing about what a syntax key is, and an inert key is clutter a future widening of the grammar may want to own.
**Approved**: pending

**Decision**: The importer reads the deserialised document by key instead of decoding a `Codable` model.
**Rationale**: Real themes carry many keys the importer ignores (`$schema`, `semanticTokenColors`, non-schema objects); a strict decoder is the wrong tool for a file consumed in part. `semanticTokenColors` is ignored because the editor highlights with tree-sitter, which has no semantic-token vocabulary.
**Approved**: pending

**Decision**: Required colours and all sixteen ANSI slots fail fast; optional colours and `tokenColors` degrade silently to "absent".
**Rationale**: `hasValidPalette` gates the store, the terminal profile editor indexes every slot, and `SemanticPalette` derives accent, status and syntax colours from specific slots, so a synthesised slot silently repaints the editor. An unreadable optional key should never cost the user a theme VS Code itself renders. `VSCodeThemeParseError` is reserved for documents that cannot produce a palette.
**Approved**: pending

**Decision**: Only six VS Code keys become `ThemeRole` overrides.
**Rationale**: Writing a redundant override would make `SemanticPalette.declares(_:)` report an author choice nobody made. Tempting keys are wrong in real themes: `textLink.foreground` is white in one popular theme, `errorForeground` is body-text grey in others, `contrastBorder` is missing from genuine high-contrast themes, and `editorWarning.foreground` means "squiggle".
**Approved**: pending

**Decision**: Selection is stored opaque, composited over the background.
**Rationale**: `SemanticPalette.derive(.selectionText)` is `theme.selection.bestTextColor()`; measuring contrast against a translucent value that is never painted picks black over what renders dark.
**Approved**: pending

**Decision**: The syntax scope chains are fixed scopes measured against 20 published Open VSX themes, with `types` alone carrying a fallback to `support.type`.
**Rationale**: Nine of ten roles resolve in 20/20 themes on the named scope; `entity.name.type` resolves in 16/20 and the Night Owl family needs `support.type`. Broader alternatives (`keyword`, `entity.name`, `string`, `comment`) matched fewer themes or were outranked by longer rules.
**Approved**: pending

**Decision**: Descendant selectors (containing whitespace) and scope-less `tokenColors` entries are dropped.
**Rationale**: The importer has no ancestor context, so matching on the last component would paint the wrong tokens; a scope-less entry could only produce a false match against the first role queried. An undeclared role derives, which is better than a confidently wrong colour.
**Approved**: pending

**Decision**: Include chains are bounded by depth (8) rather than a visited-set, and every include goes through the same containment check as a manifest path.
**Rationale**: VS Code allows nesting and real packs use two or three levels; a bound is all a cycle needs. The include path is extension-controlled, so `../../../../.ssh/config` is the same escape a manifest `path` could attempt.
**Approved**: pending

**Decision**: Syntactically invalid JSON surfaces as the `JSONSerialization` error rather than a `VSCodeThemeParseError`, although the `parse` doc comment says it throws `VSCodeThemeParseError` for a malformed document.
**Rationale**: `object(from:)` only wraps the "root is not an object" case; `JSONCPreprocessor.jsonObject(from:)` rethrows the raw-bytes `JSONSerialization` error by its own contract. The error still reaches the caller, and `ThemeContributionPoint` reports every error through `localizedDescription` alike.
**Approved**: pending

**Decision**: `UserSettingsThemeStorage` keeps the historical `theme.custom_themes` and `theme.active_theme_id` keys and encodings, and a `nil` active id writes the default.
**Rationale**: Changing either would silently orphan every theme a user has already saved; `UserSetting<String>` is non-optional, so `nil` cannot be stored.
**Approved**: pending

**Decision**: `onExternalChange` fires on every change to either setting, including this storage's own writes, although the `ThemeStorage` protocol describes it as a notice of changes from outside the seam.
**Rationale**: The class's own doc comment declares "any change to either setting", and `UserSettingObserver` cannot tell writers apart. `ThemeManager.reload()` compares the resolved theme with `currentTheme` and returns early when nothing changed, so a selection posts one notification (verified by the "exactly once" test).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

Parsing (`VSCodeThemeImporter`), the key grammar (`SyntaxRoleOverrides.swift`) and persistence (`UserSettingsThemeStorage`) are separate files with no UI code, and the only AppKit dependency is confined to the macOS `ThemeManager()` initialiser (separation-of-concerns: passed). `SyntaxRoleOverridesTests`, `VSCodeThemeImporterTests`, `LegacyThemePersistenceTests` and `ExternalThemeChangeObservationTests` assert every error case, the key grammar, the tie-breaks, include resolution, containment and legacy-key compatibility (unit-test-coverage: passed). Every document-level failure is thrown with a typed case, but unreadable optional colours and unusable `tokenColors` entries are dropped with no signal to the caller by design, invalid JSON surfaces as an untyped `JSONSerialization` error, and `VSCodeThemeParseError` carries no localized description (explicit-error-handling: partial). Extension-controlled include paths are containment-checked on the symlink-resolved path and bounded to 8 hops, and every value is type-checked before use (input-sanitization: passed). A theme missing optional colours, role keys or syntax rules still imports and derives the rest (graceful-degradation: passed). The importer validates the palette before anything is stored, but `UserSettingsThemeStorage` reads and writes `[ColorTheme]` without its own validation and leaves detection of corrupt stored JSON to the settings provider (data-integrity: partial).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/theme/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from AgenticToolkit Core/Theme and the macOS ThemeManager initialiser. |
