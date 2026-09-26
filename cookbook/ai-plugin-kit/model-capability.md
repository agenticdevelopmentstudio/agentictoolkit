---
id: 4ebd01d4-1326-42fa-83ba-58b0aebb31c7
title: ModelCapability
domain: agentictoolkit://cookbook/ai-plugin-kit/model-capability
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "AIPluginKit's yes/no capability axis (tools, reasoning, vision, conversation) for a model, matched against gateway-reported names with per-case fallbacks."
platforms:
- swift
- macos
tags:
- ai-plugin
- capability
- enum
- sendable
- foundation
depends-on:
- agentictoolkit://cookbook/ai-plugin-kit/ai-model-catalog
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

# ModelCapability

## Overview

`ModelCapability` (`packages/apple/AgenticToolkit/AIPluginKit/ModelCapability.swift`)
is a `String`-backed, `CaseIterable`, `Sendable`, `Codable` enum with four cases —
`tools`, `reasoning`, `vision`, `conversation` — representing the yes/no axis a
model either has or doesn't, as distinct from `ModelUseFacet`'s "what is it good
for" axis. Three of the four (`tools`, `reasoning`, `vision`) are hard capabilities
a serving gateway can assert directly, reported under many different spellings
(`function_calling` vs. `functionCalling` vs. `tool_use`, and so on); the fourth,
`conversation`, has no gateway flag at all and is derived from the model's prose
via `ModelUseFacet`. The type is a **logic** component — no visual surface — used
so a UI can render one column per capability with a check mark rather than a
badge string that can't be scanned down a column. It is pure: every function is a
static function of its arguments, and the type carries no stored state beyond its
own raw value.

## Behavioral Requirements

- **capability-cases**: `ModelCapability` MUST be a `String`-backed,
  `CaseIterable`, `Sendable`, `Codable` enum with exactly four cases —
  `tools`, `reasoning`, `vision`, `conversation` — whose raw values equal
  their case names.
- **title-labels**: `title` MUST return `"Tools"` for `.tools`,
  `"Reasoning"` for `.reasoning`, `"Vision"` for `.vision`, and `"Chat"` for
  `.conversation` — note `.conversation`'s label is `"Chat"`, not
  `"Conversation"`.
- **detail-tooltips**: `detail` MUST return `"Calls tools / functions you
  supply"` for `.tools`, `"Thinks step by step before answering"` for
  `.reasoning`, `"Accepts images as input"` for `.vision`, and `"Built for
  chat, assistants and personas"` for `.conversation`.
- **reported-spelling-vocabulary**: For `.tools`, `.reasoning`, and
  `.vision`, `reports(_:in:)` MUST treat each case's own fixed list of
  spellings as reporting that capability — `.tools`: `tools`, `tool_use`,
  `tool-use`, `function_calling`, `functioncalling`, `function-calling`,
  `functions`; `.reasoning`: `reasoning`, `thinking`, `extended_thinking`,
  `extended-thinking`; `.vision`: `vision`, `image`, `images`,
  `image_input`, `multimodal`.
- **reports-case-insensitive-match**: `reports(_:in:)` MUST match a
  `capabilities` entry against the case's spelling list case-insensitively
  (the entry is lowercased before comparison) and MUST return `true` as
  soon as one entry matches any spelling in the list.
- **reports-false-without-match**: `reports(_:in:)` MUST return `false`
  when no entry of `capabilities` matches, case-insensitively, any spelling
  in the capability's list, including when `capabilities` is empty.
- **conversation-never-self-reported**: `.conversation`'s spelling list
  MUST be empty, so `reports(.conversation, in:)` MUST return `false` for
  any `capabilities` array, including one containing `"chat"` or
  `"conversation"`.
- **reports-resolved-model-overload**: `reports(_:_:)`, taking an
  `AIModelCatalog.ResolvedModel`, MUST return the same result as
  `reports(_:in:)` called with that model's `capabilities` array.
- **has-short-circuits-on-report**: `has(_:_:extraText:)` MUST return
  `true` immediately whenever `reports(capability, info)` is `true`,
  without evaluating any per-case fallback.
- **has-tools-fallback-to-curated-flag**: When `.tools` is not reported,
  `has(_:_:extraText:)` MUST return `info.tools == true` — a `nil` or
  `false` `tools` value both yield `false`.
- **has-conversation-fallback-to-facets**: When `.conversation` is not
  reported (always true, per `conversation-never-self-reported`),
  `has(_:_:extraText:)` MUST return whether
  `ModelUseFacet.facets(for: info, extraText: extraText)` contains
  `.conversation`.
- **has-reasoning-vision-never-inferred**: When `.reasoning` or `.vision`
  is not reported, `has(_:_:extraText:)` MUST return `false`
  unconditionally — it MUST NOT consult `info.description`,
  `info.goodFor`, or `extraText` for either of these two cases.
