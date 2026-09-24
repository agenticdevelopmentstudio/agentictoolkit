---
id: 5069f11f-e0c6-40c3-92ca-6152b8df3bc2
title: ModelFitPolicy
domain: agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-model-fit-policy
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure policy mapping a local model's disk size, RAM, thresholds, and memory
  pressure to a fit tier and allow/block/defer verdict shared by guard and pickers.
platforms:
- swift
- macos
tags:
- ai-plugin
- model-fit
- memory-budget
- policy
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/AIPluginKit/ModelFitPolicy.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/ModelFitPolicyTests.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/LocalInferenceGuard.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/ModelChooserContent.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/AIPlugins/Settings/ModelChooserViewController.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# ModelFitPolicy

## Overview

`ModelFitPolicy` is `AIPluginKit`'s toolkit-level policy for whether a local
("loopback") model should run on the current machine. Per the source's own
doc comment, it is "a pure function from (model size, machine RAM, thresholds,
pressure) to a tier/verdict," kept at toolkit level "so every `AIPluginKit`
host shares one representation: `DaemonAIChat` enforces with it, app pickers
label with it, and the two cannot drift." Concretely, `LocalInferenceGuard`
enforces with it (its `verdict(model:baseURL:settings:)` calls
`ModelFitPolicy.verdict`) before `DaemonAIChat` dispatches a chat request to a
local model server, and the macOS model picker
(`ModelChooserContent`/`ModelChooserViewController`) labels candidate models
with it via `pickerLabel`/`fitInfo`. `ModelFitPolicy` is declared as a
case-less `enum` — an uninstantiable namespace — whose entire public surface
is `static` constants and pure functions; it holds no mutable state of its
own and performs no I/O.

## Behavioral Requirements

- **memory-pressure-cases**: `MemoryPressureLevel` MUST expose exactly three
  cases — `normal`, `warning`, and `critical` — as a `String`-raw-valued,
  `Sendable`, `Equatable` enum (`ModelFitPolicy.swift`).
- **tier-cases**: `ModelFitPolicy.Tier` MUST expose exactly three cases —
  `ok`, `warn`, and `block` — as an `Equatable`, `Sendable` enum.
- **verdict-cases**: `ModelFitPolicy.Verdict` MUST expose exactly three
  cases — `allow`, `block(reason: String)`, and `deferred(reason: String)` —
  as an `Equatable`, `Sendable` enum, with each refusal case carrying a
  human-readable reason string.
- **fit-info-shape**: `ModelFitPolicy.FitInfo` MUST be an `Equatable`,
  `Sendable` struct exposing immutable `text: String` and `tier: Tier`
  properties, constructible only through its public `init(text:tier:)`.
- **namespace-isolation**: `ModelFitPolicy` MUST be declared as a case-less
  `enum` — an uninstantiable namespace holding no stored instance state —
  whose public members are exclusively `static` constants and pure
  functions; since it declares no `Sendable`, `actor`, or `@MainActor`
  isolation of its own, every static member MUST be callable synchronously
  from any concurrency-isolation domain (an actor, a `@MainActor` context, or
  a `nonisolated` context) without an `await` hop.
- **resident-overhead-multiplier**: `ModelFitPolicy.residentOverheadMultiplier`
  MUST equal `1.2`.
- **estimated-bytes**: `estimatedBytes(diskBytes:)` MUST return
  `Int(Double(diskBytes) * residentOverheadMultiplier)`.
- **default-thresholds**: `ModelFitPolicy.defaultWarnPct` MUST equal `25` and
  `ModelFitPolicy.defaultBlockPct` MUST equal `50`.
- **threshold-setting-keys**: `ModelFitPolicy.warnPctKey` MUST equal the
  literal string `ai_guard_warn_pct` and `ModelFitPolicy.blockPctKey` MUST
  equal the literal string `ai_guard_block_pct`.
- **tier-unknown-size**: `tier(diskBytes:physicalRAM:warnPct:blockPct:)` MUST
  return `nil` when `diskBytes` is `nil`.
