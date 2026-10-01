---
id: 4ebd01d4-1326-42fa-83ba-58b0aebb31c7
title: Model Capability
domain: agentictoolkit://cookbook/ai/models/model-capability
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A yes/no capability axis (tools, reasoning, vision, conversation) for
  a model, matched against gateway-reported names with per-case fallbacks.
platforms:
- swift
- macos
tags:
- ai-plugin
- capability
depends-on:
- agentictoolkit://cookbook/ai/models/model-catalog
related: []
references:
- packages/apple/AgenticToolkit/AIPluginKit/ModelCapability.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/ModelUseFacet.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/AIModelCatalog.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/ModelCapabilityTests.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/ModelUseFacetTests.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Model Capability

## Overview

This is a yes/no capability axis for a model — four cases, `tools`,
`reasoning`, `vision`, `conversation` — representing whether a model
either has or doesn't have each capability, as distinct from the model's
use facets, which capture a "what is it good for" axis instead. Three of
the four (`tools`, `reasoning`, `vision`) are hard capabilities a serving
gateway can assert directly, reported under many different spellings
(`function_calling` vs. `functionCalling` vs. `tool_use`, and so on); the
fourth, `conversation`, has no gateway flag at all and is derived from the
model's prose via its use facets. This is a **logic** component — no
visual surface — used so a UI can render one column per capability with a
check mark rather than a badge string that can't be scanned down a column.
It is pure: every operation is a function of its arguments, and the type
carries no stored state beyond its own raw value.

## Behavioral Requirements

- **capability-cases**: This capability type MUST expose exactly four
  cases — `tools`, `reasoning`, `vision`, `conversation` — each comparable
  for equality, safe to pass across concurrent boundaries, encodable and
  decodable, and enumerable as a complete set, with each case's raw
  string form equal to its case name.
- **title-labels**: The title MUST return `"Tools"` for `tools`,
  `"Reasoning"` for `reasoning`, `"Vision"` for `vision`, and `"Chat"` for
  `conversation` — note `conversation`'s label is `"Chat"`, not
  `"Conversation"`.
- **detail-tooltips**: The detail text MUST return `"Calls tools /
  functions you supply"` for `tools`, `"Thinks step by step before
  answering"` for `reasoning`, `"Accepts images as input"` for `vision`,
  and `"Built for chat, assistants and personas"` for `conversation`.
- **reported-spelling-vocabulary**: For `tools`, `reasoning`, and
  `vision`, the reports check MUST treat each case's own fixed list of
  spellings as reporting that capability — `tools`: `tools`, `tool_use`,
  `tool-use`, `function_calling`, `functioncalling`, `function-calling`,
  `functions`; `reasoning`: `reasoning`, `thinking`, `extended_thinking`,
  `extended-thinking`; `vision`: `vision`, `image`, `images`,
  `image_input`, `multimodal`.
- **reports-case-insensitive-match**: The reports check MUST match a
  capabilities entry against the case's spelling list case-insensitively
  (the entry is lowercased before comparison) and MUST return `true` as
  soon as one entry matches any spelling in the list.
- **reports-false-without-match**: The reports check MUST return `false`
  when no entry of the capabilities list matches, case-insensitively, any
  spelling in the capability's list, including when the list is empty.
- **conversation-never-self-reported**: `conversation`'s spelling list
  MUST be empty, so the reports check for `conversation` MUST return
  `false` for any capabilities list, including one containing `"chat"` or
  `"conversation"`.
- **reports-resolved-model-overload**: The reports check taking a resolved
  model directly MUST return the same result as the reports check called
  with that model's capabilities list.
- **has-short-circuits-on-report**: The has check MUST return `true`
  immediately whenever the reports check for that capability is `true`,
  without evaluating any per-case fallback.
- **has-tools-fallback-to-curated-flag**: When `tools` is not reported,
  the has check MUST return whether the resolved model's tools flag
  equals `true` — an absent or `false` tools value both yield `false`.
- **has-conversation-fallback-to-facets**: When `conversation` is not
  reported (always true, per `conversation-never-self-reported`), the has
  check MUST return whether the model's computed use facets, given the
  resolved model and any extra text, contain `conversation`.