- **capabilities-of-order**: `capabilities(of:extraText:)` MUST return the
  subsequence of `allCases` (declaration order: `tools`, `reasoning`,
  `vision`, `conversation`) for which `has(_:_:extraText:)` is `true`,
  preserving that order and omitting every case for which it is `false`.
- **pure-and-stateless**: `ModelCapability` MUST hold no stored instance
  state beyond its raw value and MUST perform no I/O; every static
  function on it MUST be a pure function of its arguments, so repeated
  calls with the same arguments MUST return the same result.

## Appearance

Not applicable — this is a capability enum with no rendering of its own,
not a visual component.

## States

Not applicable — this is a capability enum with no rendering of its own,
not a visual component. Its one runtime distinction — "gateway-reported"
versus "fallback-derived" — is captured under Behavioral Requirements
(`has-short-circuits-on-report` and the per-case fallback requirements),
not as a visual-state table.

## Accessibility

Not applicable — this is a capability enum with no rendering of its own,
not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| MC-001 | reported-spelling-vocabulary, reports-case-insensitive-match | `ModelCapability.reports(.tools, in: [spelling])` for each of `"tools"`, `"Tools"`, `"tool_use"`, `"function_calling"`, `"functionCalling"` | Returns `true` for every spelling — `ModelCapabilityTests.reportedSpellings` |
| MC-002 | reported-spelling-vocabulary | `ModelCapability.reports(.reasoning, in: ["thinking"])` | `true` — `ModelCapabilityTests.reportedSpellings` |
| MC-003 | reported-spelling-vocabulary | `ModelCapability.reports(.vision, in: ["multimodal"])` | `true` — `ModelCapabilityTests.reportedSpellings` |
| MC-004 | reports-false-without-match | `ModelCapability.reports(.vision, in: ["tools", "reasoning"])` | `false` — an unrelated reported capability is not evidence — `ModelCapabilityTests.reportedSpellings` |
| MC-005 | conversation-never-self-reported | `ModelCapability.reports(.conversation, in: ["chat"])` | `false` — `ModelCapabilityTests.reportedSpellings` |
| MC-006 | has-tools-fallback-to-curated-flag, capabilities-of-order | `let m = ResolvedModel(id: "m", capabilities: ["vision"], tools: true)`; `ModelCapability.has(.tools, m)`; `ModelCapability.capabilities(of: m)` | `has(.tools, m) == true`; `capabilities(of: m) == [.tools, .vision]` — `ModelCapabilityTests.curatedToolsFlag` |
| MC-007 | has-conversation-fallback-to-facets | `ModelCapability.has(.conversation, ResolvedModel(id: "m"))` (no `description`, `goodFor`, or `extraText`) | `false` — `ModelCapabilityTests.conversationFromProse` |
| MC-008 | has-conversation-fallback-to-facets, has-short-circuits-on-report | `ModelCapability.has(.conversation, ResolvedModel(id: "m"), extraText: "A chat assistant model")` | `true` — `ModelCapabilityTests.conversationFromProse` |
| MC-009 | capabilities-of-order | `ModelCapability.capabilities(of: ResolvedModel(id: "m"), extraText: "A chat assistant model")` | `[.conversation]` (no other case present) — `ModelCapabilityTests.conversationFromProse` |
| MC-010 | has-conversation-fallback-to-facets | `ModelCapability.has(.conversation, ResolvedModel(id: "m", description: "Built for conversation"))` | `true` — derived from `description` alone, no `extraText` needed — `ModelCapabilityTests.conversationFromProse` |
| MC-011 | has-reasoning-vision-never-inferred | `let prose = ResolvedModel(id: "m", description: "Exceptional reasoning over images and charts")`; `has(.reasoning, prose)`; `has(.vision, prose)` | Both `false` — prose is not a gateway assertion — `ModelCapabilityTests.hardCapabilitiesAreNotInferred` |
| MC-012 | title-labels, detail-tooltips | `ModelCapability.conversation.title`; `ModelCapability.conversation.detail` | `"Chat"`; `"Built for chat, assistants and personas"` — traced to the `title`/`detail` switch statements in `ModelCapability.swift` (no dedicated test in the given suite) |
| MC-013 | capability-cases | `ModelCapability.allCases`; `ModelCapability(rawValue: "tools")` | `allCases == [.tools, .reasoning, .vision, .conversation]`; `ModelCapability(rawValue: "tools") == .tools` — traced to the `enum ModelCapability: String, CaseIterable` declaration (no dedicated test in the given suite) |
| MC-014 | reports-resolved-model-overload | `ModelCapability.reports(.vision, ResolvedModel(id: "m", capabilities: ["multimodal"]))` | `true`, identical to `reports(.vision, in: ["multimodal"])` — traced to `reports(_:_:)` forwarding to `reports(_:in:)` (no dedicated test in the given suite) |
| MC-015 | pure-and-stateless | `ModelCapability.reports(.tools, in: ["tools"])` called twice in sequence, and again from two concurrent `Task`s in a `TaskGroup` | Every call returns `true` with no observable difference and no synchronization required — traced to `ModelCapability` and its static functions carrying no stored mutable state (no dedicated concurrency test in the given suite) |

