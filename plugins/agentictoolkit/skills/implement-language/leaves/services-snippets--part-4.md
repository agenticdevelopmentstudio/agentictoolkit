<!-- leaf: implement-language/services-snippets--part-4 · source: language-services-snippets.md -->

# Language Services Snippets — continued (part 4)

**Rules** (cite as `implement-language/services-snippets--part-4#<slug>`):

- `decision` MUST — prefix's array handling drops a bad element and keeps the rest (compactMap), while body's array handling (as? [String]) …

## Design Decisions

**Decision**: `prefix`'s array handling drops a bad element and keeps the rest (`compactMap`), while `body`'s array handling (`as? [String]`) rejects the whole entry on any bad element.
**Rationale**: the source's own doc comment on `prefixes(from:)` describes this as "the same string-or-array tolerance `body(from:)` has carried all along, applied to the other half of the pair," which reads as claiming symmetry with `body`'s leniency; `SnippetFileTests.missingOrWrongTypedBodyIsSkipped`'s `"Mixed array body": ["line", 2]` case proves the two are not symmetric — `body` rejects that whole entry rather than keeping `"line"`. A port MUST implement the two independently rather than trusting the comment's implied parity.
**Approved**: pending

**Decision**: `SnippetFile.parse(_:extensionIdentifier:)` sorts by name (root object keys), while `SnippetStore.snippets(forLanguage:)` preserves an extension's own file-declaration order and `prefixes(from:)` preserves an entry's own array-declaration order.
**Rationale**: a deserialized JSON object has no order of its own, so `SnippetFile` imposes a stable one (sorted keys) to keep a completion list from reshuffling between launches; an array, by contrast, already has a real declared order — the manifest's entry list, or a `prefix` array's element order — and the source deliberately preserves that order rather than re-sorting it, because it is information the extension author wrote and not an artifact of decoding.
**Approved**: pending

**Decision**: `SnippetStore.apply(_:from:at:)` can throw per its `ContributionPoint` conformance, but every path that can fail inside it — path resolution, file read, JSON/JSONC parse — is caught locally and turned into a `SnippetFileFailure` instead of being rethrown.
**Rationale**: `SnippetStore.swift`'s own doc comment states the type "never throws in practice," because one bad snippet file must not cost the extension its other, good snippet files (apply-per-entry-error-isolation); `throws` remains in the signature only because `ContributionPoint` declares it and because a future whole-extension failure — one that is not per-file — would have somewhere to go.
**Approved**: pending

**Decision**: `snippetsByExtension[identifier] = byLanguage` is assigned unconditionally after the per-entry loop, even when every entry failed and `byLanguage` is empty, rather than being skipped when nothing was read.
**Rationale**: per `SnippetStore.swift`'s own comment, an extension whose files all parsed to nothing usable is still an extension that contributed; guarding the assignment on `byLanguage.isEmpty` would not change what `snippets(forLanguage:)` returns (`?? []` already covers a missing key) but would leave one more state — "applied but not recorded" versus "applied and recorded empty" — for a reader to reason about for no behavioral benefit.
**Approved**: pending
