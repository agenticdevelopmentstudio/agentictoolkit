<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-model-use-facet--part-2 · source: ai-plugin-runtime-ai-plugin-kit-model-use-facet.md -->

# ModelUseFacet — continued (part 2)

## Platform Notes

- **SwiftUI**: The source (`packages/apple/AgenticToolkit/AIPluginKit/ModelUseFacet.swift`,
  companion `ModelCapability.swift`, tests
  `Tests/AIPluginKitTests/ModelUseFacetTests.swift`) has no SwiftUI or AppKit
  dependency of its own — it is plain Swift, framework-agnostic. It is
  consumed today by AppKit view controllers under
  `macOS/Features/AIPlugins/Settings/` (`ModelChooserViewController`,
  `ModelChooserContent`, `ProviderPickerViewController`) purely as a pure
  function call; a SwiftUI consumer would call the same `facets`/`matches`
  API with no changes to this type, likely driving a `Picker` or a row of
  `Toggle`s from `ModelUseFacet.allCases` bound to a `@State
  Set<ModelUseFacet>`.
- **Compose**: Model as a Kotlin `enum class ModelUseFacet(val title: String,
  val detail: String)` with the ten cases as enumerants carrying their label
  and tooltip directly, matching the Swift `switch`-per-property shape.
  Reproduce `wordPrefixes`/`phrases` as `private val` lists on each
  enumerant, `impliedByCapability` as a nullable `ModelCapability?` property,
  and `facets(text:capabilities:)`/`matches(...)` as top-level (or
  companion-object) pure functions returning `Set<ModelUseFacet>` /
  `Boolean` — no Compose-specific API is needed since the type itself has no
  UI dependency, only its consumers (a `FilterChip` row) would use Compose.
- **React/Web**: Model the ten cases as a `const enum ModelUseFacet = {
  Coding: "coding", Conversation: "conversation", ... } as const` (or a
  string-literal union type) with parallel `TITLES`/`DETAILS` lookup records
  keyed by the same values. Port `facets(text, capabilities)` as a pure
  function using `text.toLowerCase()`, a tokenizer regex
  (`text.match(/[\p{L}\p{N}]+/gu)`) for `word-tokenization`, `.startsWith()`
  per prefix for `word-prefix-anchoring`, and `.includes()` per phrase for
  `phrase-matching-on-raw-text`; return a `Set<ModelUseFacet>` (native `Set`)
  and implement `matches(facets, selected)` with `Set` operations
  (`selected.size === 0 || facets.size === 0 ||
  [...facets].some(f => selected.has(f))`).
- **AppKit / UIKit**: No AppKit- or UIKit-specific API appears in this file;
  it is genuinely UI-framework-agnostic and only consumed by the AppKit view
  controllers named above. A UIKit consumer (e.g. an iOS provider-settings
  screen) would call the same `facets`/`matches` API unchanged, driving a
  `UIMenu` or a table of checkable rows instead of AppKit's
  `MultiChoiceFilterButton`.
- **WinUI 3**: This is the platform this recipe exists to steer. Model
  `ModelUseFacet` as a C# `enum ModelUseFacet { Coding, Conversation,
  ProblemSolving, Research, Writing, Vision, Agents, Translation, Speech,
  Economy }` plus a `static class ModelUseFacetInfo` exposing `Title`/`Detail`
  lookups (a `Dictionary<ModelUseFacet, string>` or a `switch` expression),
  matching `title`/`detail`. Reproduce `wordPrefixes`/`phrases` as
  `IReadOnlyList<string>` returned from a `switch` on the enum, and
  `impliedByCapability` as a `ModelCapability?` (nullable enum) switch
  mirroring `ModelUseFacet.swift`. Port `facets(text, capabilities)`
  using `text.ToLowerInvariant()`, `System.Globalization`-aware tokenizing
  (split on runs where `!char.IsLetterOrDigit(c)`) for `word-tokenization`,
  `word.StartsWith(prefix, StringComparison.Ordinal)` for
  `word-prefix-anchoring`, and `lowered.Contains(phrase)` for
  `phrase-matching-on-raw-text`; return a `HashSet<ModelUseFacet>` (the
  `Set<T>` equivalent) and implement `Matches(facets, selected)` with
  `HashSet<T>.Overlaps` (`selected.Count == 0 || facets.Count == 0 ||
  facets.Overlaps(selected)`) to mirror `!facets.isDisjoint(with:)`. No
  `HttpClient`, `System.Text.Json`, `Windows.Storage`, or `Task`/`async` is
  needed — every operation here is synchronous, in-memory string matching,
  just as in the Swift source.

## Design Decisions

- **Decision**: Facets are derived on demand from text and capabilities
  (`facets(text:capabilities:)`/`facets(for:extraText:)`) rather than stored
  as data on the model or baked into `model-catalog.json`.
  **Rationale**: per the source's top-of-file comment, the evidence text a
  model carries "arrives from three places at three different times: the
  shared catalog, a template's curated `modelDetails`, and, for a local
  server, a blurb fetched from ollama.com for a model no catalog has ever
  heard of" — baking the answer into the catalog file "would serve only the
  first."
  **Approved**: pending
- **Decision**: Keyword matching is treated explicitly as a heuristic: a
  facet present means *some* evidence was found, never that its absence
  means the model is bad at that job, and a model with no evidence at all
  (`facets.isEmpty`) always passes `matches(...)` regardless of `selected`.
  **Rationale**: per the source's top-of-file comment and the `matches` doc
  comment, "a model we know *nothing* about always passes... hiding a model
  because its gateway shipped no description would quietly remove the very
  model the user came to select — including, on a local server, every model
  at once."
  **Approved**: pending
- **Decision**: A model's `id` (its name) is deliberately excluded from
  evidence, even though it is often the most on-the-nose string available
  (e.g. `qwen3-coder`).
  **Rationale**: per the `facets(for:extraText:)` doc comment, "names are
  marketing, not description: `-instruct` and `-chat` are a training-recipe
  suffix on most of the catalog rather than a claim about conversation, and
  `claude-opus-5-fast` would land the flagship model under 'Economy'."
  **Approved**: pending
- **Decision**: `matches(facets:selected:)` uses any-of (non-disjoint) rather
  than all-of (subset) semantics when multiple facets are selected.
  **Rationale**: per the `matches` doc comment, "'good for coding *or*
  writing' is how a check-several-boxes filter reads, and requiring all of
  them empties the list on the second box."
  **Approved**: pending
- **Decision**: `.translation`'s word-prefix list does not include the bare
  word `"language"`, even though it is common in translation-relevant prose.
  **Rationale**: inferred from `ModelUseFacetTests.languageIsNotTranslation`'s
  comment — `"large language model"` is "the boilerplate opener of half the
  catalog's blurbs" and previously caused every model's description to
  falsely register as translation evidence; the fixed prefix/phrase lists in
  `ModelUseFacet.swift` (`"translat"`, `"multiling"`, `"localization"`,
  `"language pairs"`, `"cross-language"`) are the result of removing that
  false-positive term, not an oversight.
  **Approved**: pending