- **tier-zero-ram**: `tier` MUST return `nil` when `physicalRAM` is `0`.
- **tier-classification**: When `diskBytes` is non-nil and `physicalRAM` is
  greater than `0`, `tier` MUST compute `pct` as
  `estimatedBytes(diskBytes:) / physicalRAM * 100` and MUST return `.block`
  when `pct >= blockPct`, `.warn` when `pct >= warnPct` and `pct < blockPct`,
  and `.ok` when `pct < warnPct`.
- **tier-threshold-defaults**: `tier`, `fitInfo`, and `pickerLabel` MUST each
  default an omitted `warnPct` to `defaultWarnPct` and an omitted `blockPct`
  to `defaultBlockPct`.
- **pressure-verdict-normal**: `pressureVerdict(_:)` MUST return `.allow`
  when `pressure` is `.normal`.
- **pressure-verdict-elevated**: `pressureVerdict(_:)` MUST return
  `.deferred(reason:)` with a reason string of exactly the form
  `memory pressure is <pressure.rawValue>; deferring local inference` when
  `pressure` is `.warning` or `.critical`.
- **verdict-pressure-precedence**: `verdict(model:diskBytes:physicalRAM:warnPct:blockPct:pressure:)`
  MUST evaluate `pressureVerdict(pressure)` first and, whenever that result
  is `.deferred`, MUST return that exact `.deferred(reason:)` result without
  evaluating the size tier at all — regardless of `diskBytes`, `model`, or
  the thresholds.
- **verdict-required-thresholds**: `verdict`'s `warnPct` and `blockPct`
  parameters MUST carry no default value; the caller MUST supply both
  explicitly — unlike `tier`, `fitInfo`, and `pickerLabel`.
- **verdict-allow-non-block-tier**: Under `.normal` pressure, `verdict` MUST
  return `.allow` whenever the computed tier is `.ok`, `.warn`, or `nil`
  (unknown size) — only a `.block` tier with a known `diskBytes` yields a
  refusal.
- **verdict-block-reason-format**: When the computed tier is `.block` and
  `diskBytes` is known, `verdict` MUST return `.block(reason:)` with a
  reason string of exactly the form
  `<model> needs <footprintDescription> est.; block threshold is <blockPct>% of <gbString(physicalRAM)>`,
  where the embedded footprint description is computed from the estimated
  (not on-disk) resident bytes.
- **footprint-description-format**: `footprintDescription(estimatedBytes:physicalRAM:)`
  MUST return a string of exactly the form
  `~<gbString(estimatedBytes)> (~<ramPct(estimatedBytes, physicalRAM)>% of RAM)`.
- **fit-info-unknown**: `fitInfo(diskBytes:physicalRAM:warnPct:blockPct:)`
  MUST return `nil` when `diskBytes` is `nil` or when
  `tier(diskBytes:physicalRAM:warnPct:blockPct:)` returns `nil`.
- **fit-info-ok-text**: For an `.ok` tier, `fitInfo` MUST return
  `FitInfo(text: "<gbString(diskBytes)> (~<ramPct(estimatedBytes, physicalRAM)>% of RAM)", tier: .ok)`,
  displaying the on-disk size rather than the estimated resident size.
- **fit-info-warn-text**: For a `.warn` tier, `fitInfo` MUST return
  `FitInfo(text: "<gbString(diskBytes)> ⚠ large: ~<ramPct(estimatedBytes, physicalRAM)>% of RAM", tier: .warn)`.
- **fit-info-block-text**: For a `.block` tier, `fitInfo` MUST return
  `FitInfo(text: "<gbString(diskBytes)> — won't run: exceeds memory budget", tier: .block)`;
  unlike the `.ok`/`.warn` text, the block text MUST NOT include a
  RAM-percentage figure.
- **picker-label-unknown**: `pickerLabel(model:diskBytes:physicalRAM:warnPct:blockPct:)`
  MUST return `model` unchanged when
  `fitInfo(diskBytes:physicalRAM:warnPct:blockPct:)` returns `nil`.
- **picker-label-known**: `pickerLabel` MUST return the exact string
  `<model> — <fitInfo.text>` when `fitInfo` returns a non-nil value.
