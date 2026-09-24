---
id: f628f7f9-9c7b-4820-a4bf-231312a74839
title: ModelUseFacet
domain: agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-model-use-facet
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AIPluginKit's heuristic that derives what a model is good for from its description
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
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-ai-model-catalog
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

# ModelUseFacet

## Overview

`ModelUseFacet` is a `String`-backed, `CaseIterable`, `Sendable`, `Codable`
enum of ten values (`coding`, `conversation`, `problemSolving`, `research`,
`writing`, `vision`, `agents`, `translation`, `speech`, `economy`) naming
"what a model is good for" — the axis a gateway's hard capabilities
(`tools`/`reasoning`/`vision`) and a raw description sentence do not answer on
their own. It is a **logic** component with no visual surface of its own: a
pure keyword-matching heuristic (`facets(text:capabilities:)`), a convenience
wrapper that reads a `AIModelCatalog.ResolvedModel`'s description, `goodFor`
and an optional extra blurb (`facets(for:extraText:)`), and an any-of set
filter (`matches(facets:selected:)`) that AppKit "Good for" filter controls
(`ModelChooserViewController`, `ProviderPickerViewController`) use to hide or
show models. Facets are derived on demand rather than stored, because the
evidence text a model carries arrives from three different places at three
different times (the shared `model-catalog.json`, a provider template's
curated `modelDetails`, and a local server's live-fetched blurb).

## Behavioral Requirements

- **facet-cases**: `ModelUseFacet` MUST define exactly these ten cases, in
  this declaration order: `coding`, `conversation`, `problemSolving`,
  `research`, `writing`, `vision`, `agents`, `translation`, `speech`,
  `economy` (`ModelUseFacet.swift`). Each case's `rawValue` MUST equal
  its Swift case name verbatim (no custom raw-value strings are declared),
  e.g. `ModelUseFacet.problemSolving.rawValue == "problemSolving"`.
- **facet-title**: `title` MUST return the exact non-empty display string
  listed for each case — `"Coding"`, `"Conversation"`, `"Problem solving"`,
  `"Research"`, `"Writing"`, `"Vision"`, `"Agents & tools"`, `"Translation"`,
  `"Speech & audio"`, `"Fast & low cost"` — for use as a menu or checkbox
  label (`ModelUseFacet.swift`).
- **facet-detail**: `detail` MUST return the exact non-empty tooltip string
  listed for each case (e.g. `.coding` → `"Writing, reviewing and debugging
  code"`, `.economy` → `"Fast, cheap, high-volume work"`) for use as a menu
  item's tooltip (`ModelUseFacet.swift`).
- **capability-implied-facets**: `facets(text:capabilities:)` MUST insert
  `.agents` when the reported capabilities include `tools` (per
  `ModelCapability.reports(.tools, in:)`), `.vision` when they include
  `vision`, and `.problemSolving` when they include `reasoning` — regardless
  of what the text says — because `impliedByCapability` maps only those three
  facets to a `ModelCapability` (`ModelUseFacet.swift`). No
  other facet MUST be implied by a reported capability.
- **capability-evidence-checked-first**: For each facet, `facets(text:
  capabilities:)` MUST check capability-implied evidence before word-prefix
  evidence, and word-prefix evidence before phrase evidence, short-circuiting
  (`continue`) on the first match found for that facet
  (`ModelUseFacet.swift`).
- **capability-string-matching-is-delegated**: Whether a capability string is
  "reported" MUST be decided by `ModelCapability.reports(_:in:)`, which
  matches case-insensitively against every known spelling for that capability
  (e.g. `tool_use`, `function_calling`, `functions` all count as `tools`) —
  `ModelUseFacet` itself performs no string comparison against capability
  values (`ModelUseFacet.swift`, `ModelCapability.swift`).
- **word-tokenization**: `facets(text:capabilities:)` MUST lowercase `text`
  and split it into words on every run of characters that is neither a
  Unicode letter nor a Unicode number, discarding the separators
  (`ModelUseFacet.swift`).
- **word-prefix-anchoring**: A facet's word-prefix evidence MUST match only
  when a whole tokenized word has one of that facet's prefixes as its
  starting substring (`word.hasPrefix(prefix)`); a prefix occurring inside a
  word but not at its start (e.g. `"cod"` inside `"encoded"`) MUST NOT count
  as evidence (`ModelUseFacet.swift`).
- **phrase-matching-on-raw-text**: A facet's phrase evidence MUST be tested
  as a substring of the full lowercased text (not of the tokenized word
  list), so phrases that span whitespace or a hyphen (`"long-context"`,
  `"step-by-step"`, `"function calling"`) are matched even though
  tokenization would otherwise split them into separate words
  (`ModelUseFacet.swift`).
- **per-facet-evidence-lists-are-fixed**: `wordPrefixes` and `phrases` MUST
  return the fixed literal lists given in the source for each case (e.g.
  `.economy` prefixes `["fast", "efficient", "lightweight", "cheap",
  "inexpensive"]`, phrases `["low cost", "low-cost", "high volume",
  "high-volume", "cost-effective", "cost effective", "high throughput",
  "high-throughput"]`); `.conversation` MUST have an empty phrase list
  (`ModelUseFacet.swift`).
- **resolved-model-evidence-sources**: `facets(for:extraText:)` MUST derive
  its text input by joining, in order, `model.description`, `model.goodFor`,
  and `extraText` — dropping any of the three that is `nil` — with a single
  space separator, and MUST pass `model.capabilities` through unchanged as
  the capabilities input (`ModelUseFacet.swift`).
- **model-id-excluded-from-evidence**: `facets(for:extraText:)` MUST NOT use
  `model.id` (the model's name) as evidence for any facet — only
  `description`, `goodFor`, `extraText`, and `capabilities` MUST be
  considered (`ModelUseFacet.swift`).
- **empty-evidence-yields-empty-set**: `facets(text:capabilities:)` called
  with an empty string and empty (or default `[]`) capabilities MUST return
  an empty `Set<ModelUseFacet>`; no case MUST ever be present without at
  least one of capability, word-prefix, or phrase evidence for it
  (`ModelUseFacet.swift`).
- **facets-are-a-set**: `facets(text:capabilities:)` and `facets(for:
  extraText:)` MUST return a `Set<ModelUseFacet>` — a model MUST be able to
  carry more than one facet simultaneously, with no defined ordering and no
  duplicate entries for the same case (`ModelUseFacet.swift`).
- **filter-empty-selection-passes-all**: `matches(facets:selected:)` MUST
  return `true` for every `facets` value when `selected.isEmpty` — an empty
  filter selection excludes nothing (`ModelUseFacet.swift`).
- **filter-unknown-model-passes**: `matches(facets:selected:)` MUST return
  `true` whenever `facets.isEmpty`, regardless of `selected`, because no
  evidence is treated as "unknown," never as "fails every use"
  (`ModelUseFacet.swift`).
- **filter-any-of-semantics**: When both `facets` and `selected` are
  non-empty, `matches(facets:selected:)` MUST return `true` if and only if
  the two sets are not disjoint (at least one facet in common) — selecting
  several uses MUST behave as "any of these," never "all of these"
  (`ModelUseFacet.swift`).
- **value-type-concurrency-safety**: `ModelUseFacet` MUST be a `Sendable`
  value type with no stored instance state beyond its `rawValue`, and its
  `title`, `detail`, `wordPrefixes`, `phrases`, and `impliedByCapability`
  MUST be pure computed properties with no shared mutable state; the two
  `facets` overloads and `matches` MUST be pure static functions with no
  side effects, so any number of callers on any thread or actor MAY call
  them concurrently on the same or different inputs without synchronization
  (`ModelUseFacet.swift`).
- **codable-round-trip**: `ModelUseFacet` MUST encode to and decode from its
  `rawValue` string (via its compiler-synthesized `String`-backed `Codable`
  conformance), so `Set<ModelUseFacet>` round-trips through JSON as an array
  of the raw case-name strings (`ModelUseFacet.swift`).
- **exhaustive-derivation-switches**: The `title`, `detail`, `wordPrefixes`,
  and `phrases` switches MUST cover every case with no `default:` branch, so
  adding a facet without extending all four is a compile error; only
  `impliedByCapability` MUST use `default: return nil` for the seven cases it
  does not map to a capability (`ModelUseFacet.swift`).

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
*caller's* menu or checkbox control renders (e.g.
`ModelChooserViewController.swift`'s `MultiChoiceFilterButton`); this file
defines no control, role, trait, or tap target of its own.

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `text` | `String` | required | Evidence text passed to `facets(text:capabilities:)` — normally a model's description and/or `goodFor` blurb, already joined by the caller. |
| `capabilities` | `[String]` | `[]` | Reported capability strings passed alongside `text`; matched via `ModelCapability.reports(_:in:)` for the three capability-implied facets. |
| `model` | `AIModelCatalog.ResolvedModel` | required | Input to `facets(for:extraText:)`; its `description`, `goodFor`, and `capabilities` fields are read, its `id` is deliberately not. |
| `extraText` | `String?` | `nil` | Additional description text not carried by the catalog (e.g. a local server's live-fetched blurb for a model the catalog has never seen), appended to `model.description`/`goodFor` before derivation. |
| `selected` | `Set<ModelUseFacet>` | caller-supplied | The set of uses a filter control has checked, passed to `matches(facets:selected:)`; an empty set is the default, unfiltered state of the "Good for" menu (`ModelChooserViewController.swift`). |

## Deep Linking

Not applicable: `ModelUseFacet.swift` defines no route, URL scheme, or
navigable destination — it is a data-derivation and filtering type with no
navigation surface of its own.

## Localization

`title` and `detail` are hardcoded, English-only `String` literals returned
directly from a `switch` over `self` (`ModelUseFacet.swift`) — there is
no `String(localized:)`, string-catalog lookup, or `NSLocalizedString` call
anywhere in this file, so these ten menu labels and ten tooltips MUST ship in
English regardless of the host app's locale. The derivation's own evidence
vocabulary (`wordPrefixes`, `phrases`) is likewise a fixed, English-only
token and phrase list (`ModelUseFacet.swift`); a model described only
in another language derives no facets from that description text (see Edge
Cases). This is a stated fact about the source, not a gap to resolve here.

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| *(none — inline literal)* | `Coding` / `Conversation` / `Problem solving` / `Research` / `Writing` / `Vision` / `Agents & tools` / `Translation` / `Speech & audio` / `Fast & low cost` | `title`: menu/checkbox label per facet (`ModelUseFacet.swift`) |
| *(none — inline literal)* | `Writing, reviewing and debugging code` / … (one per case, `ModelUseFacet.swift`) | `detail`: tooltip text per facet |

## Accessibility Options

Not applicable: `ModelUseFacet.swift` renders nothing and reads no
accessibility display setting (Reduce Motion, Increase Contrast,
Differentiate Without Color) — those apply, if at all, to the caller's menu
or checkbox control that displays `title`/`detail`, not to this type.

## Feature Flags

Not applicable: `ModelUseFacet.swift` contains no feature-flag or
remote-config check of any kind; every facet, prefix, phrase, and filter rule
is unconditional, fixed source code.

## Analytics

Not applicable: `ModelUseFacet.swift` emits no analytics or telemetry event
of any kind — it has no event-logging call.

## Privacy

Not applicable: `ModelUseFacet` carries no user data, credential, or token.
Its inputs (`text`, `capabilities`, a `ResolvedModel`'s description/`goodFor`)
are catalog and provider-template metadata about AI models, not personal or
sensitive data, and this file neither stores nor transmits anything — it is a
pure, synchronous computation over its arguments.

## Logging

Not applicable: `ModelUseFacet.swift` contains no `Logger`, `os_log`, or
`print` call of any kind.

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
| 1.0.1 | 2026-09-24 | Mike Fullerton | Compliance links moved to the agenticdevelopercookbook compliance scheme |
