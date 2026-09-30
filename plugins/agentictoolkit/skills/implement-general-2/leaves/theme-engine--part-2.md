<!-- leaf: implement-general-2/theme-engine--part-2 · source: theme-engine.md -->

# Theme Engine — continued (part 2)

**Rules** (cite as `implement-general-2/theme-engine--part-2#<slug>`):

- `syntax-role-vocabulary` MUST
- `syntax-role-names` MUST
- `syntax-style-shape` MUST
- `syntax-style-defaults` MUST
- `syntax-value-semantics` MUST
- `override-key-spelling` MUST
- `override-key-flag-order` MUST
- `override-key-prefix` MUST
- `override-key-role` MUST
- `override-key-flag-vocabulary` MUST
- `override-key-flag-once` MUST
- `override-key-no-throw` MUST
- `override-key-collision-free` MUST
- `syntax-styles-read` MUST
- `syntax-styles-empty` MUST
- `syntax-styles-tiebreak` MUST
- `syntax-styles-invisible-to-roles` MUST
- `syntax-styles-travel` MUST
- `with-syntax-styles-replace` MUST
- `with-syntax-styles-preserve` MUST
- `with-syntax-styles-write` MUST
- `with-syntax-styles-clear` MUST
- `with-syntax-styles-copy` MUST
- `syntax-grammar-shared` MUST
- `import-bytes-entry` MUST
- `import-jsonc` MUST
- `import-encodings` MUST
- `import-bytes-ignores-include` MUST
- `import-file-entry` MUST
- `import-file-default-root` MUST
- `import-file-url-precondition` MUST
- `import-name-from-label` MUST
- `import-lock-flags` MUST
- `import-validation-order` MUST
- `import-syntax-error-passthrough` MUST
- `import-root-object` MUST
- `import-colors-object` MUST
- `import-foreground-required` MUST
- `import-background-required` MUST
- `import-foreground-background-distinct` MUST
- `import-ansi-complete` MUST
- `import-ansi-order` MUST
- `import-file-errors` MUST
- `import-error-descriptions` MUST

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
- **import-encodings**: Both entry points MUST accept UTF-8, UTF-8 with a byte-order mark, and UTF-16 payloads (including UTF-16 JSONC), producing the same theme as the UTF-8 spelling, by decoding through `JSONCPreprocessor.jsonObject(from:)` (see Foundation JSON).
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