- **gb-string-format**: `gbString(_:)` MUST format `bytes` as `<value> GB`
  with the value rendered to exactly one decimal place at
  `Double(bytes) / 1_000_000_000`, using the `en_US_POSIX` locale regardless
  of the caller's current locale.
- **ram-pct-computation**: `ramPct(_:of:)` MUST return
  `Int((Double(bytes) / Double(physicalRAM) * 100).rounded())` — the nearest
  whole percentage, rounded half-away-from-zero per Swift's
  `Double.rounded()` default — when `physicalRAM` is non-zero.
- **ram-pct-zero-ram**: `ramPct(_:of:)` MUST return `0` when `physicalRAM`
  is `0`.

## Appearance

Not applicable — this is a stateless memory-fit policy, not a visual
component.

## States

Not applicable — this is a stateless memory-fit policy, not a visual
component.

## Accessibility

Not applicable — this is a stateless memory-fit policy, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| model-fit-policy-001 | tier-classification, tier-threshold-defaults | `tier(diskBytes: 12_500_000_000, physicalRAM: 64_000_000_000)` — thresholds omitted (`ModelFitPolicyTests.swift`, `tierBoundaries`). | `.ok` — est. 15.0 GB ≈ 23% of RAM, under the default 25% warn threshold. |
| model-fit-policy-002 | tier-classification | `tier(diskBytes: 14_000_000_000, physicalRAM: 64_000_000_000)` (`tierBoundaries`). | `.warn` — est. 16.8 GB ≈ 26% of RAM, at or above 25% and below 50%. |
| model-fit-policy-003 | tier-classification | `tier(diskBytes: 27_000_000_000, physicalRAM: 64_000_000_000)` (`tierBoundaries`). | `.block` — est. 32.4 GB ≈ 51% of RAM, at or above the default 50% block threshold. |
| model-fit-policy-004 | tier-unknown-size, tier-zero-ram | `tier(diskBytes: nil, physicalRAM: 64_000_000_000)` and `tier(diskBytes: 1, physicalRAM: 0)` (`unknownSizeHasNoTier`). | Both return `nil`. |
| model-fit-policy-005 | verdict-block-reason-format, footprint-description-format, verdict-required-thresholds | `verdict(model: "qwen3-coder-next:latest", diskBytes: 51_000_000_000, physicalRAM: 64_000_000_000, warnPct: 25, blockPct: 50, pressure: .normal)` (`verdictBlocksOverBudgetModel`). | `.block(reason:)` containing `"qwen3-coder-next:latest"`, `"~61.2 GB (~96% of RAM)"`, and `"50% of 64.0 GB"`. |
| model-fit-policy-006 | footprint-description-format, gb-string-format, ram-pct-computation | `footprintDescription(estimatedBytes: 24_000_000_000, physicalRAM: 64_000_000_000)` (`footprintDescriptionSharedCore`). | Returns exactly `"~24.0 GB (~38% of RAM)"`. |
| model-fit-policy-007 | fit-info-ok-text | `fitInfo(diskBytes: 8_900_000_000, physicalRAM: 64_000_000_000)` (`fitInfoStructured`). | `FitInfo(text: "8.9 GB (~17% of RAM)", tier: .ok)`. |
| model-fit-policy-008 | fit-info-warn-text | `fitInfo(diskBytes: 20_000_000_000, physicalRAM: 64_000_000_000)` (`fitInfoStructured`). | `FitInfo(text: "20.0 GB ⚠ large: ~38% of RAM", tier: .warn)`. |
| model-fit-policy-009 | fit-info-block-text | `fitInfo(diskBytes: 51_000_000_000, physicalRAM: 64_000_000_000)` (`fitInfoStructured`). | `FitInfo(text: "51.0 GB — won't run: exceeds memory budget", tier: .block)`. |
| model-fit-policy-010 | fit-info-unknown | `fitInfo(diskBytes: nil, physicalRAM: 64_000_000_000)` (`fitInfoStructured`). | `nil`. |
| model-fit-policy-011 | pressure-verdict-elevated, verdict-pressure-precedence | `verdict(model: "llama3.1:8b", diskBytes: diskBytes, physicalRAM: 64_000_000_000, warnPct: 25, blockPct: 50, pressure: .warning)` for `diskBytes` in `[4_900_000_000, nil]` (`verdictDefersUnderPressure`). | `.deferred(reason:)` containing `"memory pressure is warning"` in both cases, even with a known small size or an unknown size. |
| model-fit-policy-012 | verdict-allow-non-block-tier, pressure-verdict-normal | `verdict` with `pressure: .normal` for `diskBytes` 4.9 GB (`.ok`), 20 GB (`.warn`), and `nil` (unknown) at 64 GB RAM (`verdictAllowsOkWarnAndUnknownSize`). | `.allow` in all three cases. |
| model-fit-policy-013 | picker-label-known | `pickerLabel(model: "deepseek-coder-v2:16b", diskBytes: 8_900_000_000, physicalRAM: 64_000_000_000)` (`pickerLabels`). | Returns exactly `"deepseek-coder-v2:16b — 8.9 GB (~17% of RAM)"`. |
| model-fit-policy-014 | picker-label-known | `pickerLabel(model: "huge", diskBytes: 51_000_000_000, physicalRAM: 64_000_000_000)` (`pickerLabels`). | Returns exactly `"huge — 51.0 GB — won't run: exceeds memory budget"`. |
| model-fit-policy-015 | picker-label-unknown | `pickerLabel(model: "mystery", diskBytes: nil, physicalRAM: 64_000_000_000)` (`pickerLabels`). | Returns exactly `"mystery"`. |
| model-fit-policy-016 | estimated-bytes, resident-overhead-multiplier | `estimatedBytes(diskBytes: 51_000_000_000)`. | Returns `61_200_000_000` (`51_000_000_000 * 1.2`). |
| model-fit-policy-017 | ram-pct-zero-ram | `ramPct(1_000_000_000, of: 0)`. | Returns `0`. |
| model-fit-policy-018 | default-thresholds, threshold-setting-keys | Read `ModelFitPolicy.defaultWarnPct`, `defaultBlockPct`, `warnPctKey`, `blockPctKey` directly. | `25`, `50`, `"ai_guard_warn_pct"`, `"ai_guard_block_pct"` respectively. |
| model-fit-policy-019 | memory-pressure-cases, tier-cases, verdict-cases, fit-info-shape | Construct `MemoryPressureLevel.warning`, `ModelFitPolicy.Tier.warn`, `ModelFitPolicy.Verdict.block(reason: "x")`, and `ModelFitPolicy.FitInfo(text: "t", tier: .ok)` and compare each for equality with itself. | Each equals itself under `==` (all four types conform to `Equatable`); each also compiles when passed across a `Task { ... }` boundary (all four conform to `Sendable`). |
| model-fit-policy-020 | namespace-isolation | Call `ModelFitPolicy.tier(...)` synchronously from a `@MainActor` context and, separately, from inside a non-`AIPluginKit` `actor`'s method, with no `await`. | Both call sites compile and run without an `await`, because `ModelFitPolicy` carries no isolation of its own. |

