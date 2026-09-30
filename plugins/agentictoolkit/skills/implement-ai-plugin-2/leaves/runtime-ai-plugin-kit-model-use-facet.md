<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-model-use-facet · source: ai-plugin-runtime-ai-plugin-kit-model-use-facet.md -->

**Rules** (cite as `implement-ai-plugin-2/runtime-ai-plugin-kit-model-use-facet#<slug>`):

- `facet-cases` MUST
- `facet-title` MUST
- `facet-detail` MUST
- `capability-implied-facets` MUST
- `capability-evidence-checked-first` MUST
- `capability-string-matching-is-delegated` MUST
- `word-tokenization` MUST
- `word-prefix-anchoring` MUST
- `phrase-matching-on-raw-text` MUST
- `per-facet-evidence-lists-are-fixed` MUST
- `resolved-model-evidence-sources` MUST
- `model-id-excluded-from-evidence` MUST
- `empty-evidence-yields-empty-set` MUST
- `facets-are-a-set` MUST
- `filter-empty-selection-passes-all` MUST
- `filter-unknown-model-passes` MUST
- `filter-any-of-semantics` MUST
- `value-type-concurrency-safety` MUST
- `codable-round-trip` MUST
- `exhaustive-derivation-switches` MUST
- `labels-ten-tooltips-ship-english-regardless-host` MUST — title and detail are hardcoded, English-only String literals returned directly from a switch over self …

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `text` | `String` | required | Evidence text passed to `facets(text:capabilities:)` — normally a model's description and/or `goodFor` blurb, already joined by the caller. |
| `capabilities` | `[String]` | `[]` | Reported capability strings passed alongside `text`; matched via `ModelCapability.reports(_:in:)` for the three capability-implied facets. |
| `model` | `AIModelCatalog.ResolvedModel` | required | Input to `facets(for:extraText:)`; its `description`, `goodFor`, and `capabilities` fields are read, its `id` is deliberately not. |
| `extraText` | `String?` | `nil` | Additional description text not carried by the catalog (e.g. a local server's live-fetched blurb for a model the catalog has never seen), appended to `model.description`/`goodFor` before derivation. |
| `selected` | `Set<ModelUseFacet>` | caller-supplied | The set of uses a filter control has checked, passed to `matches(facets:selected:)`; an empty set is the default, unfiltered state of the "Good for" menu (`ModelChooserViewController.swift`). |

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