- **has-reasoning-vision-never-inferred**: When `reasoning` or `vision` is
  not reported, the has check MUST return `false` unconditionally — it
  MUST NOT consult the model's description, its "good for" text, or the
  extra text for either of these two cases.
- **capabilities-of-order**: Computing the capabilities of a model MUST
  return the subsequence of all cases (declaration order: `tools`,
  `reasoning`, `vision`, `conversation`) for which the has check is
  `true`, preserving that order and omitting every case for which it is
  `false`.
- **pure-and-stateless**: This type MUST hold no stored instance state
  beyond its raw value and MUST perform no I/O; every operation on it
  MUST be a pure function of its arguments, so repeated calls with the
  same arguments MUST return the same result.

## Appearance

Not applicable — this is a capability enumeration with no rendering of its
own, not a visual component.

## States

Not applicable — this is a capability enumeration with no rendering of its
own, not a visual component. Its one runtime distinction —
"gateway-reported" versus "fallback-derived" — is captured under
Behavioral Requirements (`has-short-circuits-on-report` and the per-case
fallback requirements), not as a visual-state table.

## Accessibility

Not applicable — this is a capability enumeration with no rendering of its
own, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| MC-001 | reported-spelling-vocabulary, reports-case-insensitive-match | Check whether `tools` is reported for capabilities lists containing each of `"tools"`, `"Tools"`, `"tool_use"`, `"function_calling"`, `"functionCalling"`, one spelling at a time. | Returns `true` for every spelling. |
| MC-002 | reported-spelling-vocabulary | Check whether `reasoning` is reported for a capabilities list containing `"thinking"`. | `true`. |
| MC-003 | reported-spelling-vocabulary | Check whether `vision` is reported for a capabilities list containing `"multimodal"`. | `true`. |
| MC-004 | reports-false-without-match | Check whether `vision` is reported for a capabilities list containing `"tools"` and `"reasoning"`. | `false` — an unrelated reported capability is not evidence. |
| MC-005 | conversation-never-self-reported | Check whether `conversation` is reported for a capabilities list containing `"chat"`. | `false`. |
| MC-006 | has-tools-fallback-to-curated-flag, capabilities-of-order | For a resolved model with id `"m"`, capabilities `["vision"]`, and tools `true`: check whether `tools` is present, and compute the model's capabilities. | The `tools` check is `true`; the computed capabilities are `[tools, vision]`. |
| MC-007 | has-conversation-fallback-to-facets | Check whether `conversation` is present for a resolved model with id `"m"` and no description, "good for" text, or extra text. | `false`. |
| MC-008 | has-conversation-fallback-to-facets, has-short-circuits-on-report | Check whether `conversation` is present for a resolved model with id `"m"` and extra text `"A chat assistant model"`. | `true`. |
| MC-009 | capabilities-of-order | Compute the capabilities of a resolved model with id `"m"` and extra text `"A chat assistant model"`. | `[conversation]` (no other case present). |
| MC-010 | has-conversation-fallback-to-facets | Check whether `conversation` is present for a resolved model with id `"m"` and description `"Built for conversation"`. | `true` — derived from the description alone, no extra text needed. |
| MC-011 | has-reasoning-vision-never-inferred | For a resolved model with id `"m"` and description `"Exceptional reasoning over images and charts"`, check whether `reasoning` is present and whether `vision` is present. | Both `false` — prose is not a gateway assertion. |
| MC-012 | title-labels, detail-tooltips | Read the title and detail text for `conversation`. | `"Chat"`; `"Built for chat, assistants and personas"`. |
| MC-013 | capability-cases | Read the full set of cases, and look up the case whose raw value is `"tools"`. | The full set is `[tools, reasoning, vision, conversation]`; the case looked up by raw value `"tools"` is `tools`. |
| MC-014 | reports-resolved-model-overload | Check whether `vision` is reported for a resolved model with id `"m"` and capabilities `["multimodal"]`, using the resolved-model overload directly. | `true`, identical to checking whether `vision` is reported for a capabilities list containing `"multimodal"`. |
| MC-015 | pure-and-stateless | Check whether `tools` is reported for a capabilities list containing `"tools"`, called twice in sequence, and again from two concurrent tasks. | Every call returns `true` with no observable difference and no synchronization required. |

## Edge Cases

