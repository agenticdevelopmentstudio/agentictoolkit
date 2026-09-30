<!-- leaf: implement-extension-host-vs-1/code-api-host-language-vocabulary--part-2 · source: extension-host-vs-code-api-host-language-vocabulary.md -->

# HostLanguageVocabulary — continued (part 2)

## Design Decisions

- **Decision**: built-in identifiers are listed before contributed
  identifiers, and the built-in loop's own duplicate guard is kept even
  though nothing in `CodeLanguage.allLanguages` can trigger it today.
  **Rationale**: the source's own doc comment states that an extension
  contributing an id CodeEditLanguages already has is adding a
  file-extension claim to an existing language, not declaring a new one,
  so the built-in entry — the one that was there first — must win the
  position; the guard costs one set insertion this code already pays for
  the later loops and guards against a future duplicate appearing in a
  third-party array this codebase does not control.
  **Approved**: pending
- **Decision**: `languageIdentifiers` is built from `CodeLanguage.id`,
  never `CodeLanguage.tsName`.
  **Rationale**: the source's doc comment states `tsName` names the
  tree-sitter grammar, not the language, and building on it would return
  duplicates while losing three languages `id` keeps distinct (JSX and
  JavaScript, TSX and TypeScript, an OCaml interface and OCaml each share
  one grammar).
  **Approved**: pending
- **Decision**: the returned identifiers are this host's own vocabulary
  (for example `cSharp`, `jsx`, `tsx`, `objc`, `bash`, `goMod`, `jsdoc`,
  `markdownInline`, `regex`), not a translation into whatever spelling a
  real VS Code installation uses for the same language.
  **Rationale**: the source's doc comment states upstream's push-and-cache
  design exists to amortize a process boundary this host does not have,
  not to translate vocabulary, and an extension asking what languages this
  editor knows wants this host's actual ids, not VS Code's.
  **Approved**: pending
- **Decision**: `languageIdentifiers` is a computed property, never cached
  behind a stored field.
  **Rationale**: `contributionPoint`'s contributions can change between
  calls as extensions load and unload, and the source's own doc comment
  ties this directly to "Ruling 16," which requires a fresh array on every
  call.
  **Approved**: pending