## Edge Cases

- **Empty `capabilities` array.** `reports(_:in:)` called with
  `capabilities: []` MUST return `false` for every case — `[].contains`
  is `false` for any spelling set, and no crash occurs. MUST.
- **Bare `ResolvedModel` with no evidence.** A `ResolvedModel` with no
  `description`, `goodFor`, `capabilities`, or `tools` set MUST have
  `has(_:_:)` return `false` for every case except when `extraText` alone
  supplies conversation evidence — traced to `conversationFromProse`'s
  `bare` fixture. MUST.
- **Boundary values: not applicable in the numeric sense.** The only
  bounded input is `ModelCapability` itself, a fixed four-case enum with
  no numeric range to bound. `capabilities: [String]` and `extraText:
  String?` are unbounded collections/strings with no length check
  anywhere in the source.
- **Concurrent access.** `ModelCapability` is `Sendable`; every static
  function is a pure function of its arguments with no shared mutable
  state, and `AIModelCatalog.ResolvedModel` is a `Sendable`, `Equatable`
  value type built from `let` properties. Concurrent calls from any
  isolation domain MUST be safe with no additional synchronization —
  this is safe by construction, not merely untested.
- **Error states: not applicable.** No function in `ModelCapability.swift`
  throws, returns an error type, or calls anything that can fail;
  `reports`, `has`, and `capabilities(of:)` are total functions over
  their arguments.
- **Offline/disconnected: not applicable.** `ModelCapability.swift`
  performs no network or file I/O; it operates only on in-memory
  `String`s and an already-resolved `AIModelCatalog.ResolvedModel` value.
- **Duplicate/redundant spellings.** `capabilities: ["tools", "tool_use",
  "TOOLS"]` MUST still yield `reports(.tools, in:) == true` — matching one
  entry is sufficient, and repeated matches change nothing observable.
  MUST.
- **Unrecognized capability string.** `capabilities: ["moonwalk"]` MUST
  NOT match any case; `reports` MUST return `false` for all four cases,
  and `has(.tools, ...)` still falls back to `info.tools` rather than
  treating the unknown string as evidence. MUST.
- **`extraText` present but empty.** `extraText: ""` MUST behave
  identically to `extraText: nil` for word-matching purposes:
  `ModelUseFacet.facets` joins the non-`nil` text pieces with a space,
  and an empty piece contributes no additional words to match against.
  MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `capability` | `ModelCapability` | — (caller-selected case) | The `self` receiver of `reports(_:in:)`/`reports(_:_:)`, or the case under test inside `has`/`capabilities(of:)`. |
| `capabilities` | `[String]` | — (required) | Gateway-reported capability strings passed to `reports(_:in:)`, matched case-insensitively against the fixed spelling vocabulary. |
| `info` | `AIModelCatalog.ResolvedModel` | — (required) | The resolved model `reports(_:_:)`, `has(_:_:extraText:)`, and `capabilities(of:extraText:)` inspect for `capabilities`, `tools`, `description`, and `goodFor`. |
| `extraText` | `String?` | `nil` | Additional prose (e.g. a local server's fetched blurb) folded into the text `ModelUseFacet.facets` derives `.conversation` from; has no effect on `.tools`, `.reasoning`, or `.vision`. |

## Deep Linking

Not applicable: `ModelCapability.swift` defines no URL, route, or
navigable destination — it is a data enum with no navigation surface.

## Localization

`title` and `detail` are hardcoded English-only string literals returned
directly from `switch` statements, with no string-key lookup, no
`NSLocalizedString`/`String(localized:)` call, and no `.strings`/
`.xcstrings` catalog entry anywhere in the source.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — no string-key mechanism) | `"Tools"` / `"Reasoning"` / `"Vision"` / `"Chat"` | `title`: "Column header / badge label" per the source doc comment |
| (none — no string-key mechanism) | `"Calls tools / functions you supply"` / `"Thinks step by step before answering"` / `"Accepts images as input"` / `"Built for chat, assistants and personas"` | `detail`: "Tooltip copy for the column header" per the source doc comment |

## Accessibility Options

Not applicable: `ModelCapability.swift` renders nothing and reads no
accessibility display setting (Reduce Motion, Increase Contrast,
Differentiate Without Color) — it only supplies label strings a caller's
view may later display.

## Feature Flags

Not applicable: `ModelCapability.swift` contains no feature-flag or
remote-config check of any kind.

## Analytics

Not applicable: `ModelCapability.swift` emits no analytics event — it has
no telemetry call of any kind.

## Privacy

Not applicable: `ModelCapability` carries no user data, credentials, or
tokens. It operates only on public model metadata (capability strings,
description prose) already resolved by `AIModelCatalog`/
`AIPluginDescriptor`, and reads or writes nothing to disk or network
itself.

## Logging

Not applicable: `ModelCapability.swift` contains no `Logger`/`os_log`/
`print` call of any kind.

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
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