## Edge Cases

- **Null and empty input**: `diskBytes == nil` MUST short-circuit `tier` and
  `fitInfo` to `nil` and MUST make `verdict` fail open to `.allow` whenever
  pressure is `.normal` (MUST, see `tier-unknown-size`,
  `verdict-allow-non-block-tier`). An empty `model` string (`""`) is not
  validated or rejected anywhere in the source: `verdict` and `pickerLabel`
  MUST interpolate it verbatim into the reason string or label exactly as
  any other string, since neither function branches on it (MUST).
- **Boundary values**: A `pct` exactly equal to `warnPct` MUST classify as
  `.warn`, not `.ok`, and a `pct` exactly equal to `blockPct` MUST classify
  as `.block`, not `.warn`, because `tier` compares with `>=`, not `>` (MUST,
  see `tier-classification`). `physicalRAM == 0` MUST yield a
  `nil` tier (so `verdict` fails open) and MUST make `ramPct` return `0`,
  regardless of `diskBytes` (MUST, see `tier-zero-ram`, `ram-pct-zero-ram`).
  A negative `diskBytes`, or a negative or over-100 `warnPct`/`blockPct`, is
  not validated or rejected anywhere in `ModelFitPolicy.swift`;
  `estimatedBytes`, `tier`, and the percentage arithmetic all proceed
  unguarded, so a negative `diskBytes` necessarily produces a negative `pct`,
  which both `>=` comparisons read as `.ok` (fact, not a MUST — no
  validation branch exists in the source to enforce or violate).
