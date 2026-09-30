<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-model-capability · source: ai-plugin-runtime-ai-plugin-kit-model-capability.md -->

**Rules** (cite as `implement-ai-plugin-2/runtime-ai-plugin-kit-model-capability#<slug>`):

- `capability-cases` MUST
- `title-labels` MUST
- `detail-tooltips` MUST
- `reported-spelling-vocabulary` MUST
- `reports-case-insensitive-match` MUST
- `reports-false-without-match` MUST
- `conversation-never-self-reported` MUST
- `reports-resolved-model-overload` MUST
- `has-short-circuits-on-report` MUST
- `has-tools-fallback-to-curated-flag` MUST
- `has-conversation-fallback-to-facets` MUST
- `has-reasoning-vision-never-inferred` MUST
- `capabilities-of-order` MUST
- `pure-and-stateless` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `capability` | `ModelCapability` | — (caller-selected case) | The `self` receiver of `reports(_:in:)`/`reports(_:_:)`, or the case under test inside `has`/`capabilities(of:)`. |
| `capabilities` | `[String]` | — (required) | Gateway-reported capability strings passed to `reports(_:in:)`, matched case-insensitively against the fixed spelling vocabulary. |
| `info` | `AIModelCatalog.ResolvedModel` | — (required) | The resolved model `reports(_:_:)`, `has(_:_:extraText:)`, and `capabilities(of:extraText:)` inspect for `capabilities`, `tools`, `description`, and `goodFor`. |
| `extraText` | `String?` | `nil` | Additional prose (e.g. a local server's fetched blurb) folded into the text `ModelUseFacet.facets` derives `.conversation` from; has no effect on `.tools`, `.reasoning`, or `.vision`. |

## Localization

`title` and `detail` are hardcoded English-only string literals returned
directly from `switch` statements, with no string-key lookup, no
`NSLocalizedString`/`String(localized:)` call, and no `.strings`/
`.xcstrings` catalog entry anywhere in the source.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — no string-key mechanism) | `"Tools"` / `"Reasoning"` / `"Vision"` / `"Chat"` | `title`: "Column header / badge label" per the source doc comment |
| (none — no string-key mechanism) | `"Calls tools / functions you supply"` / `"Thinks step by step before answering"` / `"Accepts images as input"` / `"Built for chat, assistants and personas"` | `detail`: "Tooltip copy for the column header" per the source doc comment |

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

