<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-model-use-facet--test-vectors · source: ai-plugin-runtime-ai-plugin-kit-model-use-facet.md -->

# ModelUseFacet

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| MUF-001 | word-tokenization, word-prefix-anchoring | `facets(text: "A model for coding, debugging and creative writing")` | Result contains `.coding` and `.writing` — `ModelUseFacetTests.fromText` |
| MUF-002 | capability-implied-facets | `facets(text: "A model for coding, debugging and creative writing")` | Result does not contain `.conversation` (no chat/assistant/dialog wording, no `tools`/`reasoning`/`vision` capability) — `ModelUseFacetTests.fromText` |
| MUF-003 | word-prefix-anchoring | `facets(text: "encoded tokens are decoded")` | Result does not contain `.coding` — `"cod"` occurs mid-word, not at a word start — `ModelUseFacetTests.anchoredPrefixes` |
| MUF-004 | word-prefix-anchoring | `facets(text: "codes and coding")` | Result contains `.coding` — `ModelUseFacetTests.anchoredPrefixes` |
| MUF-005 | phrase-matching-on-raw-text | `facets(text: "supports function calling")` | Result contains `.agents` — `ModelUseFacetTests.phrases` |
| MUF-006 | phrase-matching-on-raw-text | `facets(text: "a long-context model")` | Result contains `.research` — `ModelUseFacetTests.phrases` |
| MUF-007 | phrase-matching-on-raw-text | `facets(text: "step-by-step")` | Result contains `.problemSolving` — `ModelUseFacetTests.phrases` |
| MUF-008 | phrase-matching-on-raw-text | `facets(text: "cost-effective for high volume")` | Result contains `.economy` — `ModelUseFacetTests.phrases` |
| MUF-009 | capability-implied-facets, capability-evidence-checked-first | `facets(text: "", capabilities: ["tools", "vision", "reasoning"])` | Result `== [.agents, .vision, .problemSolving]` exactly, with no text evidence needed — `ModelUseFacetTests.capabilitiesImply` |
| MUF-010 | resolved-model-evidence-sources, model-id-excluded-from-evidence | `facets(for: AIModelCatalog.ResolvedModel(id: "mystery-7b", description: "Great at coding.", goodFor: "translation"))` | Result is a superset of `[.coding, .translation]` — `ModelUseFacetTests.fromResolvedModel` |
| MUF-011 | model-id-excluded-from-evidence, empty-evidence-yields-empty-set | `facets(for: AIModelCatalog.ResolvedModel(id: "claude-opus-5-fast"))` and `facets(for: AIModelCatalog.ResolvedModel(id: "qwen3-coder"))` | Both results are empty sets — the model id alone (`-fast`, `-coder`) is never evidence — `ModelUseFacetTests.fromResolvedModel` |
| MUF-012 | resolved-model-evidence-sources | `facets(for: AIModelCatalog.ResolvedModel(id: "mystery"), extraText: "excels at math and logic puzzles")` | Result contains `.problemSolving` — `ModelUseFacetTests.fromResolvedModel` |
| MUF-013 | per-facet-evidence-lists-are-fixed | `facets(text: "A large language model from Acme.")` | Result does not contain `.translation` — `"language"` alone is not `.translation` evidence (inferred from `ModelUseFacetTests.languageIsNotTranslation`'s comment: this boilerplate opener previously caused a false positive) | 
| MUF-014 | per-facet-evidence-lists-are-fixed | `facets(text: "Translates between 30 languages")` and `facets(text: "Strong on rare language pairs")` | Both results contain `.translation` — `ModelUseFacetTests.languageIsNotTranslation` |
| MUF-015 | filter-empty-selection-passes-all | `matches(facets: [.coding], selected: [])` and `matches(facets: [], selected: [])` | Both `true` — `ModelUseFacetTests.emptySelectionPasses` |
| MUF-016 | filter-any-of-semantics | `matches(facets: [.coding], selected: [.coding, .writing])`, `matches(facets: [.writing], selected: [.coding, .writing])`, `matches(facets: [.vision], selected: [.coding, .writing])` | `true`, `true`, `false` — `ModelUseFacetTests.orSemantics` |
| MUF-017 | filter-unknown-model-passes | `matches(facets: [], selected: [.coding])` | `true` — `ModelUseFacetTests.unknownPasses` |
| MUF-018 | facet-title, facet-detail | For every case in `ModelUseFacet.allCases`, read `.title` and `.detail` | Every `.title` and `.detail` is a non-empty string — `ModelUseFacetTests.labels` |
| MUF-019 | facet-cases, codable-round-trip | `ModelUseFacet.allCases.count` | `10`, and `ModelUseFacet(rawValue: "problemSolving") == .problemSolving` — not exercised by a named test in the given suite; traced directly to the `enum` declaration (`ModelUseFacet.swift`) |
| MUF-020 | value-type-concurrency-safety | Call `ModelUseFacet.facets(text:capabilities:)` from many concurrent `Task`s in a `TaskGroup` with different inputs | Every task returns the result for its own input with no crash, data race, or need for a lock — not exercised by a dedicated concurrency test in the given suite; enforced statically by the `Sendable` conformance and the absence of any mutable stored state |
