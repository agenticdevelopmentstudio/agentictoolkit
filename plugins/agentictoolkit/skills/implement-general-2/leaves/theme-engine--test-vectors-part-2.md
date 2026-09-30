<!-- leaf: implement-general-2/theme-engine--test-vectors-part-2 · source: theme-engine.md -->

# Theme Engine — Conformance Test Vectors (part 2)

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
