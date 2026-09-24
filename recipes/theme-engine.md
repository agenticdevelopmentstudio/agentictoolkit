---
id: 0e35ddf2-3e87-4a5a-9fd9-24bafc7325b6
title: Theme Engine
domain: agentictoolkit://recipes/theme-engine
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'AgenticToolkit''s theme-engine layer: VS Code theme import, syntax-role
  overrides in roleOverrides, and UserSettings-backed theme storage.'
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
- agentictoolkit://recipes/settings-storage
- agentictoolkit://recipes/foundation-json
- agentictoolkit://recipes/extension-host-core-extensions-extension-resource-path
related:
- agentictoolkit://recipes/theme-picker-view
- agentictoolkit://recipes/theme-preview-view
references:
- https://code.visualstudio.com/api/extension-guides/color-theme
approved-by: ''
approved-date: ''
---

# Theme Engine

## Overview

This recipe covers the AgenticToolkit (ATK) half of the theme engine. The
theme model itself — `ColorTheme`, `RGBAColor`, `ThemeRole`,
`SemanticPalette`, `ThemeStore`, `ThemeStorage`, `ThemeManager` — ships from
AgenticDeveloperToolkit and is specified by
[Theme Engine (ADT)](agenticdevelopertoolkit://recipes/theme-engine). ATK adds
four things on top of it, each in its own source file:

- **`SyntaxRoleOverrides.swift`** — the `SyntaxRole` vocabulary (the ten syntax
  attributes a source editor paints), the `SyntaxStyle` value (colour + bold +
  italic), and the `syntax.<role>[.bold][.italic]` key grammar that stores
  those styles inside `ColorTheme.roleOverrides`, read by
  `ColorTheme.syntaxStyles` and written by `ColorTheme.withSyntaxStyles(_:)`.
- **`VSCodeThemeImporter.swift`** — a caseless namespace that parses a VS Code
  colour-theme JSON(C) file into a `ColorTheme`: palette, appearance, six
  semantic role overrides, `tokenColors`-derived syntax styles, and `include`
  chain resolution with a containment root and a depth bound. It also adds
  `ThemeStore.importVSCodeTheme(contentsOf:label:uiTheme:)`, which stores the
  result as a locked imported theme.
- **`UserSettingsThemeStorage.swift`** — the `ThemeStorage` conformer that
  persists custom themes and the active theme id through ATK's `UserSettings`
  under the historical keys, plus the zero-argument `ThemeStore()`.
- **`ThemeManager+UserSettings.swift`** (macOS) — the zero-argument
  `ThemeManager()` wiring that storage to an `AppKitAppearanceDriver`.

Use it when a host needs VS Code themes, per-role syntax colours that travel
with a theme, or the theme store persisted in `UserSettings`. It has no
visual surface.

## Behavioral Requirements

### Syntax roles and styles

- **syntax-role-vocabulary**: `SyntaxRole` MUST have exactly ten cases whose raw values are `keywords`, `commands`, `types`, `attributes`, `variables`, `values`, `numbers`, `strings`, `characters` and `comments`, in that declaration order.
- **syntax-role-names**: Each `SyntaxRole` raw value MUST equal the name of the corresponding syntax field of `EditorTheme` verbatim, so a consumer assigns a role across without a translation table.
- **syntax-style-shape**: `SyntaxStyle` MUST carry exactly a `color` (`RGBAColor`), a `bold` flag and an `italic` flag; it MUST NOT carry underline or strikethrough.
- **syntax-style-defaults**: `SyntaxStyle.init(color:bold:italic:)` MUST default `bold` and `italic` to `false`.
- **syntax-value-semantics**: `SyntaxRole` and `SyntaxStyle` MUST be `Sendable` and `Equatable` value types, safe to pass across isolation domains.

### The roleOverrides key grammar

- **override-key-spelling**: `SyntaxRole.overrideKey(bold:italic:)` MUST return `syntax.` + the role's raw value, then `.bold` when `bold` is true, then `.italic` when `italic` is true — so the only four shapes written are `syntax.<role>`, `syntax.<role>.bold`, `syntax.<role>.italic` and `syntax.<role>.bold.italic`.
- **override-key-flag-order**: When reading, the grammar MUST treat the trailing segments as a set, so `syntax.comments.italic.bold` MUST parse identically to `syntax.comments.bold.italic`.
- **override-key-prefix**: A key MUST be recognised as a syntax key only when splitting it on `.` (keeping empty segments) yields at least two segments and the first segment is exactly `syntax`.
- **override-key-role**: A key whose second segment is not exactly a `SyntaxRole` raw value (case-sensitive) MUST NOT be recognised as a syntax key.
- **override-key-flag-vocabulary**: A key with any trailing segment other than `bold` or `italic` — including an empty segment — MUST NOT be recognised as a syntax key.
- **override-key-flag-once**: A key that states `bold` twice or `italic` twice MUST NOT be recognised as a syntax key.
- **override-key-no-throw**: An unrecognised key MUST be ignored — never thrown on — and MUST NOT prevent a well-formed syntax key in the same dictionary from being read.
- **override-key-collision-free**: The `syntax` namespace MUST NOT collide with `ThemeRole` keys; the source relies on `ThemeRole` raw values being camelCase identifiers that cannot contain a dot.

### Reading and writing syntax styles

- **syntax-styles-read**: `ColorTheme.syntaxStyles` MUST return one `SyntaxStyle` per role that has at least one recognised key in `roleOverrides`, with the key's colour and the bold/italic flags the key names.
- **syntax-styles-empty**: `ColorTheme.syntaxStyles` MUST return an empty dictionary for a theme with no recognised syntax key.
- **syntax-styles-tiebreak**: When more than one recognised key names the same role, `syntaxStyles` MUST resolve to the lexicographically greatest key (so `syntax.keywords.italic` beats `syntax.keywords.bold`, which beats `syntax.keywords`), independent of dictionary iteration or insertion order.
- **syntax-styles-invisible-to-roles**: Syntax keys MUST NOT cause `SemanticPalette` to report any `ThemeRole` as declared, because `SemanticPalette` looks roles up strictly by `ThemeRole.rawValue`.
- **syntax-styles-travel**: Syntax keys MUST survive a `ColorTheme` JSON encode/decode round trip unchanged, because they live in `roleOverrides`, which `ColorTheme` encodes; this is what carries them through `ThemeStore.exportJSON(_:)` and `ThemeStore.duplicate(_:)`.
- **with-syntax-styles-replace**: `ColorTheme.withSyntaxStyles(_:)` MUST remove every key the grammar recognises as a syntax key before writing the new styles, so the result carries exactly the given styles and no stale shape survives.
- **with-syntax-styles-preserve**: `withSyntaxStyles(_:)` MUST leave every other `roleOverrides` entry unchanged, including a `syntax.`-prefixed key the grammar rejects (for example `syntax.keywords.underline`).
- **with-syntax-styles-write**: `withSyntaxStyles(_:)` MUST write each style under `role.overrideKey(bold: style.bold, italic: style.italic)` with the style's colour as the value.
- **with-syntax-styles-clear**: `withSyntaxStyles([:])` MUST remove every recognised syntax key and nothing else.
- **with-syntax-styles-copy**: `withSyntaxStyles(_:)` MUST return a modified copy and MUST NOT mutate the receiver.
- **syntax-grammar-shared**: `syntaxStyles` and `withSyntaxStyles(_:)` MUST use the same parser, so the set of keys one reads is exactly the set the other replaces.

### VS Code import: entry points

- **import-bytes-entry**: `VSCodeThemeImporter.parse(_:label:uiTheme:)` MUST parse raw theme bytes into a `ColorTheme` or throw.
- **import-jsonc**: Both entry points MUST accept JSONC — `//` and block comments and trailing commas — and MUST produce the same theme a strict-JSON spelling of the same document produces.
- **import-encodings**: Both entry points MUST accept UTF-8, UTF-8 with a byte-order mark, and UTF-16 payloads (including UTF-16 JSONC), producing the same theme as the UTF-8 spelling, by decoding through `JSONCPreprocessor.jsonObject(from:)` (see [Foundation JSON](agentictoolkit://recipes/foundation-json)).
- **import-bytes-ignores-include**: `parse(_:label:uiTheme:)` MUST NOT resolve an `include` key and MUST NOT reject a document for carrying one; the result MUST equal the result for the same document without the key.
- **import-file-entry**: `VSCodeThemeImporter.parse(contentsOf:label:uiTheme:containedIn:)` MUST read the file at `url`, resolve its `include` chain, and parse the merged document.
- **import-file-default-root**: When `containedIn` is `nil`, the containment root MUST be the theme file's own directory.
- **import-file-url-precondition**: The top-level `url` is a caller precondition: the importer MUST NOT containment-check it — only `include` targets are checked. The shipping caller, `ThemeContributionPoint`, resolves the manifest's `path` through `ExtensionResourcePath.resolve(_:inside:)` before calling.
- **import-name-from-label**: The imported theme's `name` MUST be the `label` argument; the theme file's own `name` and `type` keys MUST be ignored.
- **import-lock-flags**: `parse` MUST return a theme with `isBuiltIn == false` and `isImported == false`, carrying the freshly generated UUID string `ColorTheme.init` assigns as its `id`.

### VS Code import: validation and errors

- **import-validation-order**: The importer MUST check, in this order, and throw the first failure: root is an object; `colors` is an object; `editor.foreground` is present and parses; `editor.background` is present and parses; foreground differs from background; all sixteen ANSI keys are present and parse.
- **import-syntax-error-passthrough**: When no candidate encoding yields a parseable JSON document, the importer MUST propagate the error `JSONSerialization` throws for the raw bytes unchanged; it is not wrapped in `VSCodeThemeParseError`.
- **import-root-object**: A document whose root is not a JSON object MUST throw `VSCodeThemeParseError.notAnObject`.
- **import-colors-object**: A document whose `colors` member is absent, `null`, or not an object MUST throw `VSCodeThemeParseError.missingColors`.
- **import-foreground-required**: An absent or unparseable `editor.foreground` MUST throw `VSCodeThemeParseError.missingColor("editor.foreground")`.
- **import-background-required**: An absent or unparseable `editor.background` MUST throw `VSCodeThemeParseError.missingColor("editor.background")`.
- **import-foreground-background-distinct**: A theme whose parsed foreground equals its parsed background MUST throw `VSCodeThemeParseError.foregroundMatchesBackground`.
- **import-ansi-complete**: When any of the sixteen `terminal.ansi*` keys is absent or unparseable, the importer MUST throw `VSCodeThemeParseError.missingANSIColors` carrying every missing key, in `ColorTheme.ansi` slot order; it MUST NOT synthesise a missing slot.
- **import-ansi-order**: The sixteen ANSI colours MUST be stored in the slot order `terminal.ansiBlack`, `Red`, `Green`, `Yellow`, `Blue`, `Magenta`, `Cyan`, `White`, then the eight `terminal.ansiBright*` keys in the same colour order.
- **import-file-errors**: A file read failure for the top-level file or any included file MUST propagate the error `Data(contentsOf:)` throws unchanged.
- **import-error-descriptions**: `VSCodeThemeParseError` MUST NOT conform to `LocalizedError`; a caller that shows `localizedDescription` gets Foundation's generic description of the enum case.

### VS Code import: palette mapping

- **import-appearance**: `uiTheme` MUST decide `appearance`: `vs-dark` and `hc-black` MUST yield `.dark`; `vs` and `hc-light` MUST yield `.light`.
- **import-appearance-fallback**: Any other `uiTheme` value MUST yield `.dark` when the parsed background `isDark` and `.light` otherwise.
- **import-cursor**: `cursor` MUST be `editorCursor.foreground` when present and parseable, and the foreground otherwise.
- **import-selection-source**: The declared selection MUST be `editor.selectionBackground` when present and parseable, else `editor.inactiveSelectionBackground` when present and parseable.
- **import-selection-opaque**: A declared selection MUST be stored composited over the background (`composited(over:)`), so the stored value is opaque (alpha byte `FF`).
- **import-selection-fallback**: With neither selection key usable, `selection` MUST be `background.blended(withFraction: 0.20, of: foreground)`.
- **import-role-overrides**: The importer MUST map exactly these six keys to `ThemeRole` overrides: `sideBar.background` → `surface`, `editorWidget.background` → `elevatedSurface`, `input.background` → `controlBackground`, `descriptionForeground` → `secondaryText`, `input.placeholderForeground` → `placeholderText`, `focusBorder` → `outline`.
- **import-role-overrides-present-only**: A mapped key MUST become an override only when it is present and parses; an absent or unparseable key MUST write nothing.
- **import-no-other-roles**: The importer MUST NOT write an override for any other `ThemeRole` — in particular not `windowBackground`, `primaryText`, `selection`, `accent`, `danger`, `border` or `warning` — even when a tempting VS Code key (`textLink.foreground`, `errorForeground`, `contrastBorder`, `editorWarning.foreground`) is present.

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
- **token-no-throw**: Nothing in `tokenColors` handling MUST throw; a malformed `tokenColors` yields no styles and the rest of the theme is unchanged.
- **token-stored-as-overrides**: The resolved syntax styles MUST be stored via `withSyntaxStyles(_:)`, so they appear as `syntax.*` keys in `roleOverrides` alongside the six role overrides and change no palette field.

### VS Code import: include chains

- **include-detect**: A document MUST be treated as including another only when its `include` value is a non-empty string; any other value MUST be treated as no include.
- **include-resolve**: An include path MUST be resolved relative to the including file's directory and MUST stay inside the containment root, via `ExtensionResourcePath.resolve(_:relativeTo:containedIn:)` (see [Extension Resource Path](agentictoolkit://recipes/extension-host-core-extensions-extension-resource-path)).
- **include-containment**: An include that resolves outside the containment root MUST throw `ExtensionResourcePathError.escapesExtensionDirectory`.
- **include-depth-bound**: The importer MUST follow at most 8 include hops; a document at depth 8 that still names an include MUST throw `VSCodeThemeParseError.includeChainTooDeep(limit: 8)`.
- **include-cycle**: A cycle (`a.json` including `b.json` including `a.json`) MUST be stopped by the depth bound and throw `includeChainTooDeep(limit: 8)`; there is no visited-set.
- **include-merge-colors**: When both files carry a `colors` object, the merged `colors` MUST be the base's keys overlaid key by key with the including file's, the including file winning.
- **include-merge-tokens**: When either file carries a `tokenColors` array, the merged `tokenColors` MUST be the base's entries followed by the including file's.
- **include-merge-other**: Every other top-level key of the including file MUST override the base's value outright.
- **include-consumed**: The `include` key MUST NOT appear in the merged document.

### Storing an imported theme

- **store-import**: `ThemeStore.importVSCodeTheme(contentsOf:label:uiTheme:)` MUST parse with `parse(contentsOf:label:uiTheme:)` using the default containment root, set `isImported = true`, append the theme through `ThemeStore.add(_:)`, and return the stored theme.
- **store-import-locked**: The stored theme MUST report `isLocked == true` and `isEditable == false`.
- **store-import-failure**: When parsing throws, `importVSCodeTheme` MUST propagate the error and MUST NOT write to storage.
- **store-import-no-rename**: `importVSCodeTheme` MUST NOT de-duplicate the theme's name against existing themes; the name is the `label` verbatim.

### Concurrency

- **importer-isolation**: `VSCodeThemeImporter` is a caseless `enum` of non-isolated static functions with no mutable state; its parse functions MUST be callable from any thread and MUST run synchronously on the calling thread, including the blocking file reads.
- **importer-no-limits**: The importer MUST NOT impose a timeout, a file-size limit or cancellation; a parse runs to completion or throws.
- **store-isolation**: `ThemeStore.importVSCodeTheme` MUST run on the main actor, because `ThemeStore` is `@MainActor`; its file reads therefore block the main actor.
- **storage-isolation**: `UserSettingsThemeStorage` is a `@MainActor` `final class`; every property access MUST happen on the main actor.

### UserSettings-backed storage

- **storage-custom-themes-key**: `UserSettingsThemeStorage.customThemes` MUST read and write `UserSettings.customThemes` — key `theme.custom_themes`, a JSON-encoded `[ColorTheme]`, default `[]` — in whichever provider `UserSettings.shared` holds (see [Settings Storage](agentictoolkit://recipes/settings-storage)).
- **storage-active-key**: `UserSettingsThemeStorage.activeThemeID` MUST read and write `UserSettings.activeThemeID` — key `theme.active_theme_id`, a plain `String`, default `BuiltInThemes.defaultID`.
- **storage-legacy-compatible**: The keys and encodings MUST NOT change; a value written by an earlier build under either key MUST read back unchanged, and a write MUST land under the historical key as a plain string for the active id.
- **storage-nil-write**: Assigning `nil` to `activeThemeID` MUST store `BuiltInThemes.defaultID`, never `nil`.
- **storage-read-non-nil**: Reading `activeThemeID` MUST return the stored string or `BuiltInThemes.defaultID`; it never returns `nil` despite the optional type.
- **storage-observers-lazy**: `UserSettingsThemeStorage` MUST NOT observe either setting until `onExternalChange` is set to a non-nil closure, and MUST release both observers when it is set back to `nil`.
- **storage-observers-rebuilt**: Each assignment of a non-nil `onExternalChange` MUST replace both observers with fresh ones.
- **storage-change-any-writer**: Once hooked, `onExternalChange` MUST fire on every change to either setting — including a write made through this storage itself — not only on writes from outside the `ThemeStorage` seam.
- **storage-change-deferred**: `onExternalChange` MUST be delivered on the main dispatch queue after the new value has landed, not synchronously inside the write.
- **storage-change-no-initial**: Hooking `onExternalChange` MUST NOT invoke it for the values already stored.
- **storage-weak-owner**: The observers MUST hold the storage weakly, so a deallocated storage delivers no further callbacks.

### Convenience initialisers

- **store-default-init**: `ThemeStore()` MUST be equivalent to `ThemeStore(storage: UserSettingsThemeStorage())`.
- **manager-default-init**: On macOS, `ThemeManager()` MUST be equivalent to `ThemeManager(storage: UserSettingsThemeStorage(), appearanceDriver: AppKitAppearanceDriver(autoAppearance:))`, with an `autoAppearance` closure that returns `UserSettings.appearanceMode.currentValue.nsAppearance`, read each time the closure is called.
- **manager-default-reads-disk**: A theme id stored under `theme.active_theme_id` by an earlier build MUST be the `currentTheme` of a freshly created `ThemeManager()`.

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
| theme-engine-001 | syntax-role-vocabulary | `SyntaxRole.allCases` | 10 cases, raw values `keywords` … `comments` in declaration order |
| theme-engine-002 | syntax-style-defaults, syntax-style-shape | `SyntaxStyle(color: c)` | `bold == false`, `italic == false` |
| theme-engine-003 | override-key-spelling (test) | `SyntaxRole.keywords.overrideKey()`, `(bold: true)`, `(italic: true)`, `(bold: true, italic: true)` | `syntax.keywords`, `syntax.keywords.bold`, `syntax.keywords.italic`, `syntax.keywords.bold.italic` |
| theme-engine-004 | syntax-styles-read, override-key-spelling (test) | For every role × flag combination, a theme whose only override is `role.overrideKey(bold:italic:)` → c | `syntaxStyles == [role: SyntaxStyle(color: c, bold:, italic:)]` |
| theme-engine-005 | override-key-flag-order (test) | `roleOverrides = ["syntax.comments.italic.bold": c]` | `syntaxStyles == [.comments: SyntaxStyle(color: c, bold: true, italic: true)]` |
| theme-engine-006 | override-key-prefix, override-key-role, override-key-flag-vocabulary, override-key-flag-once, override-key-no-throw (test) | Each of `syntax.nope`, `syntax.keywords.underline`, `syntax.keywords.bold.bold`, `syntax`, `syntax.`, `keywords`, `syntaxkeywords`, `prefix.syntax.keywords` → c1, alone and beside `syntax.strings` → c2 | Alone: `syntaxStyles` empty. Beside: `[.strings: SyntaxStyle(color: c2)]` |
| theme-engine-007 | syntax-styles-empty | Theme with `roleOverrides = ["accent": c]` | `syntaxStyles` empty |
| theme-engine-008 | syntax-styles-tiebreak (test) | `syntax.keywords` → c1, `syntax.keywords.bold` → c2, `syntax.keywords.italic` → c3, in every insertion order | Always `[.keywords: SyntaxStyle(color: c3, italic: true)]` |
| theme-engine-009 | syntax-styles-invisible-to-roles (test) | Theme whose `roleOverrides` are one syntax key per role (10 keys) | `SemanticPalette.declares(r) == false` and `color(r) == derived(r)` for every `ThemeRole` |
| theme-engine-010 | syntax-styles-travel (test) | Theme carrying all four key shapes plus `accent`, JSON-encoded then decoded as `ColorTheme` | Decoded `roleOverrides` and `syntaxStyles` equal the original's; only `accent` is declared |
| theme-engine-011 | with-syntax-styles-replace, with-syntax-styles-preserve, with-syntax-styles-write (test) | Overrides `syntax.keywords.bold` → c1, `syntax.keywords.underline` → c8, `accent` → c9; `withSyntaxStyles([.keywords: SyntaxStyle(color: c2)])` | `syntax.*` keys are exactly `syntax.keywords`, `syntax.keywords.underline`; underline still c8; `syntaxStyles == [.keywords: SyntaxStyle(color: c2)]`; `accent` still c9 |
| theme-engine-012 | with-syntax-styles-clear (test) | Syntax keys plus `accent` → c9; `withSyntaxStyles([:])` | `syntaxStyles` empty; `roleOverrides == ["accent": c9]` |
| theme-engine-013 | with-syntax-styles-copy | `let t2 = t.withSyntaxStyles([.comments: s])` | `t.roleOverrides` unchanged |
| theme-engine-014 | import-bytes-entry, import-name-from-label, import-lock-flags, import-appearance (test) | Minimal theme, `label: "Acme Dark"`, `uiTheme: "vs-dark"` | `name == "Acme Dark"`, `appearance == .dark`, `isBuiltIn == false`, `isImported == false`, foreground `#D8DEE9FF`, background `#2E3440FF`, cursor `#FF00FFFF`, selection `#4C566AFF`, 16 ANSI colours, `hasValidPalette` |
| theme-engine-015 | import-ansi-order (test) | Minimal theme whose ANSI slot n is `#0n0000` | `ansi[0] == #000000FF`, `ansi[5] == #050000FF`, `ansi[15] == #0F0000FF` |
| theme-engine-016 | import-jsonc (test) | Minimal theme with comments and trailing commas vs its strict-JSON spelling | Identical palette, name, appearance and `roleOverrides` |
| theme-engine-017 | import-encodings (test) | Minimal theme as UTF-16, as UTF-16 JSONC, and as UTF-8 with BOM | Each parses to the UTF-8 result |
| theme-engine-018 | import-bytes-ignores-include (test) | Minimal theme plus `"include": "./base.json"` via `parse(_:label:uiTheme:)` | Same palette as without the key; no throw |
| theme-engine-019 | import-root-object (test) | Bytes `[1, 2, 3]` | Throws `notAnObject` |
| theme-engine-020 | import-syntax-error-passthrough | Bytes `{ "colors": ` (truncated) | Throws a `JSONSerialization` error, not a `VSCodeThemeParseError` |
| theme-engine-021 | import-colors-object (test) | `colors` missing, `null`, or `"x"` | Throws `missingColors` |
| theme-engine-022 | import-foreground-required, import-background-required, hex-invalid-absent (test) | `editor.foreground` missing; then `editor.background` missing; then `editor.foreground` `"red"` | `missingColor("editor.foreground")`; `missingColor("editor.background")`; `missingColor("editor.foreground")` |
| theme-engine-023 | import-validation-order | Both `editor.foreground` and `editor.background` missing | Throws `missingColor("editor.foreground")` |
| theme-engine-024 | import-ansi-complete (test) | Minimal theme minus `terminal.ansiGreen`; then minus several keys | `missingANSIColors(["terminal.ansiGreen"])`; then every missing key in slot order |
| theme-engine-025 | import-foreground-background-distinct (test) | Foreground and background both `#2E3440` | Throws `foregroundMatchesBackground` |
| theme-engine-026 | import-appearance, import-appearance-fallback (test) | Minimal theme (dark background) with `uiTheme` `vs`, `hc-light`, `vs-dark`, `hc-black`, `aurora`; then background `#FFFFFF` with `aurora` | `[.light, .light, .dark, .dark, .dark]`; then `.light` |
| theme-engine-027 | import-cursor (test) | Minimal theme without `editorCursor.foreground` | `cursor == foreground` |
| theme-engine-028 | import-selection-opaque (test) | Background `#011627`, `editor.selectionBackground` `#3392FF44` | `selection == #3392FF44 composited over #011627FF`; hex ends in `FF` |
| theme-engine-029 | import-selection-source, import-selection-fallback (test) | Only `editor.inactiveSelectionBackground` `#1D3B53`; then neither selection key | `#1D3B53FF`; then `background.blended(withFraction: 0.20, of: foreground)` |
| theme-engine-030 | import-role-overrides, import-role-overrides-present-only (test) | All six mapped keys present | `roleOverrides.count == 6`, each at its mapped role, each `declares(role)` |
| theme-engine-031 | import-no-other-roles (test) | `textLink.foreground`, `errorForeground`, `contrastBorder`, `editorWarning.foreground` present, no mapped key | `roleOverrides` empty; `accent`, `danger`, `border`, `warning`, `windowBackground`, `primaryText`, `selection` undeclared |
| theme-engine-032 | hex-forms (test) | fg `#ABCDEF12`, bg `123456`, cursor `#F0A`, `focusBorder` `#1234`, `input.background` `ABCDEF` | `#ABCDEF12`, `#123456FF`, `#FF00AAFF`, outline `#11223344`, controlBackground `#ABCDEFFF` |
| theme-engine-033 | hex-invalid-absent (test) | `editorCursor.foreground` `null`, a mapped role key as an array or a number | `cursor == foreground`; `roleOverrides` empty; no throw |
| theme-engine-034 | token-scope-forms (test) | Same rules as `scope: ["a", "b"]` and as `scope: "a, b"` | Identical `syntaxStyles` |
| theme-engine-035 | token-specificity (test) | Rules `keyword` → `#111111` and `keyword.control` → `#222222`, in both orders | `keywords` colour `#222222FF` both times |
| theme-engine-036 | token-tiebreak (test) | Two `keyword.control` rules, `#111111` then `#222222` bold | `keywords` = `#222222FF` + bold |
| theme-engine-037 | token-selector-clean (test) | `meta.tag entity.name.function` → c1 and `entity.name` → `#111111`; then the descendant rule alone | `commands` = `#111111FF`; then no `commands` style |
| theme-engine-038 | token-selector-clean (test) | `scope: "meta.tag entity.name.function, constant.numeric"` → `#333333` | `numbers` = `#333333FF`; no `commands` style |
| theme-engine-039 | token-emphasis (test) | `fontStyle` `italic`, `bold italic`, `italic bold`, `bold`, `underline`, `normal`, `regular`, `bold underline`, empty, absent on `#C792EA` | `+italic`, `+bold+italic`, `+bold+italic`, `+bold`, plain, plain, plain, `+bold`, plain, plain |
| theme-engine-040 | token-scope-chain, token-chain-first-match (test) | Only `support.type` → `#FFCB8B`; then `entity.name.type` → `#ADDB67` and `support.type` → `#FFCB8B` | `types` = `#FFCB8BFF`; then `#ADDB67FF` |
| theme-engine-041 | token-chain-first-match | Rules `entity` → c1 and `support.type` → c2 | `types` = c1 |
| theme-engine-042 | token-rule-usable, hex-shared (test) | `keyword.control` with foreground `"nope"`, with only `fontStyle`, with foreground `42`, each beside `keyword` → `#111111`; then foreground `#ABC` on `string.quoted.double` | `keywords` = `#111111FF` each time; `strings` = `#AABBCCFF` |
| theme-engine-043 | token-rules-source, token-no-throw, token-unmatched-role (test) | `tokenColors` absent, `"keyword.control"`, `{ "scope": "keyword" }`, `null`, `[]` | No throw; `syntaxStyles` empty; palette identical to the minimal theme |
| theme-engine-044 | token-stored-as-overrides (test) | Minimal theme with a `comment.line` rule vs without | Palette identical; non-`syntax.` overrides identical; `syntaxStyles` keys == `[.comments]` |
| theme-engine-045 | import-file-entry, include-merge-colors (test) | `variant.json` `{"include": "./base.json", "colors": {"editor.background": "#111111"}}`; `base.json` is the minimal theme | foreground `#D8DEE9FF`, background `#111111FF`, cursor `#FF00FFFF`, 16 ANSI |
| theme-engine-046 | include-merge-tokens (test) | Base and variant each with a `comment.line` rule; variant also `keyword.control` → `#222222` | `comments` from the variant (`#333333FF`); `keywords` `#222222FF` |
| theme-engine-047 | include-cycle, include-depth-bound (test) | `a.json` includes `./b.json`, `b.json` includes `./a.json` | Throws `includeChainTooDeep(limit: 8)` |
| theme-engine-048 | include-containment, import-file-default-root (test) | `themes/variant.json` includes `../outside/secret.json`, no `containedIn` | Throws `ExtensionResourcePathError` |
| theme-engine-049 | include-resolve (test) | Same files, `containedIn:` the parent directory | Parses; foreground `#D8DEE9FF` |
| theme-engine-050 | include-detect, import-file-entry (test) | Minimal theme on disk with no `include` | Same palette as `parse(_:label:uiTheme:)` of the same bytes |
| theme-engine-051 | include-merge-other, include-consumed | Base `{"x": 1, ...}`, variant `{"include": "./base.json", "x": 2}` | Merged document has `x == 2` and no `include` key |
| theme-engine-052 | import-file-errors | `parse(contentsOf:)` on a path that does not exist | Throws the file-read error; nothing parsed |
| theme-engine-053 | store-import, store-import-locked (test) | `ThemeStore(storage: InMemoryThemeStorage())`, minimal theme file, `importVSCodeTheme(label: "Acme Dark", uiTheme: "vs-dark")` | Returned `name == "Acme Dark"`, `isImported`, `isLocked`, `!isEditable`; `customThemes.map(\.id) == [imported.id]`; `allThemes` contains it |
| theme-engine-054 | store-import-failure | `importVSCodeTheme` on a file whose `colors` is missing | Throws `missingColors`; `customThemes` unchanged |
| theme-engine-055 | store-import-no-rename | Import the same file twice with the same label | Two custom themes, both named the label, with different ids |
| theme-engine-056 | storage-active-key, storage-legacy-compatible (test) | Defaults hold `theme.active_theme_id` = Dracula's id written the pre-seam way | `UserSettingsThemeStorage().activeThemeID == BuiltInThemes.dracula.id` |
| theme-engine-057 | storage-legacy-compatible (test) | `storage.activeThemeID = BuiltInThemes.nord.id` | `defaults.string(forKey: "theme.active_theme_id") == nord.id` |
| theme-engine-058 | storage-nil-write, storage-read-non-nil | `storage.activeThemeID = nil`, then read | Reads `BuiltInThemes.defaultID` |
| theme-engine-059 | storage-custom-themes-key | `storage.customThemes = [t]`, then read `UserSettings.customThemes.value` | `[t]` |
| theme-engine-060 | storage-change-any-writer, storage-change-deferred (test) | `ThemeManager` over this storage; write `UserSettings.activeThemeID.value = dracula.id` directly | After the main queue drains, `didChangeNotification` fired and `currentTheme.id == dracula.id` |
| theme-engine-061 | storage-change-any-writer (test) | Rewrite `UserSettings.customThemes` with the active custom theme renamed | Notification fired; `currentTheme.name` is the new name |
| theme-engine-062 | storage-change-any-writer (test) | `manager.selectTheme(id: dracula.id)` | Exactly one `didChangeNotification` (the storage callback fires, `ThemeManager.reload()` de-duplicates) |
| theme-engine-063 | storage-observers-lazy, storage-change-no-initial | Set `onExternalChange` to a counter, drain the main queue, then set it to `nil` and write both settings | Counter stays 0 |
| theme-engine-064 | store-default-init, manager-default-init, manager-default-reads-disk (test) | Defaults hold `theme.active_theme_id` = Gruvbox Dark's id; create `ThemeManager()` | `currentTheme.id == BuiltInThemes.gruvboxDark.id` |

## Edge Cases

- **Empty or missing theme data**: `parse(_:label:uiTheme:)` of empty bytes MUST throw the `JSONSerialization` error; a document `{}` MUST throw `missingColors`; `"colors": {}` MUST throw `missingColor("editor.foreground")`.
- **A variant file on its own**: a per-variant file that restates a few colours and relies on `include` MUST throw `missingColor("editor.foreground")` when parsed from bytes, and MUST parse when read with `parse(contentsOf:)` — which is why production callers use the file entry point.
- **Empty or non-string include**: `"include": ""`, `"include": 3` or `"include": null` MUST be treated as no include (MUST).
- **Include one level too deep**: a chain of 9 files (8 hops) MUST parse; a 10th file (9th hop) MUST throw `includeChainTooDeep(limit: 8)` (MUST).
- **Non-object colors in one link of a chain**: when the including file's `colors` is not an object but the base's is, the merged `colors` MUST be the base's (the non-object value is replaced by the merge); the same holds for a non-array `tokenColors` (MUST).
- **Symlinked include**: containment is decided on the symlink-resolved path by `ExtensionResourcePath`; a symlink that lands outside the root MUST throw `escapesExtensionDirectory` (MUST).
- **Unreadable optional colour**: a named colour, a 5- or 7-digit value, or a non-string for any optional key MUST count as absent and fall back (cursor → foreground, selection → blend, role → no override) (MUST).
- **Translucent required colours**: `editor.foreground` and `editor.background` MUST be stored with their declared alpha; only selection is composited (MUST).
- **Foreground equal to background only after normalisation**: `#FFF` and `#FFFFFFFF` MUST be treated as equal and throw `foregroundMatchesBackground` (MUST).
- **tokenColors entry with a `scope` array holding `null`**: the `null` element MUST be skipped and the entry's other selectors kept (MUST).
- **Scope absent**: an entry with no `scope` (VS Code's "applies to everything") MUST produce no rule, so it cannot falsely match the first role queried (MUST).
- **No rule matches any role**: `syntaxStyles` MUST be empty and no `syntax.` key written (MUST).
- **Hand-edited duplicate syntax keys**: two keys for one role MUST resolve to the lexicographically greatest; `withSyntaxStyles` MUST remove both (MUST).
- **Rejected `syntax.` key**: it MUST be preserved by `withSyntaxStyles` and ignored by `syntaxStyles` and `SemanticPalette` (MUST).
- **Concurrent access**: the importer has no shared state, so concurrent parses on different threads MUST NOT interfere (MUST). `ThemeStore` and `UserSettingsThemeStorage` are `@MainActor`, so their calls are serialised by the main actor and cannot interleave (MUST).
- **Write followed by callback**: a write through `UserSettingsThemeStorage` MUST produce an `onExternalChange` callback on a later main-queue turn; a consumer that also reacts synchronously sees two notifications unless it de-duplicates, as `ThemeManager.reload()` does (MUST).
- **Storage never hooked**: a `ThemeStore()` used without a `ThemeManager` MUST allocate no observers (MUST).
- **Corrupt stored themes**: what `UserSettings.customThemes` returns when the stored JSON does not decode is owned by the active `SettingsStorageProvider` (see [Settings Storage](agentictoolkit://recipes/settings-storage)); this storage returns whatever the setting holds without further validation (MUST).
- **Large theme file**: the importer MUST read the whole file into memory with no size cap and no timeout (MUST); on the main actor via `importVSCodeTheme` this blocks the main thread for the read.
- **Cancellation**: no parse can be cancelled once started (MUST).
- **Error states**: every failure MUST surface as a thrown error — `VSCodeThemeParseError`, `ExtensionResourcePathError`, a file-read error or a `JSONSerialization` error — and nothing is stored (MUST).
- **Offline or disconnected state**: not applicable; the component reads local files and local settings only and performs no network I/O.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `data` | `Data` | — | Raw theme bytes for `parse(_:label:uiTheme:)`; JSONC, UTF-8/UTF-16, optional BOM. |
| `url` | `URL` | — | Theme file for `parse(contentsOf:…)` and `importVSCodeTheme`; the caller vouches for it (not containment-checked). |
| `label` | `String` | — | The manifest entry's `label`; becomes `ColorTheme.name`. |
| `uiTheme` | `String` | — | The manifest entry's `uiTheme` (`vs`, `vs-dark`, `hc-light`, `hc-black`); decides appearance. |
| `containedIn` | `URL?` | `nil` (the theme file's directory) | Root every `include` must stay inside; the themes contribution point passes the extension's folder. |
| `maximumIncludeDepth` | `Int` (private constant) | `8` | Include hops followed before `includeChainTooDeep`. |
| `theme.custom_themes` | `UserSettings` key, `[ColorTheme]` as JSON | `[]` | Where `UserSettingsThemeStorage` keeps custom and imported themes. |
| `theme.active_theme_id` | `UserSettings` key, `String` | `BuiltInThemes.defaultID` | The selected theme's id. |
| `UserSettings.appearanceMode` | `UserSetting` | host-defined | Read by `ThemeManager()`'s `autoAppearance` closure for `.auto` themes. |
| `onExternalChange` | `(() -> Void)?` | `nil` | Callback `ThemeManager` installs; setting it allocates the two setting observers. |
| `UserSettings.shared` provider | injected `SettingsStorageProvider` | host-configured | Backend both keys are persisted in. |

## Deep Linking

Not applicable: the sources define no URL scheme, route or deep-link handler; the engine is reached only through Swift API calls.

## Localization

Not applicable: the sources contain no user-facing strings. `VSCodeThemeParseError` has no `LocalizedError` conformance, so its `localizedDescription` is Foundation's generic English wording for the case (see import-error-descriptions); the theme name is the manifest's `label`, passed through verbatim.

## Accessibility Options

Not applicable: the engine renders nothing and reads no Reduce Motion, Increase Contrast or Differentiate Without Color setting; only `ThemeManager()` reads `UserSettings.appearanceMode` for `.auto` themes.

## Feature Flags

Not applicable: no source file reads a feature flag; every code path is unconditional.

## Analytics

Not applicable: the sources emit no analytics events.

## Privacy

Not applicable: the engine handles colour themes and a theme id only — no personal data, credentials or tokens — and transmits nothing off the device.

## Logging

Not applicable: none of the four source files logs; every failure is reported to the caller as a thrown error instead.

## Platform Notes

- **SwiftUI**: The source is Swift and platform-neutral except `ThemeManager+UserSettings.swift`. `SyntaxRoleOverrides.swift` and `VSCodeThemeImporter.swift` are Foundation-only; `UserSettingsThemeStorage.swift` depends on ATK's `UserSettings` (`UserSettings+Theme.swift` declares the two keys) and `UserSettingObserver`, which delivers on `DispatchQueue.main` after `dropFirst()`. A SwiftUI host holds a `ThemeManager` and observes `ThemeManager.didChangeNotification`; nothing here is SwiftUI-specific.
- **Compose**: Port `SyntaxRole` as a Kotlin `enum class` with the same lowercase names and `SyntaxStyle` as a `data class`. Parse with `kotlinx.serialization.json.Json { isLenient = true; allowTrailingComma = true; allowComments = true }` into a `JsonObject` and read by key, as the source does, rather than a strict `@Serializable` model. Resolve includes with `java.nio.file.Path.resolve(...).toRealPath()` plus a `startsWith(root)` check. Back `ThemeStorage` with Jetpack `DataStore<Preferences>` under the same two keys; `onExternalChange` becomes collecting the DataStore `Flow` with `drop(1)`, dispatched on `Dispatchers.Main`.
- **React/Web**: Port the importer as a pure TypeScript module over `JSON.parse` after a JSONC strip (`jsonc-parser`'s `parse` with `allowTrailingComma`); `Map` iteration order is insertion order, but keep the lexicographic tie-break so the result does not depend on it. File access and include containment only exist in Node/Electron (`fs.readFileSync`, `path.resolve` + `fs.realpathSync` + a prefix check); a browser port accepts bytes only, like `parse(_:label:uiTheme:)`. Persist with `localStorage` under the same keys; the cross-tab `storage` event is the `onExternalChange` equivalent, and it does not fire in the writing tab — unlike the source, which fires for its own writes too.
- **AppKit / UIKit**: This is the source's own platform. `ThemeManager()` (macOS target) installs `AppKitAppearanceDriver` with `autoAppearance` reading `UserSettings.appearanceMode.currentValue.nsAppearance`; a UIKit port swaps in a driver that sets `overrideUserInterfaceStyle` on the window scene. `ThemeContributionPoint.swift` is the production caller of `parse(contentsOf:…containedIn:)`, and `ThemeSettingsPanelViewController` is where users duplicate an imported theme to edit it.
- **WinUI 3**: Port the model as C# `record` types (`SyntaxStyle(Color, bool Bold, bool Italic)`) and `SyntaxRole` as an `enum` with a lowercase-name mapping. Parse with `System.Text.Json.JsonDocument.Parse(bytes, new JsonDocumentOptions { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true })` and walk `JsonElement`s by key (`TryGetProperty`, `ValueKind`) to keep the source's "read by key, absent on wrong type" rule; detect UTF-16 with `StreamReader`'s BOM detection before parsing. Read files with `Windows.Storage.StorageFile.GetFileFromPathAsync` + `FileIO.ReadBufferAsync`, or `System.IO.File.ReadAllBytes` in an unpackaged app; do include containment with `Path.GetFullPath` plus a case-insensitive `StartsWith(root)` check, resolving reparse points with `FileSystemInfo.ResolveLinkTarget(true)`. Where the source is synchronous, expose `Task<ColorTheme> ParseAsync(...)` so the UI thread is not blocked. Back `ThemeStorage` with `Windows.Storage.ApplicationData.Current.LocalSettings.Values["theme.active_theme_id"]` (a string) and a JSON string (or a `LocalFolder` file, since a settings value is capped at 8 KB) for `theme.custom_themes`; implement change notification with `INotifyPropertyChanged` on a storage class and dispatch the callback through `DispatcherQueue.TryEnqueue` to match the source's deferred main-queue delivery. Expose the catalog as an `ObservableCollection<ColorTheme>` for a `ListView` theme picker.

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
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from AgenticToolkit Core/Theme and the macOS ThemeManager initialiser. |
