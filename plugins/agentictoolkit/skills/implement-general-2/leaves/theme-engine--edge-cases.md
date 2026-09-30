<!-- leaf: implement-general-2/theme-engine--edge-cases · source: theme-engine.md -->

# Theme Engine

**Rules** (cite as `implement-general-2/theme-engine--edge-cases#<slug>`):

- `empty-or-missing-theme-data` MUST — parse(_:label:uiTheme:) of empty bytes MUST throw the JSONSerialization error; a document {} MUST throw missingColors; …
- `a-variant-file-on-its-own` MUST — a per-variant file that restates a few colours and relies on include MUST throw missingColor("editor.foreground") when …
- `empty-or-non-string-include` MUST — "include": "", "include": 3 or "include": null MUST be treated as no include (MUST).
- `include-one-level-too-deep` MUST — a chain of 9 files (8 hops) MUST parse; a 10th file (9th hop) MUST throw includeChainTooDeep(limit: 8) (MUST).
- `non-object-colors-in-one-link-of-a-chain` MUST — when the including file's colors is not an object but the base's is, the merged colors MUST be the base's (the …
- `symlinked-include` MUST — containment is decided on the symlink-resolved path by ExtensionResourcePath; a symlink that lands outside the root …
- `unreadable-optional-colour` MUST — a named colour, a 5- or 7-digit value, or a non-string for any optional key MUST count as absent and fall back (cursor …
- `translucent-required-colours` MUST — editor.foreground and editor.background MUST be stored with their declared alpha; only selection is composited (MUST).
- `foreground-equal-to-background-only-after-normalisation` MUST — #FFF and #FFFFFFFF MUST be treated as equal and throw foregroundMatchesBackground (MUST).
- `tokencolors-entry-with-a-scope-array-holding-null` MUST — the null element MUST be skipped and the entry's other selectors kept (MUST).
- `scope-absent` MUST — an entry with no scope (VS Code's "applies to everything") MUST produce no rule, so it cannot falsely match the first …
- `no-rule-matches-any-role` MUST — syntaxStyles MUST be empty and no syntax. key written (MUST).
- `hand-edited-duplicate-syntax-keys` MUST — two keys for one role MUST resolve to the lexicographically greatest; withSyntaxStyles MUST remove both (MUST).
- `rejected-syntax-key` MUST — it MUST be preserved by withSyntaxStyles and ignored by syntaxStyles and SemanticPalette (MUST).
- `concurrent-access` MUST — the importer has no shared state, so concurrent parses on different threads MUST NOT interfere (MUST). ThemeStore and …
- `write-followed-by-callback` MUST — a write through UserSettingsThemeStorage MUST produce an onExternalChange callback on a later main-queue turn; a …
- `storage-never-hooked` MUST — a ThemeStore() used without a ThemeManager MUST allocate no observers (MUST).
- `corrupt-stored-themes` MUST — what UserSettings.customThemes returns when the stored JSON does not decode is owned by the active …
- `large-theme-file` MUST — the importer MUST read the whole file into memory with no size cap and no timeout (MUST); on the main actor via …
- `cancellation` MUST — no parse can be cancelled once started (MUST).
- `error-states` MUST — every failure MUST surface as a thrown error — VSCodeThemeParseError, ExtensionResourcePathError, a file-read error or …

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
- **Corrupt stored themes**: what `UserSettings.customThemes` returns when the stored JSON does not decode is owned by the active `SettingsStorageProvider` (see Settings Storage); this storage returns whatever the setting holds without further validation (MUST).
- **Large theme file**: the importer MUST read the whole file into memory with no size cap and no timeout (MUST); on the main actor via `importVSCodeTheme` this blocks the main thread for the read.
- **Cancellation**: no parse can be cancelled once started (MUST).
- **Error states**: every failure MUST surface as a thrown error — `VSCodeThemeParseError`, `ExtensionResourcePathError`, a file-read error or a `JSONSerialization` error — and nothing is stored (MUST).
- **Offline or disconnected state**: not applicable; the component reads local files and local settings only and performs no network I/O.
