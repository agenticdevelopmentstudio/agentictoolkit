<!-- leaf: implement-general-2/theme-engine--part-3 · source: theme-engine.md -->

# Theme Engine — continued (part 3)

**Rules** (cite as `implement-general-2/theme-engine--part-3#<slug>`):

- `import-appearance` MUST
- `import-appearance-fallback` MUST
- `import-cursor` MUST
- `import-selection-source` MUST
- `import-selection-opaque` MUST
- `import-selection-fallback` MUST
- `import-role-overrides` MUST
- `import-role-overrides-present-only` MUST
- `import-no-other-roles` MUST
- `hex-forms` MUST
- `hex-invalid-absent` MUST
- `hex-shared` MUST
- `token-rules-source` MUST
- `token-rule-usable` MUST
- `token-scope-forms` MUST
- `token-selector-clean` MUST
- `token-emphasis` MUST
- `token-match` MUST
- `token-specificity` MUST
- `token-tiebreak` MUST
- `token-scope-chain` MUST
- `token-chain-first-match` MUST
- `token-unmatched-role` MUST
- `token-no-throw` MUST
- `token-stored-as-overrides` MUST
- `include-detect` MUST
- `include-resolve` MUST
- `include-containment` MUST
- `include-depth-bound` MUST
- `include-cycle` MUST
- `include-merge-colors` MUST
- `include-merge-tokens` MUST
- `include-merge-other` MUST
- `include-consumed` MUST
- `store-import` MUST
- `store-import-locked` MUST
- `store-import-failure` MUST
- `store-import-no-rename` MUST
- `importer-isolation` MUST
- `importer-no-limits` MUST
- `store-isolation` MUST
- `storage-isolation` MUST

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
- **include-resolve**: An include path MUST be resolved relative to the including file's directory and MUST stay inside the containment root, via `ExtensionResourcePath.resolve(_:relativeTo:containedIn:)` (see Extension Resource Path).
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