- **Concurrent access**: Not applicable in the mutex/serialization sense —
  `ModelFitPolicy` declares no actor, lock, or shared mutable state of any
  kind (MUST, see `namespace-isolation`); every function reads
  only its parameters and returns a freshly computed value, so any number of
  concurrent callers on any number of threads or tasks are inherently
  race-free and require no synchronization.
- **Error states**: `ModelFitPolicy.swift` declares no `throws` on any
  function and raises no error of its own; it has no dependency (network,
  file system, database) to fail against. A caller's own failure to
  determine a model's size or the machine's RAM is communicated to
  `ModelFitPolicy` only as `diskBytes == nil`, already covered under Null and
  empty input above (fact — the source has no error path of its own to
  document).
- **Offline or disconnected state**: Not applicable — `ModelFitPolicy.swift`
  makes no network call and holds no notion of connectivity (traced to the
  single `import Foundation` and the absence of any networking API
  in the file). A caller's own unreachable local model server surfaces to
  `ModelFitPolicy` only as `diskBytes == nil`, identical to any other
  unknown-size case above.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `warnPct` (parameter to `tier`, `fitInfo`, `pickerLabel`) | `Int` | `ModelFitPolicy.defaultWarnPct` (25) | Percentage of RAM at or above which the estimated footprint is `.warn`. |
| `blockPct` (parameter to `tier`, `fitInfo`, `pickerLabel`) | `Int` | `ModelFitPolicy.defaultBlockPct` (50) | Percentage of RAM at or above which the estimated footprint is `.block`. |
| `warnPct`, `blockPct` (parameters to `verdict`) | `Int`, `Int` | none — required | Same meaning as above, but `verdict` has no default; the caller MUST supply both explicitly. |
| `diskBytes` (parameter to `tier`, `verdict`, `fitInfo`, `pickerLabel`) | `Int?` | none — required | On-disk size in bytes of the candidate model; `nil` means unknown. |
| `physicalRAM` (parameter to `tier`, `verdict`, `fitInfo`, `pickerLabel`) | `UInt64` | none — required | The machine's physical RAM in bytes. |
| `pressure` (parameter to `verdict`, `pressureVerdict`) | `MemoryPressureLevel` | none — required | Latched OS memory-pressure snapshot (`.normal`/`.warning`/`.critical`). |
| `model` (parameter to `verdict`, `pickerLabel`) | `String` | none — required | Model name/tag, included verbatim in the returned text. |

`ModelFitPolicy.swift` defines no environment variable. It declares two
settings-key constants, `warnPctKey` (`"ai_guard_warn_pct"`) and `blockPctKey`
(`"ai_guard_block_pct"`), but reads neither itself — resolving them through a
host's settings store (a `ProviderSettingsReader`) is the caller's
responsibility, as documented in the sibling `LocalInferenceGuard` recipe
(the open question of *where* those keys are persisted is that recipe's
concern, not this one's).

## Deep Linking

Not applicable: `ModelFitPolicy.swift` defines no URL scheme, route, or
navigation destination — it is a pure in-process policy, not app navigation.

## Localization

`ModelFitPolicy.swift` defines no string-key or localization-table lookup;
every string it produces is a hardcoded English literal composed inline, with
no key system to reference:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no key) | `~<X> GB (~<Y>% of RAM)` | `footprintDescription`'s shared footprint core, embedded in `verdict`'s block reason. |
| (none — literal, no key) | `<model> needs <footprint> est.; block threshold is <N>% of <X> GB` | `verdict`'s block reason. |
| (none — literal, no key) | `memory pressure is <level>; deferring local inference` | `pressureVerdict`'s deferred reason, also surfaced by `verdict`. |
| (none — literal, no key) | `<size> (~<Y>% of RAM)` / `<size> ⚠ large: ~<Y>% of RAM` / `<size> — won't run: exceeds memory budget` | `fitInfo`'s per-tier text, shown verbatim by `pickerLabel` and by callers such as `ModelChooserContent`. |