- **Empty capabilities list.** The reports check called with an empty
  capabilities list MUST return `false` for every case — an empty list
  contains no match for any spelling set, and no crash occurs. MUST.
- **Bare resolved model with no evidence.** A resolved model with no
  description, "good for" text, capabilities, or tools flag set MUST have
  the has check return `false` for every case except when extra text
  alone supplies conversation evidence. MUST.
- **Boundary values: not applicable in the numeric sense.** The only
  bounded input is this capability type itself, a fixed four-case type
  with no numeric range to bound. The capabilities list and the extra
  text are unbounded collections/strings with no length check anywhere in
  the source.
- **Concurrent access.** This type is safe to pass across concurrent
  boundaries; every operation is a pure function of its arguments with no
  shared mutable state, and the resolved model is itself a value type
  comparable for equality and safe to pass across concurrent boundaries,
  built from immutable fields. Concurrent calls from any context MUST be
  safe with no additional synchronization — this is safe by construction,
  not merely untested.
- **Error states: not applicable.** No operation on this type raises an
  error, returns an error type, or calls anything that can fail; the
  reports check, has check, and capabilities-of computation are total
  functions over their arguments.
- **Offline/disconnected: not applicable.** This component performs no
  network or file I/O; it operates only on in-memory strings and an
  already-resolved model value.
- **Duplicate/redundant spellings.** A capabilities list containing
  `"tools"`, `"tool_use"`, and `"TOOLS"` together MUST still yield a
  `true` reports check for `tools` — matching one entry is sufficient,
  and repeated matches change nothing observable. MUST.
- **Unrecognized capability string.** A capabilities list containing
  `"moonwalk"` MUST NOT match any case; the reports check MUST return
  `false` for all four cases, and the has check for `tools` still falls
  back to the resolved model's tools flag rather than treating the
  unknown string as evidence. MUST.
- **Extra text present but empty.** An empty extra-text string MUST
  behave identically to an absent extra text for word-matching purposes:
  the use-facets computation joins the non-empty text pieces with a
  space, and an empty piece contributes no additional words to match
  against. MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `capability` | capability type | — (caller-selected case) | The receiver of the reports check, or the case under test inside the has check / capabilities-of computation. |
| `capabilities` | array of strings | — (required) | Gateway-reported capability strings passed to the reports check, matched case-insensitively against the fixed spelling vocabulary. |
| `info` | resolved model | — (required) | The resolved model the reports check, has check, and capabilities-of computation inspect for capabilities, the tools flag, description, and "good for" text. |
| `extraText` | optional string | none | Additional prose (e.g. a local server's fetched blurb) folded into the text the use-facets computation derives `conversation` from; has no effect on `tools`, `reasoning`, or `vision`. |

## Deep Linking

Not applicable: this component defines no URL, route, or navigable
destination — it is a data type with no navigation surface.

## Localization

The title and detail text are hardcoded English-only string literals
returned directly, with no string-key lookup and no localization-catalog
entry anywhere in the source.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — no string-key mechanism) | `"Tools"` / `"Reasoning"` / `"Vision"` / `"Chat"` | The title text: column header / badge label. |
| (none — no string-key mechanism) | `"Calls tools / functions you supply"` / `"Thinks step by step before answering"` / `"Accepts images as input"` / `"Built for chat, assistants and personas"` | The detail text: tooltip copy for the column header. |

## Accessibility Options

Not applicable: this component renders nothing and reads no accessibility
display setting (Reduce Motion, Increase Contrast, Differentiate Without
Color) — it only supplies label strings a caller's view may later display.

## Feature Flags

Not applicable: this component contains no feature-flag or remote-config
check of any kind.

## Analytics

Not applicable: this component emits no analytics event — it has no
telemetry call of any kind.

## Privacy

Not applicable: this component carries no user data, credentials, or
tokens. It operates only on public model metadata (capability strings,
description prose) already resolved elsewhere, and reads or writes
nothing to disk or network itself.

## Logging

Not applicable: this component contains no logging call of any kind.

## Platform Notes

