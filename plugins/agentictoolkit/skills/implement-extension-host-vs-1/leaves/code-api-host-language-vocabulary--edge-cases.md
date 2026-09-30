<!-- leaf: implement-extension-host-vs-1/code-api-host-language-vocabulary--edge-cases · source: extension-host-vs-code-api-host-language-vocabulary.md -->

# HostLanguageVocabulary

**Rules** (cite as `implement-extension-host-vs-1/code-api-host-language-vocabulary--edge-cases#<slug>`):

- `null-empty-contributions` MUST — when contributionPoint.contributedLanguageIdentifiers is empty (no extension has contributed a language), …
- `boundary-values` MUST — MUST NOT apply a maximum length or count to languageIdentifiers; any number of contributed identifiers, including one …
- `concurrent-access` MUST — HostLanguageVocabulary is @MainActor, so every read of languageIdentifiers and every read of the stored …

## Edge Cases

- **Null/empty contributions**: when `contributionPoint.contributedLanguageIdentifiers`
  is empty (no extension has contributed a language), `languageIdentifiers`
  MUST still return the full built-in set plus the default identifier; it
  MUST NOT return an empty array (`default-language-inclusion`, `hlv-002`).
- **Boundary values**: MUST NOT apply a maximum length or count to
  `languageIdentifiers`; any number of contributed identifiers, including
  one that duplicates every built-in identifier, MUST be accepted and
  deduplicated the same way a single duplicate is (`contributed-deduplication`).
- **Concurrent access**: `HostLanguageVocabulary` is `@MainActor`, so every
  read of `languageIdentifiers` and every read of the stored
  `contributionPoint` executes serialized on the main actor; concurrent
  calls from other isolation domains MUST NOT compile without an `await`
  hop, and the type defines no additional locking because the actor
  already serializes access (`main-actor-isolation`, `non-sendable-declaration`).
- **Error states**: not applicable in the throwing or `Optional`-unwrapping
  sense — `languageIdentifiers` is a synchronous, non-throwing computed
  property with no failure path; every input it consumes
  (`CodeLanguage.allLanguages`, `CodeLanguage.default`,
  `contributionPoint.contributedLanguageIdentifiers`) is already a plain,
  non-optional `[String]` or `String` by the time this type reads it.
- **Offline/disconnected**: not applicable — this component performs no
  networking and touches no filesystem; `CodeLanguage.allLanguages` is
  linked-in package data and `contributionPoint`'s contributions were
  already parsed and applied before this type reads them.
