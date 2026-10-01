---
id: f628f7f9-9c7b-4820-a4bf-231312a74839
title: Model Use Facet
domain: agentictoolkit://cookbook/ai/models/model-use-facet
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A heuristic that derives what a model is good for from its description
  text and reported capabilities, and filters models against a set of selected uses.
platforms:
- swift
- macos
tags:
- ai
- model-catalog
- provider
- engine
depends-on: []
related:
- agentictoolkit://cookbook/ai/models/model-catalog
references:
- packages/apple/AgenticToolkit/AIPluginKit/ModelUseFacet.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/ModelCapability.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/AIModelCatalog.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/ModelUseFacetTests.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/ModelChooserViewController.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/ModelChooserContent.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/ProviderPickerViewController.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Model Use Facet

## Overview

A use facet is one of ten fixed values (`coding`, `conversation`,
`problemSolving`, `research`, `writing`, `vision`, `agents`, `translation`,
`speech`, `economy`) naming "what a model is good for" — the axis a
gateway's hard capabilities (tools/reasoning/vision) and a raw description
sentence do not answer on their own. It is a **logic** component with no
visual surface of its own: a pure keyword-matching heuristic that derives
facets from text and capabilities, a convenience wrapper that reads a
resolved model's description, `goodFor` and an optional extra blurb, and an
any-of set filter that "Good for" filter controls use to hide or show
models. Facets are derived on demand rather than stored, because the
evidence text a model carries arrives from three different places at three
different times (the shared model catalog, a provider template's curated
model details, and a local server's live-fetched blurb).

## Behavioral Requirements

- **facet-cases**: The use-facet vocabulary MUST define exactly these ten
  values, in this order: `coding`, `conversation`, `problemSolving`,
  `research`, `writing`, `vision`, `agents`, `translation`, `speech`,
  `economy`. Each value's own identifier string MUST equal its case name
  verbatim (no custom identifier strings are declared), e.g. the identifier
  for `problemSolving` is `"problemSolving"`.
- **facet-title**: `title` MUST return the exact non-empty display string
  listed for each facet — `"Coding"`, `"Conversation"`, `"Problem solving"`,
  `"Research"`, `"Writing"`, `"Vision"`, `"Agents & tools"`, `"Translation"`,
  `"Speech & audio"`, `"Fast & low cost"` — for use as a menu or checkbox
  label.
- **facet-detail**: `detail` MUST return the exact non-empty tooltip string
  listed for each facet (e.g. `coding` → `"Writing, reviewing and debugging
  code"`, `economy` → `"Fast, cheap, high-volume work"`) for use as a menu
  item's tooltip.
- **capability-implied-facets**: Deriving facets from text and capabilities
  MUST insert `agents` when the reported capabilities include `tools`,
  `vision` when they include `vision`, and `problemSolving` when they
  include `reasoning` — regardless of what the text says — because the
  capability-to-facet mapping covers only those three facets. No other
  facet MUST be implied by a reported capability.
- **capability-evidence-checked-first**: For each facet, deriving facets
  from text and capabilities MUST check capability-implied evidence before
  word-prefix evidence, and word-prefix evidence before phrase evidence,
  short-circuiting on the first match found for that facet.
- **capability-string-matching-is-delegated**: Whether a capability string
  is "reported" MUST be decided by a shared capability-matching check, which
  matches case-insensitively against every known spelling for that
  capability (e.g. `tool_use`, `function_calling`, `functions` all count as
  `tools`) — facet derivation itself performs no string comparison against
  capability values.
- **word-tokenization**: Deriving facets from text and capabilities MUST
  lowercase the text and split it into words on every run of characters
  that is neither a Unicode letter nor a Unicode number, discarding the
  separators.
- **word-prefix-anchoring**: A facet's word-prefix evidence MUST match only
  when a whole tokenized word has one of that facet's prefixes as its
  starting substring; a prefix occurring inside a word but not at its start
  (e.g. `"cod"` inside `"encoded"`) MUST NOT count as evidence.
- **phrase-matching-on-raw-text**: A facet's phrase evidence MUST be tested
  as a substring of the full lowercased text (not of the tokenized word
  list), so phrases that span whitespace or a hyphen (`"long-context"`,
  `"step-by-step"`, `"function calling"`) are matched even though
  tokenization would otherwise split them into separate words.
- **per-facet-evidence-lists-are-fixed**: Each facet's word-prefix list and
  phrase list MUST be the fixed literal lists given for that case (e.g.
  `economy`'s prefixes `["fast", "efficient", "lightweight", "cheap",
  "inexpensive"]`, phrases `["low cost", "low-cost", "high volume",
  "high-volume", "cost-effective", "cost effective", "high throughput",
  "high-throughput"]`); `conversation` MUST have an empty phrase list.
- **resolved-model-evidence-sources**: Deriving facets for a resolved model
  MUST derive its text input by joining, in order, the model's
  `description`, its `goodFor` value, and an optional extra text — dropping
  any of the three that is absent — with a single space separator, and MUST
  pass the model's `capabilities` through unchanged as the capabilities
  input.
- **model-id-excluded-from-evidence**: Deriving facets for a resolved model
  MUST NOT use the model's `id` (its name) as evidence for any facet — only
  `description`, `goodFor`, the extra text, and `capabilities` MUST be
  considered.
- **empty-evidence-yields-empty-set**: Deriving facets from text and
  capabilities, called with an empty string and empty (or default)
  capabilities, MUST return an empty set of facets; no facet MUST ever be
  present without at least one of capability, word-prefix, or phrase
  evidence for it.
- **facets-are-a-set**: Both facet-derivation entry points MUST return a
  set of facets — a model MUST be able to carry more than one facet
  simultaneously, with no defined ordering and no duplicate entries for the
  same facet.
- **filter-empty-selection-passes-all**: Testing whether a model's facets
  match a filter selection MUST return true for every facets value when the
  selection is empty — an empty filter selection excludes nothing.
- **filter-unknown-model-passes**: Testing whether a model's facets match a
  filter selection MUST return true whenever the model's facets are empty,
  regardless of the selection, because no evidence is treated as "unknown,"
  never as "fails every use."
- **filter-any-of-semantics**: When both the model's facets and the
  selection are non-empty, the match check MUST return true if and only if
  the two sets are not disjoint (at least one facet in common) — selecting
  several uses MUST behave as "any of these," never "all of these."
- **value-type-concurrency-safety**: A use facet MUST be an immutable
  value with no stored state beyond its own identifier, and its `title`,
  `detail`, word-prefix list, phrase list, and capability mapping MUST be
  pure computed properties with no shared mutable state; both
  facet-derivation functions and the match check MUST be pure, with no
  side effects, so any number of callers on any thread MAY call them
  concurrently on the same or different inputs without synchronization.
- **codable-round-trip**: A use facet MUST serialize to and deserialize
  from its own identifier string, so a set of facets round-trips through
  JSON as an array of the raw case-name strings.
- **exhaustive-derivation-switches**: The `title`, `detail`, word-prefix,
  and phrase derivations MUST cover every facet with no fallback branch, so
  adding a facet without extending all four is a build-time error; only the
  capability mapping MUST use a fallback (no mapping) for the seven facets
  it does not map to a capability.

## Appearance

Not applicable — this is a keyword-derivation heuristic and a set filter, not
a visual component.

## States

Not applicable — this is a keyword-derivation heuristic and a set filter, not
a visual component. It has no runtime state machine of its own: every public
function is a pure, synchronous, side-effect-free computation over its
arguments (see `value-type-concurrency-safety` under Behavioral
Requirements).

## Accessibility

Not applicable — this is a keyword-derivation heuristic and a set filter, not
a visual component. `title`/`detail` supply label and tooltip text that a
*caller's* menu or checkbox filter control renders; this component defines
no control, role, trait, or tap target of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| MUF-001 | word-tokenization, word-prefix-anchoring | Derive facets from the text "A model for coding, debugging and creative writing" | Result contains `coding` and `writing` |
| MUF-002 | capability-implied-facets | Same text | Result does not contain `conversation` (no chat/assistant/dialog wording, no `tools`/`reasoning`/`vision` capability) |
| MUF-003 | word-prefix-anchoring | Derive facets from "encoded tokens are decoded" | Result does not contain `coding` — `"cod"` occurs mid-word, not at a word start |
| MUF-004 | word-prefix-anchoring | Derive facets from "codes and coding" | Result contains `coding` |
| MUF-005 | phrase-matching-on-raw-text | Derive facets from "supports function calling" | Result contains `agents` |
| MUF-006 | phrase-matching-on-raw-text | Derive facets from "a long-context model" | Result contains `research` |
| MUF-007 | phrase-matching-on-raw-text | Derive facets from "step-by-step" | Result contains `problemSolving` |
| MUF-008 | phrase-matching-on-raw-text | Derive facets from "cost-effective for high volume" | Result contains `economy` |
| MUF-009 | capability-implied-facets, capability-evidence-checked-first | Derive facets from empty text with capabilities `["tools", "vision", "reasoning"]` | Result equals exactly `{agents, vision, problemSolving}`, with no text evidence needed |
| MUF-010 | resolved-model-evidence-sources, model-id-excluded-from-evidence | Derive facets for a resolved model with `id: "mystery-7b"`, `description: "Great at coding."`, `goodFor: "translation"` | Result is a superset of `{coding, translation}` |
| MUF-011 | model-id-excluded-from-evidence, empty-evidence-yields-empty-set | Derive facets for a resolved model with `id: "claude-opus-5-fast"` (no other evidence), and for one with `id: "qwen3-coder"` (no other evidence) | Both results are empty sets — the model id alone (`-fast`, `-coder`) is never evidence |
| MUF-012 | resolved-model-evidence-sources | Derive facets for a resolved model with `id: "mystery"` and extra text "excels at math and logic puzzles" | Result contains `problemSolving` |
| MUF-013 | per-facet-evidence-lists-are-fixed | Derive facets from "A large language model from Acme." | Result does not contain `translation` — the word "language" alone is not translation evidence (this boilerplate opener previously caused a false positive) |
| MUF-014 | per-facet-evidence-lists-are-fixed | Derive facets from "Translates between 30 languages" and from "Strong on rare language pairs" | Both results contain `translation` |
| MUF-015 | filter-empty-selection-passes-all | Match facets `{coding}` against selection `{}`, and facets `{}` against selection `{}` | Both true |
| MUF-016 | filter-any-of-semantics | Match facets `{coding}` against selection `{coding, writing}`; facets `{writing}` against `{coding, writing}`; facets `{vision}` against `{coding, writing}` | true, true, false |
| MUF-017 | filter-unknown-model-passes | Match facets `{}` against selection `{coding}` | true |
| MUF-018 | facet-title, facet-detail | Read `title` and `detail` for every facet | Every title and detail is a non-empty string |
| MUF-019 | facet-cases, codable-round-trip | Count all facets; look up the facet whose identifier is `"problemSolving"` | Count is `10`, and the looked-up facet equals `problemSolving` |
| MUF-020 | value-type-concurrency-safety | Derive facets from many concurrent tasks with different inputs | Every task returns the result for its own input with no crash, data race, or need for a lock |

## Edge Cases

- **Empty text, no capabilities.** Deriving facets from an empty string and
  empty capabilities (the default) MUST return an empty set — zero words
  are produced by tokenizing an empty string, and empty capabilities report
  nothing.
- **Text with no letters or numbers.** Deriving facets from a string with no
  letters or numbers (e.g. `"--- ... !!!"`) MUST return an empty set —
  tokenization on "not a letter and not a number" yields zero words, and
  phrase matching finds no substring hits either.
- **Unrecognized capability string.** A capabilities list containing a
  string the capability-matching check does not recognize for any facet
  (e.g. `"beta-feature"`) MUST be silently ignored — it implies no facet and
  MUST NOT raise an error.
- **Boundary: single matching character run.** A word that is exactly one of
  a facet's prefixes (e.g. the word `"cod"` alone) MUST count as evidence —
  a word matching itself as its own prefix; this is the minimum-length case
  of `word-prefix-anchoring`, not a special-cased boundary.
- **Redundant evidence.** Text that satisfies both the word-prefix and the
  phrase evidence for the same facet (e.g. `"coding, code generation"` for
  `coding`) MUST still yield that facet exactly once — the result is a set
  with no duplicate entries.
- **Capability and text both point to the same facet.** A model whose
  capabilities report `tools` and whose text also matches an `agents`
  keyword MUST still show `agents` exactly once: because capability-implied
  evidence for a facet is checked first and short-circuits, the word/phrase
  checks for that facet are never reached, so this cannot produce a
  duplicate or a conflict.
- **Non-English or transliterated evidence.** The word-prefix and phrase
  lists are fixed English-token lists (see Localization); a description
  written only in another language MUST produce an empty set for facets
  whose only matching keywords are English, exactly as if the model had no
  description at all — this is a fact about the fixed evidence lists, not a
  crash or undefined behavior.
- **Concurrent access.** Facet derivation and every function in this
  component are pure and hold no shared mutable state, so concurrent calls
  from multiple threads or tasks on the same or different inputs MUST
  behave identically to sequential calls — this is applicable (facets are
  read from UI code and could be read from background contexts) and is safe
  by construction, not merely untested.
- **Error states (dependency failure).** Not applicable: facet derivation
  makes no network call, file-system call, or database call of any kind —
  it operates only on the text/capability arguments and the already-in-memory
  resolved model passed to it, so there is no dependency that can be
  "unavailable" or "return an error" for this component to handle.
- **Offline or disconnected state.** Not applicable, for the same reason:
  this component performs no network I/O. Whether the resolved model it is
  given was itself fetched online or offline is a concern of its caller,
  not of facet derivation.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `text` | string | required | Evidence text passed to the core facet derivation — normally a model's description and/or `goodFor` blurb, already joined by the caller. |
| `capabilities` | list of strings | `[]` | Reported capability strings passed alongside `text`; matched via the capability-matching check for the three capability-implied facets. |
| `model` | a resolved model | required | Input to facet derivation for a resolved model; its `description`, `goodFor`, and `capabilities` fields are read, its `id` is deliberately not. |
| `extraText` | string, optional | absent | Additional description text not carried by the catalog (e.g. a local server's live-fetched blurb for a model the catalog has never seen), appended to the model's `description`/`goodFor` before derivation. |
| `selected` | set of facets | caller-supplied | The set of uses a filter control has checked, passed to the match check; an empty set is the default, unfiltered state of a "Good for" filter menu. |

## Deep Linking

Not applicable: facet derivation defines no route, URL scheme, or navigable
destination — it is a data-derivation and filtering component with no
navigation surface of its own.

## Localization

`title` and `detail` are hardcoded, English-only literal strings returned
directly from a per-facet mapping — there is no localization-lookup
mechanism (a string catalog, a localized-string table) anywhere in this
component, so these ten menu labels and ten tooltips MUST ship in English
regardless of the host app's locale. The derivation's own evidence
vocabulary (the word-prefix and phrase lists) is likewise a fixed,
English-only token and phrase list; a model described only in another
language derives no facets from that description text (see Edge Cases).
This is a stated fact about the source, not a gap to resolve here.

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| *(none — inline literal)* | `Coding` / `Conversation` / `Problem solving` / `Research` / `Writing` / `Vision` / `Agents & tools` / `Translation` / `Speech & audio` / `Fast & low cost` | `title`: menu/checkbox label per facet |
| *(none — inline literal)* | `Writing, reviewing and debugging code` / … (one per facet) | `detail`: tooltip text per facet |

## Accessibility Options

Not applicable: facet derivation renders nothing and reads no accessibility
display setting (Reduce Motion, Increase Contrast, Differentiate Without
Color) — those apply, if at all, to the caller's menu or checkbox control
that displays `title`/`detail`, not to this component.

## Feature Flags

Not applicable: facet derivation contains no feature-flag or remote-config
check of any kind; every facet, prefix, phrase, and filter rule is
unconditional, fixed.

## Analytics

Not applicable: facet derivation emits no analytics or telemetry event of
any kind — it has no event-logging call.

## Privacy

Not applicable: a use facet carries no user data, credential, or token. Its
inputs (`text`, `capabilities`, a resolved model's `description`/`goodFor`)
are catalog and provider-template metadata about AI models, not personal or
sensitive data, and this component neither stores nor transmits anything —
it is a pure, synchronous computation over its arguments.

## Logging

Not applicable: facet derivation contains no logging call of any kind.

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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/ModelUseFacet.swift` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [test-pyramid](agenticdevelopercookbook://compliance/best-practices#test-pyramid) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

Notes: separation-of-concerns passes because the source itself distinguishes
"the pure core" (`facets(text:capabilities:)`) from the `AIModelCatalog`-aware
convenience wrapper (`facets(for:extraText:)`), and keeps filtering
(`matches`) as a third, independent function. graceful-degradation passes
because an evidence-free model always passes `matches(...)` rather than being
hidden (see `filter-unknown-model-passes`). test-pyramid passes because
`ModelUseFacetTests.swift` exercises the pure derivation and filter logic
directly, with no UI, network, or file-system dependency in the test suite.
no-hardcoded-strings fails because `title` and `detail` return English-only
`String` literals with no localization mechanism (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/models/. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Compliance links moved to the agenticdevelopercookbook compliance scheme |
