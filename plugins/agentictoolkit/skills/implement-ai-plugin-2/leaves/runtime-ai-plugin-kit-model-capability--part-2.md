<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-model-capability--part-2 · source: ai-plugin-runtime-ai-plugin-kit-model-capability.md -->

# ModelCapability — continued (part 2)

## Design Decisions

- **Decision**: `.conversation`'s capability is derived via
  `ModelUseFacet.facets(for:extraText:).contains(.conversation)` rather
  than its own keyword heuristic.
  **Rationale**: per the source's top-of-file doc comment, `conversation`
  "has no gateway flag anywhere and is read out of the model's prose via
  `ModelUseFacet`, which is exactly the heuristic the 'Good for' filter
  already runs; folding it in here keeps one derivation rather than two
  that can disagree."
  **Approved**: pending
- **Decision**: `.reasoning` and `.vision` return `false` from
  `has(_:_:extraText:)` whenever the gateway does not report them, even
  when `description`, `goodFor`, or `extraText` explicitly praise the
  model's reasoning or vision ability.
  **Rationale**: per the source comment on `has`, "prose saying a model
  'reasons well' is marketing, not the asserted capability the check-mark
  column claims" — the column is meant to represent only what the
  serving gateway itself asserted.
  **Approved**: pending
- **Decision**: a curated `tools == true` flag counts as evidence for
  `.tools` even when the gateway reported no capability list at all.
  **Rationale**: per the source comment on `has`, "that flag is the only
  evidence most curated `modelDetails` entries carry, and dropping it
  would blank the column for every provider that ships its own model
  copy."
  **Approved**: pending
- **Decision**: `reportedNames` lists multiple spellings per hard
  capability (e.g. `function_calling`, `functioncalling`,
  `function-calling`, `functions` for `.tools` alone), rather than a
  single canonical spelling.
  **Rationale**: per the source's top-of-file doc comment, "the string is
  whatever the serving gateway chose to call it and no two agree...
  Matching only the toolkit's own spelling silently blanked the column
  for every provider that spells it differently" — this documents a
  fix for a real, previously observed bug.
  **Approved**: pending