## Accessibility Options

Not applicable: `ModelFitPolicy.swift` presents no UI, so it responds to no
Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: `ModelFitPolicy.swift` defines no feature-flag or on/off
settings-key gate of its own; `warnPctKey`/`blockPctKey` (see Configuration)
are numeric percentage thresholds, not a flag that enables or disables the
policy.

## Analytics

Not applicable: `ModelFitPolicy.swift` contains no analytics or
event-tracking call.

## Privacy

Not applicable: `ModelFitPolicy.swift` handles only a model name string and
numeric memory figures (bytes, percentages) — no credential, token, or
personal data — and performs no storage or transmission of its own.

## Logging

Not applicable: `ModelFitPolicy.swift` makes no logging call of its own — no
`import os`, no `Logger`, no `print` appears in the file. A warn-tier
condition it computes is logged by its caller, `LocalInferenceGuard`, as
documented in that component's own recipe, not by this file.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/AIPluginKit/ModelFitPolicy.swift`, alongside
  its test target `ModelFitPolicyTests.swift` and its consumers
  `LocalInferenceGuard.swift` and the macOS `ModelChooserContent`/
  `ModelChooserViewController`. It uses only `Foundation`'s `Double`,
  `String(format:locale:)`, and `Locale` — nothing here is SwiftUI-specific;
  any host consumes `ModelFitPolicy` identically.
- **Compose**: Model `Tier`/`MemoryPressureLevel` as Kotlin `enum class`es
  and `Verdict` as a `sealed interface` with `Allow`, `Block(reason: String)`,
  and `Deferred(reason: String)` implementations (Kotlin has no bare
  associated-value enum case, so a sealed hierarchy is the standard
  substitute). `FitInfo` becomes a `data class`. Use
  `String.format(Locale.ROOT, "%.1f GB", bytes / 1_000_000_000.0)` in place
  of `gbString`'s `en_US_POSIX` locale, and `Math.round(pct).toInt()` for
  `ramPct` (Kotlin's `Math.round` rounds half-up for positive values,
  matching Swift's `.rounded()` for the non-negative inputs this policy
  receives).
