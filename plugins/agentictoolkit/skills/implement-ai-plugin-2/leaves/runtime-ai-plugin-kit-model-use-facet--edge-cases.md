<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-model-use-facet--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-model-use-facet.md -->

# ModelUseFacet

**Rules** (cite as `implement-ai-plugin-2/runtime-ai-plugin-kit-model-use-facet--edge-cases#<slug>`):

- `empty-text-no-capabilities` MUST — facets(text: "", capabilities: []) (the default) MUST return an empty set — zero words are produced by tokenizing an …
- `text-with-no-letters-or-numbers` MUST — facets(text: "--- ... !!!") MUST return an empty set — tokenization on "not a letter and not a number" yields zero …
- `unrecognized-capability-string` MUST — A capabilities array containing a string ModelCapability.reports does not recognize for any case (e.g. "beta-feature") …
- `boundary-single-matching-character-run` MUST — A word that is exactly one of a facet's prefixes (e.g. the word "cod" alone) MUST count as evidence …
- `redundant-evidence` MUST — Text that satisfies both the word-prefix and the phrase evidence for the same facet (e.g. "coding, code generation" for …
- `capability-and-text-both-point-to-the-same-facet` MUST — A model whose capabilities report tools and whose text also matches an .agents keyword MUST still show .agents exactly …
- `non-english-or-transliterated-evidence` MUST — wordPrefixes and phrases are fixed English-token lists (see Localization); a description written only in another …
- `concurrent-access` MUST — ModelUseFacet and every function in this file are pure and hold no shared mutable state, so concurrent calls from …

## Edge Cases

- **Empty text, no capabilities.** `facets(text: "", capabilities: [])` (the
  default) MUST return an empty set — zero words are produced by tokenizing
  an empty string, and the empty `capabilities` array reports nothing.
- **Text with no letters or numbers.** `facets(text: "--- ... !!!")` MUST
  return an empty set — tokenization on "not a letter and not a number"
  yields zero words, and phrase matching finds no substring hits either.
- **Unrecognized capability string.** A capabilities array containing a
  string `ModelCapability.reports` does not recognize for any case (e.g.
  `"beta-feature"`) MUST be silently ignored — it implies no facet and MUST
  NOT raise an error.
- **Boundary: single matching character run.** A word that is exactly one of
  a facet's prefixes (e.g. the word `"cod"` alone) MUST count as evidence
  (`"cod".hasPrefix("cod") == true`); this is the minimum-length case of
  `word-prefix-anchoring`, not a special-cased boundary in the source.
- **Redundant evidence.** Text that satisfies both the word-prefix and the
  phrase evidence for the same facet (e.g. `"coding, code generation"` for
  `.coding`) MUST still yield that facet exactly once — `found` is a `Set`,
  so re-inserting the same case is a no-op.
- **Capability and text both point to the same facet.** A model whose
  capabilities report `tools` and whose text also matches an `.agents`
  keyword MUST still show `.agents` exactly once, via the capability check's
  `continue` short-circuit — the word/phrase checks for that facet are never
  reached, so this cannot produce a duplicate or a conflict.
- **Non-English or transliterated evidence.** `wordPrefixes` and `phrases`
  are fixed English-token lists (see Localization); a description written
  only in another language MUST produce an empty set for facets whose only
  matching keywords are English, exactly as if the model had no description
  at all — this is a fact about the fixed evidence lists, not a crash or
  undefined behavior.
- **Concurrent access.** `ModelUseFacet` and every function in this file are
  pure and hold no shared mutable state, so concurrent calls from multiple
  threads, tasks, or actors on the same or different inputs MUST behave
  identically to sequential calls — this is applicable (the type is read
  from AppKit UI code and could be read from background contexts) and is
  safe by construction, not merely untested.
- **Error states (dependency failure).** Not applicable: `ModelUseFacet.swift`
  makes no network call, file-system call, or database call of any kind — it
  operates only on the `String`/`[String]` arguments and the
  already-in-memory `AIModelCatalog.ResolvedModel` passed to it, so there is
  no dependency that can be "unavailable" or "return an error" for this file
  to handle.
- **Offline or disconnected state.** Not applicable, for the same reason:
  this file performs no network I/O. Whether the `ResolvedModel` it is given
  was itself fetched online or offline is a concern of its caller
  (`AIModelCatalog`, `AIPluginDescriptor`), not of `ModelUseFacet`.
