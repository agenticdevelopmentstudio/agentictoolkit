<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-model-catalog--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-ai-model-catalog.md -->

# AIModelCatalog

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-model-catalog--edge-cases#<slug>`):

- `empty-lookup-name` MUST — model(named: "") — byName and byCanonicalID (via canonicalID("") == "") both miss unless a Model literally has id ""; …
- `sparse-decode` MUST — A JSON model object carrying only "id" — aliases and capabilities MUST decode to [], description MUST decode to nil, …
- `model-with-zero-aliases` MUST — A Model whose aliases == [] (e.g. the sample's llama-3.3-70b-instruct) MUST still resolve by its own id through …
- `empty-catalog` MUST — A catalog constructed with models: [] MUST build empty indexes; every model(named:) call MUST return nil and every …
- `full-size-shipped-catalog` MUST — The bundled resource carries 566+ models across 26+ gateways; the same dictionary-based lookup and merge logic MUST …
- `concurrent-reads` MUST — Model, Offering, ResolvedModel, and AIModelCatalog are Sendable value types built entirely inside their initializers, …
- `missing-unreadable-or-malformed-bundle-resource` MUST — load(from:) MUST return nil for all three (bundle.url(forResource:withExtension:) returns nil; Data(contentsOf:) …
- `curated-modeldetail-lookup-is-exact-match-only` SHOULD — template.modelDetail(for:) (AIPluginDescriptor.swift) does modelDetails?.first { $0.id == modelID } — no lowercasing, …
- `empty-string-curated-description-is-treated-as-absent` MUST — resolve(...) MUST fall back to the shared Model.description when the curated ModelDetail.description is present but an …
- `canonicalization-suffix-ordering` MUST — A model name ending in -fp8-fast MUST have the whole four-token suffix stripped, not just -fp8, because the source …

## Edge Cases

- **Empty lookup name.** `model(named: "")` — `byName` and `byCanonicalID`
  (via `canonicalID("") == ""`) both miss unless a `Model` literally has id
  `""`; the call MUST return `nil`.
- **Sparse decode.** A JSON model object carrying only `"id"` — `aliases` and
  `capabilities` MUST decode to `[]`, `description` MUST decode to `nil`,
  rather than failing the whole catalog's decode.
- **Model with zero aliases.** A `Model` whose `aliases == []` (e.g. the
  sample's `llama-3.3-70b-instruct`) MUST still resolve by its own `id`
  through `byCanonicalID`.
- **Empty catalog.** A catalog constructed with `models: []` MUST build empty
  indexes; every `model(named:)` call MUST return `nil` and every
  `resolve(...)` call MUST return an empty `ResolvedModel`, never throw.
- **Full-size shipped catalog.** The bundled resource carries 566+ models
  across 26+ gateways; the same dictionary-based lookup and merge logic MUST
  behave identically at that scale as in the two-model unit-test fixture — no
  size-dependent branch exists in the source.
- **Concurrent reads.** `Model`, `Offering`, `ResolvedModel`, and
  `AIModelCatalog` are `Sendable` value types built entirely inside their
  initializers, with no mutable stored state afterward, so concurrent reads
  from multiple threads or tasks MUST be safe with no locking — this is
  applicable (the catalog is read from AppKit UI code and could be read from
  background contexts too) and is safe by construction, not merely untested.
- **Missing, unreadable, or malformed bundle resource.** `load(from:)` MUST
  return `nil` for all three (`bundle.url(forResource:withExtension:)` returns
  `nil`; `Data(contentsOf:)` throws; `JSONDecoder().decode` throws), and
  `AIModelCatalog.shared` MUST fall back to the empty catalog rather than
  crash.
- **Id/alias collision between two distinct models.** No validation exists;
  the index-build loop's last write for a given key wins deterministically
  (see `alias-collision-last-writer-wins`), with no diagnostic distinguishing
  "intended override" from "generator bug." This is a stated fact, not a
  gap, because the resulting behavior is fully deterministic and traceable.
- **Curated `ModelDetail` lookup is exact-match only.** `template.modelDetail(for:)`
  (`AIPluginDescriptor.swift`) does `modelDetails?.first { $0.id == modelID }`
  — no lowercasing, no canonicalization fallback, unlike `model(named:)`.
  A template whose `modelDetails` entry is spelled differently from its
  `models` list entry SHOULD have matching spellings, or curation silently
  does not apply for that model.
- **Empty-string curated description is treated as absent.** `resolve(...)`
  MUST fall back to the shared `Model.description` when the curated
  `ModelDetail.description` is present but an empty string, exactly as it
  does when the curated value is `nil` — the two are indistinguishable to a
  caller of `resolve`.
- **Canonicalization suffix ordering.** A model name ending in `-fp8-fast`
  MUST have the whole four-token suffix stripped, not just `-fp8`, because
  the source checks the fixed suffix list in the order given and returns on
  the first match.
- **No network dependency (offline/disconnected: not applicable).** `AIModelCatalog`
  performs no network I/O of any kind — it reads only a bundled local JSON
  resource via `Bundle`/`Data(contentsOf:)`. There is no online/offline
  distinction for this component; connectivity loss elsewhere in the host app
  cannot affect it.