- **React/Web**: Model `Tier` and `MemoryPressureLevel` as TypeScript string
  union types and `Verdict` as a discriminated union
  (`{ kind: "allow" } | { kind: "block"; reason: string } | { kind: "deferred"; reason: string }`).
  Use `(bytes / 1_000_000_000).toFixed(1) + " GB"` in place of `gbString`
  (`toFixed` is locale-independent, unlike `Intl.NumberFormat`, matching the
  source's deliberate use of the fixed `en_US_POSIX` locale rather than the
  caller's current one), and `Math.round(pct)` for `ramPct`.
- **AppKit / UIKit**: Identical to the SwiftUI note — this policy is
  UI-framework-agnostic; only the host application embedding `AIPluginKit`
  differs, never this contract.
- **WinUI 3**: Model `Tier` and `MemoryPressureLevel` as C# `enum`s, and
  `Verdict` as an `abstract record` with `Allow`, `Block(string Reason)`, and
  `Deferred(string Reason)` derived `record` types (C#'s closest match to a
  Swift enum with associated values) so a `switch` expression over `Verdict`
  can be exhaustive. `FitInfo` becomes a `readonly record struct` with `Text`
  and `Tier` properties. Expose `ModelFitPolicy` as a `static class` of
  `static` methods and `const`/`static readonly` fields — no
  `INotifyPropertyChanged`, `ObservableCollection`, `HttpClient`, or
  `Windows.Storage` is needed, since this policy performs no networking,
  persistence, or observable-property binding. Use
  `bytes.ToString("F1", CultureInfo.InvariantCulture) + " GB"` for the
  `gbString` analogue (`InvariantCulture` is .NET's equivalent of the
  source's fixed `en_US_POSIX` locale) and
  `Math.Round(pct, MidpointRounding.AwayFromZero)` for `ramPct`, since
  .NET's default `MidpointRounding.ToEven` would silently diverge from
  Swift's `Double.rounded()` (which rounds half away from zero) at exact
  `.5` percentage boundaries.

## Design Decisions

**Decision**: `fitInfo`'s `.ok`/`.warn` text shows the on-disk size
(`gbString(diskBytes)`), while `verdict`'s block reason and
`footprintDescription` show the *estimated* resident size
(`gbString(estimatedBytes)`).
**Rationale**: Per the source's own doc comment, `footprintDescription` is
"computed from ESTIMATED resident bytes" and is reserved for the paths that
need the safety-margin number (a block refusal, or a warn-tier log line);
`fitInfo`'s ok/warn text instead shows the number the user already sees
reported for the model on disk, since the estimate is only needed to decide
*whether* to warn, not to relabel a model that already fits comfortably.
**Approved**: pending

**Decision**: `verdict`'s `warnPct`/`blockPct` parameters carry no default
value, while the equivalent parameters on `tier`, `fitInfo`, and
`pickerLabel` default to `defaultWarnPct`/`defaultBlockPct`.
**Rationale**: `verdict` is the inference-time gate, called by
`LocalInferenceGuard` with a live settings reader that always resolves
`ai_guard_warn_pct`/`ai_guard_block_pct`, so it is written to force every
caller to make that threshold resolution explicit; the labeling-only
functions are used by pickers that may have no override UI (per `fitInfo`'s
own doc comment, "stenographer has no override UI yet, so it relies on the
defaults") and so fall back silently.
**Approved**: pending

**Decision**: `tier` uses `>=` for both the warn and block comparisons, so a
model whose estimated footprint is exactly `warnPct`% of RAM is `.warn`, not
`.ok`, and exactly `blockPct`% is `.block`, not `.warn`.
**Rationale**: This is the plain reading of
`if pct >= Double(blockPct) { return .block }` followed by
`if pct >= Double(warnPct) { return .warn }`; no comment
explains the choice, but it means the threshold value itself is the first
percentage point treated as the more severe tier — the recipe records this
as the normative `tier-classification` boundary rather than leaving a reader
to assume a strict `>`.
**Approved**: pending

**Decision**: `ModelFitPolicy` declares no `Sendable` conformance of its
own, unlike `MemoryPressureLevel`, `Tier`, `Verdict`, and `FitInfo`, which
each are.
**Rationale**: A case-less enum used purely as a namespace for `static`
members has no instances that could ever cross an isolation boundary, so
`Sendable` conformance is not meaningful for it; the four nested/sibling
types that do carry values across boundaries — as parameters or return
values of `ModelFitPolicy`'s functions — are exactly the ones marked
`Sendable`.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [test-pyramid](agenticdevelopercookbook://compliance/best-practices#test-pyramid) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

Notes: separation-of-concerns passes because the policy is kept at toolkit level specifically so enforcement (`LocalInferenceGuard`) and presentation (`ModelChooserContent`/`ModelChooserViewController`) each consume the same pure computation rather than each reimplementing it, per the Overview's "so every `AIPluginKit` host shares one representation... and the two cannot drift." unit-test-coverage passes because `ModelFitPolicyTests.swift` covers tier boundaries, verdict precedence, and every `fitInfo`/`pickerLabel` text format across 20 vectors. test-pyramid passes because `ModelFitPolicyTests.swift` tests the pure functions entirely at the unit level, with no integration or UI layer needed for a case-less policy enum. no-hardcoded-strings fails because every string `ModelFitPolicy` produces — `gbString`, `footprintDescription`, `fitInfo.text`, `pickerLabel`, and `verdict`'s reasons — is a hardcoded English literal composed inline with no localization key, and that text is shown verbatim by the macOS model picker.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-24 | Mike Fullerton | Compliance section rewritten as linked checks against the compliance catalog |
| 1.0.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