- **SwiftUI**: The source (`packages/apple/AgenticToolkit/AIPluginKit/ModelCapability.swift`,
  tests `Tests/AIPluginKitTests/ModelCapabilityTests.swift`) has no
  SwiftUI dependency of its own — it is plain Swift, framework-agnostic.
  A SwiftUI consumer would render `ForEach(ModelCapability.allCases)` as a
  table column, using `title` as the header and `has(_:_:)`/
  `capabilities(of:)` to decide the check mark, with no change to this
  type.
- **Compose**: Model as a Kotlin `enum class ModelCapability(val
  rawValue: String) { TOOLS("tools"), REASONING("reasoning"),
  VISION("vision"), CONVERSATION("conversation") }` with `title`/`detail`
  computed properties mirroring the Swift `switch` statements, and a
  private `reportedNames: List<String>` per case. Implement `reports`,
  `has`, and `capabilitiesOf` as functions on a companion `object`, using
  `.lowercase()` for the case-insensitive comparison and `entries` (the
  Kotlin `enum class` equivalent of `CaseIterable.allCases`, in
  declaration order) for `capabilitiesOf`.
- **React/Web**: `type ModelCapability = "tools" | "reasoning" | "vision"
  | "conversation"` as a string union, plus `const ALL_CAPABILITIES:
  ModelCapability[] = ["tools", "reasoning", "vision", "conversation"]`
  mirroring `allCases`' declaration order. `title`/`detail` as `Record<
  ModelCapability, string>` lookup maps, `reportedNames` as `Record<
  ModelCapability, string[]>`, and `reports`/`has`/`capabilitiesOf` as
  pure functions over a `ResolvedModel` interface, using
  `.toLowerCase()` plus `Array.prototype.includes` for the
  case-insensitive match.
- **AppKit / UIKit**: No AppKit- or UIKit-specific API appears in this
  file; it is UI-framework-agnostic. It is consumed today by AppKit
  table/column code that renders one column per `ModelCapability` with a
  check mark keyed by `has(_:_:)` — nothing in this type changes to run
  under UIKit, only the consuming view.
- **WinUI 3**: This is the platform this recipe exists to steer. Model
  `ModelCapability` as a C# `enum ModelCapability { Tools, Reasoning,
  Vision, Conversation }` with a
  `[JsonConverter(typeof(JsonStringEnumConverter))]` using a naming
  policy that lowercases case names, so it round-trips through
  `System.Text.Json` as the same `tools`/`reasoning`/`vision`/
  `conversation` wire strings `Codable` produces. Give `Title`/`Detail`
  as `string`-returning `switch` expressions mirroring the Swift
  `title`/`detail` computed properties exactly. Store the per-case
  spelling vocabulary as a `static readonly Dictionary<ModelCapability,
  string[]> ReportedNames`, and implement `Reports(ModelCapability,
  IEnumerable<string>)` as `capabilities.Any(c =>
  names.Contains(c.ToLowerInvariant()))` (mirroring the Swift `Set` +
  case-insensitive `contains`). Implement `Has(ModelCapability,
  ResolvedModel, string? extraText = null)` with the same
  report-first-then-per-case-fallback short circuit (`ResolvedModel.Tools
  == true` for Tools; a `ModelUseFacet` port's `Facets(...)` for
  Conversation; a hard `false` for Reasoning/Vision). Implement
  `CapabilitiesOf(ResolvedModel, string? extraText = null)` as
  `Enum.GetValues<ModelCapability>().Where(c => Has(c, info,
  extraText))`, which preserves declaration order the same way
  `CaseIterable.allCases` does in Swift. Bind `Title` to an
  `ItemsRepeater`/`GridView` column header `TextBlock` and `Detail` to
  that header's `ToolTipService.ToolTip` attached property, matching the
  Swift doc comment's own description of these two properties' UI role.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/ModelCapability.swift` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |

Notes: no-hardcoded-strings fails because `title` and `detail` return
English-only literals with no localization mechanism (see Localization).
idempotent-operations passes because every function on `ModelCapability`
is a pure, stateless function of its arguments (see `pure-and-stateless`
and the Concurrent access edge case). separation-of-concerns passes
because the source's own doc comment draws an explicit boundary between
this type's "does it have this" axis and `ModelUseFacet`'s "what's it
good for" axis, and derives `.conversation` by calling into
`ModelUseFacet` rather than duplicating its heuristic.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/models/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
