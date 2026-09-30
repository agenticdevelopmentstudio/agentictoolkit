<!-- leaf: implement-general-2/theme-engine--part-5 · source: theme-engine.md -->

# Theme Engine — continued (part 5)

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
