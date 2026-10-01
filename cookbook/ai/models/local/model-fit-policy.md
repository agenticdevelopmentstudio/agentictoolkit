---
id: 5069f11f-e0c6-40c3-92ca-6152b8df3bc2
title: Model Fit Policy
domain: agentictoolkit://cookbook/ai/models/local/model-fit-policy
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure policy mapping a local model's disk size, available RAM, thresholds,
  and memory pressure to a fit tier and an allow/block/defer verdict, shared by
  an inference guard and model pickers.
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

# Model Fit Policy

## Overview

This is a toolkit-level policy for whether a local ("loopback") model should
run on the current machine. Per the source's own doc comment, it is "a pure
function from (model size, machine RAM, thresholds, pressure) to a
tier/verdict," kept at a shared level so every host in this family shares one
representation: an inference guard enforces with it before dispatching a
chat request to a local model server, and a model chooser labels candidate
models with it via its picker-label and fit-info computations — "so the two
cannot drift." This policy holds no mutable state of its own and performs no
I/O; it is exposed purely as constants and pure functions, and there is no
way to construct an instance of it.

## Behavioral Requirements

- **memory-pressure-cases**: The memory pressure level type MUST expose
  exactly three cases — `normal`, `warning`, and `critical` — each
  comparable for equality and safe to pass across concurrent boundaries,
  with a stable string form for each case.
- **tier-cases**: The tier type MUST expose exactly three cases — `ok`,
  `warn`, and `block` — each comparable for equality and safe to pass
  across concurrent boundaries.
- **verdict-cases**: The verdict type MUST expose exactly three cases —
  `allow`, `block` (carrying a reason), and `deferred` (carrying a reason)
  — each comparable for equality and safe to pass across concurrent
  boundaries, with each refusal case carrying a human-readable reason
  string.
- **fit-info-shape**: The fit-info structure MUST be comparable for
  equality and safe to pass across concurrent boundaries, exposing
  immutable `text` and `tier` fields, constructible only through its
  public initializer.
- **namespace-isolation**: This policy MUST be exposed as an uninstantiable
  namespace holding no stored state of its own, whose public members are
  exclusively constants and pure functions; because it declares no
  concurrency isolation of its own, every member MUST be callable
  synchronously from any concurrency context without waiting on it.
- **resident-overhead-multiplier**: The resident overhead multiplier MUST
  equal `1.2`.
- **estimated-bytes**: The estimated-bytes computation MUST return the
  on-disk byte count multiplied by the resident overhead multiplier,
  truncated to a whole number of bytes.
- **default-thresholds**: The default warn threshold MUST equal `25` and
  the default block threshold MUST equal `50` (both percentages of RAM).
- **threshold-setting-keys**: The warn-threshold setting key MUST equal the
  literal string `ai_guard_warn_pct` and the block-threshold setting key
  MUST equal the literal string `ai_guard_block_pct`.
- **tier-unknown-size**: The tier computation MUST return nothing when the
  disk size is unknown.
- **tier-zero-ram**: The tier computation MUST return nothing when
  physical RAM is `0`.
- **tier-classification**: When the disk size is known and physical RAM is
  greater than `0`, the tier computation MUST compute a percentage as the
  estimated resident bytes divided by physical RAM, times `100`, and MUST
  classify it as `block` when the percentage is at or above the block
  threshold, `warn` when it is at or above the warn threshold and below
  the block threshold, and `ok` when it is below the warn threshold.
- **tier-threshold-defaults**: The tier, fit-info, and picker-label
  computations MUST each default an omitted warn threshold to the default
  warn threshold and an omitted block threshold to the default block
  threshold.
- **pressure-verdict-normal**: The pressure verdict MUST be `allow` when
  pressure is `normal`.
- **pressure-verdict-elevated**: The pressure verdict MUST be `deferred`,
  with a reason string of exactly the form
  `memory pressure is <pressure>; deferring local inference`, when
  pressure is `warning` or `critical`.
- **verdict-pressure-precedence**: The verdict computation MUST evaluate
  the pressure verdict first and, whenever that result is `deferred`, MUST
  return that exact deferred result without evaluating the size tier at
  all — regardless of disk size, model, or the thresholds.
- **verdict-required-thresholds**: The verdict computation's warn and block
  threshold inputs MUST carry no default value; the caller MUST supply
  both explicitly — unlike the tier, fit-info, and picker-label
  computations.
- **verdict-allow-non-block-tier**: Under `normal` pressure, the verdict
  computation MUST return `allow` whenever the computed tier is `ok`,
  `warn`, or unknown (unknown size) — only a `block` tier with a known
  disk size yields a refusal.
- **verdict-block-reason-format**: When the computed tier is `block` and
  the disk size is known, the verdict computation MUST return a `block`
  result with a reason string of exactly the form
  `<model> needs <footprint description> est.; block threshold is <block threshold>% of <RAM as a GB string>`,
  where the embedded footprint description is computed from the estimated
  (not on-disk) resident bytes.
- **footprint-description-format**: The footprint-description computation
  MUST return a string of exactly the form
  `~<estimated bytes as a GB string> (~<estimated bytes as a percentage of RAM>% of RAM)`.
- **fit-info-unknown**: The fit-info computation MUST return nothing when
  the disk size is unknown or when the tier computation returns nothing.
- **fit-info-ok-text**: For an `ok` tier, the fit-info computation MUST
  return text of exactly the form
  `<disk size as a GB string> (~<percentage of RAM>% of RAM)` paired with
  tier `ok`, displaying the on-disk size rather than the estimated
  resident size.
- **fit-info-warn-text**: For a `warn` tier, the fit-info computation MUST
  return text of exactly the form
  `<disk size as a GB string> ⚠ large: ~<percentage of RAM>% of RAM`
  paired with tier `warn`.
- **fit-info-block-text**: For a `block` tier, the fit-info computation
  MUST return text of exactly the form
  `<disk size as a GB string> — won't run: exceeds memory budget` paired
  with tier `block`; unlike the `ok`/`warn` text, the block text MUST NOT
  include a RAM-percentage figure.
- **picker-label-unknown**: The picker-label computation MUST return the
  model name unchanged when the fit-info computation returns nothing.
- **picker-label-known**: The picker-label computation MUST return the
  exact string `<model> — <fit-info text>` when the fit-info computation
  returns a value.
- **gb-string-format**: Formatting a byte count as a GB string MUST render
  the value, divided by `1,000,000,000`, to exactly one decimal place
  followed by ` GB`, using a fixed, locale-independent numeric format
  regardless of the caller's own locale.
- **ram-pct-computation**: Computing a byte count's percentage of RAM MUST
  return the nearest whole percentage, rounded half-away-from-zero, when
  physical RAM is non-zero.
- **ram-pct-zero-ram**: Computing a byte count's percentage of RAM MUST
  return `0` when physical RAM is `0`.

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
| model-fit-policy-001 | tier-classification, tier-threshold-defaults | Compute the tier for a disk size of 12.5 GB and physical RAM of 64 GB, with thresholds omitted. | `ok` — estimated 15.0 GB is about 23% of RAM, under the default 25% warn threshold. |
| model-fit-policy-002 | tier-classification | Compute the tier for a disk size of 14 GB and physical RAM of 64 GB. | `warn` — estimated 16.8 GB is about 26% of RAM, at or above 25% and below 50%. |
| model-fit-policy-003 | tier-classification | Compute the tier for a disk size of 27 GB and physical RAM of 64 GB. | `block` — estimated 32.4 GB is about 51% of RAM, at or above the default 50% block threshold. |
| model-fit-policy-004 | tier-unknown-size, tier-zero-ram | Compute the tier for an unknown disk size at 64 GB RAM, and for a 1-byte disk size at 0 RAM. | Both return nothing. |
| model-fit-policy-005 | verdict-block-reason-format, footprint-description-format, verdict-required-thresholds | Compute the verdict for model `qwen3-coder-next:latest`, disk size 51 GB, physical RAM 64 GB, warn threshold 25, block threshold 50, pressure normal. | A `block` result whose reason contains `"qwen3-coder-next:latest"`, `"~61.2 GB (~96% of RAM)"`, and `"50% of 64.0 GB"`. |
| model-fit-policy-006 | footprint-description-format, gb-string-format, ram-pct-computation | Compute the footprint description for estimated bytes 24 GB and physical RAM 64 GB. | Returns exactly `"~24.0 GB (~38% of RAM)"`. |
| model-fit-policy-007 | fit-info-ok-text | Compute the fit info for disk size 8.9 GB and physical RAM 64 GB. | Text `"8.9 GB (~17% of RAM)"` paired with tier `ok`. |
| model-fit-policy-008 | fit-info-warn-text | Compute the fit info for disk size 20 GB and physical RAM 64 GB. | Text `"20.0 GB ⚠ large: ~38% of RAM"` paired with tier `warn`. |
| model-fit-policy-009 | fit-info-block-text | Compute the fit info for disk size 51 GB and physical RAM 64 GB. | Text `"51.0 GB — won't run: exceeds memory budget"` paired with tier `block`. |
| model-fit-policy-010 | fit-info-unknown | Compute the fit info for an unknown disk size at 64 GB RAM. | Returns nothing. |
| model-fit-policy-011 | pressure-verdict-elevated, verdict-pressure-precedence | Compute the verdict for model `llama3.1:8b`, physical RAM 64 GB, warn threshold 25, block threshold 50, pressure warning, once with a known disk size of 4.9 GB and once with an unknown disk size. | A `deferred` result whose reason contains `"memory pressure is warning"` in both cases, even with a known small size or an unknown size. |
| model-fit-policy-012 | verdict-allow-non-block-tier, pressure-verdict-normal | Compute the verdict under normal pressure for disk sizes 4.9 GB (`ok`), 20 GB (`warn`), and unknown, all at 64 GB RAM. | `allow` in all three cases. |
| model-fit-policy-013 | picker-label-known | Compute the picker label for model `deepseek-coder-v2:16b`, disk size 8.9 GB, physical RAM 64 GB. | Returns exactly `"deepseek-coder-v2:16b — 8.9 GB (~17% of RAM)"`. |
| model-fit-policy-014 | picker-label-known | Compute the picker label for model `huge`, disk size 51 GB, physical RAM 64 GB. | Returns exactly `"huge — 51.0 GB — won't run: exceeds memory budget"`. |
| model-fit-policy-015 | picker-label-unknown | Compute the picker label for model `mystery`, an unknown disk size, physical RAM 64 GB. | Returns exactly `"mystery"`. |
| model-fit-policy-016 | estimated-bytes, resident-overhead-multiplier | Compute estimated bytes for a disk size of 51 GB. | Returns `61,200,000,000` (`51,000,000,000 × 1.2`). |
| model-fit-policy-017 | ram-pct-zero-ram | Compute a percentage of RAM for a 1 GB byte count against 0 physical RAM. | Returns `0`. |
| model-fit-policy-018 | default-thresholds, threshold-setting-keys | Read the default warn threshold, default block threshold, warn-threshold setting key, and block-threshold setting key directly. | `25`, `50`, `"ai_guard_warn_pct"`, and `"ai_guard_block_pct"` respectively. |
| model-fit-policy-019 | memory-pressure-cases, tier-cases, verdict-cases, fit-info-shape | Construct one instance each of the memory pressure level (`warning`), the tier (`warn`), the verdict (`block`, reason `"x"`), and the fit-info structure (text `"t"`, tier `ok`), and compare each for equality with itself. | Each equals itself; each also can be safely passed across a concurrent boundary. |
| model-fit-policy-020 | namespace-isolation | Call the tier computation synchronously from two different concurrency contexts, with no waiting. | Both call sites run without waiting on the call, because this policy carries no isolation of its own. |

## Edge Cases

- **Null and empty input**: An unknown disk size MUST short-circuit the
  tier and fit-info computations to nothing and MUST make the verdict
  computation fail open to `allow` whenever pressure is `normal` (MUST,
  see `tier-unknown-size`, `verdict-allow-non-block-tier`). An empty model
  name string (`""`) is not validated or rejected anywhere: the verdict
  and picker-label computations MUST interpolate it verbatim into the
  reason string or label exactly as any other string, since neither
  branches on it (MUST).
- **Boundary values**: A percentage exactly equal to the warn threshold
  MUST classify as `warn`, not `ok`, and a percentage exactly equal to the
  block threshold MUST classify as `block`, not `warn`, because the tier
  computation compares with "at or above," not "strictly above" (MUST,
  see `tier-classification`). Physical RAM of `0` MUST yield an unknown
  tier (so the verdict computation fails open) and MUST make the
  RAM-percentage computation return `0`, regardless of disk size (MUST,
  see `tier-zero-ram`, `ram-pct-zero-ram`). A negative disk size, or a
  negative or over-100 warn/block threshold, is not validated or rejected
  anywhere; the estimated-bytes computation, the tier computation, and the
  percentage arithmetic all proceed unguarded, so a negative disk size
  necessarily produces a negative percentage, which both "at or above"
  comparisons read as `ok` (fact, not a MUST — no validation branch exists
  to enforce or violate this).
- **Concurrent access**: Not applicable in the mutex/serialization sense —
  this policy declares no lock or shared mutable state of any kind (MUST,
  see `namespace-isolation`); every computation reads only its parameters
  and returns a freshly computed value, so any number of concurrent
  callers are inherently race-free and require no synchronization.
- **Error states**: This policy raises no error of its own and has no
  dependency (network, file system, database) to fail against. A caller's
  own failure to determine a model's size or the machine's RAM is
  communicated to this policy only as an unknown disk size, already
  covered under Null and empty input above (fact — there is no error path
  of its own to document).
- **Offline or disconnected state**: Not applicable — this policy makes no
  network call and holds no notion of connectivity. A caller's own
  unreachable local model server surfaces to this policy only as an
  unknown disk size, identical to any other unknown-size case above.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `warnPct` (parameter to the tier, fit-info, picker-label computations) | integer | the default warn threshold (25) | Percentage of RAM at or above which the estimated footprint is `warn`. |
| `blockPct` (parameter to the tier, fit-info, picker-label computations) | integer | the default block threshold (50) | Percentage of RAM at or above which the estimated footprint is `block`. |
| `warnPct`, `blockPct` (parameters to the verdict computation) | integer, integer | none — required | Same meaning as above, but the verdict computation has no default; the caller MUST supply both explicitly. |
| `diskBytes` (parameter to the tier, verdict, fit-info, picker-label computations) | optional integer | none — required | On-disk size in bytes of the candidate model; absent means unknown. |
| `physicalRAM` (parameter to the tier, verdict, fit-info, picker-label computations) | unsigned integer | none — required | The machine's physical RAM in bytes. |
| `pressure` (parameter to the verdict and pressure-verdict computations) | memory pressure level | none — required | Latched OS memory-pressure snapshot (`normal`/`warning`/`critical`). |
| `model` (parameter to the verdict and picker-label computations) | string | none — required | Model name/tag, included verbatim in the returned text. |

This policy defines no environment variable. It declares two settings-key
constants, the warn-threshold key (`ai_guard_warn_pct`) and the
block-threshold key (`ai_guard_block_pct`), but reads neither itself —
resolving them through a host's settings store is the caller's
responsibility, as documented in the sibling inference-guard recipe (the
open question of *where* those keys are persisted is that recipe's concern,
not this one's).

## Deep Linking

Not applicable: this policy defines no URL scheme, route, or navigation
destination — it is a pure in-process policy, not app navigation.

## Localization

This policy defines no string-key or localization-table lookup; every
string it produces is a hardcoded English literal composed inline, with no
key system to reference:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no key) | `~<X> GB (~<Y>% of RAM)` | The shared footprint-description core, embedded in the verdict computation's block reason. |
| (none — literal, no key) | `<model> needs <footprint> est.; block threshold is <N>% of <X> GB` | The verdict computation's block reason. |
| (none — literal, no key) | `memory pressure is <level>; deferring local inference` | The pressure-verdict computation's deferred reason, also surfaced by the verdict computation. |
| (none — literal, no key) | `<size> (~<Y>% of RAM)` / `<size> ⚠ large: ~<Y>% of RAM` / `<size> — won't run: exceeds memory budget` | The fit-info computation's per-tier text, shown verbatim by the picker-label computation and by callers such as a model chooser. |

## Accessibility Options

Not applicable: this policy presents no UI, so it responds to no Reduce
Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: this policy defines no feature-flag or on/off settings-key
gate of its own; the warn-threshold and block-threshold keys (see
Configuration) are numeric percentage thresholds, not a flag that enables
or disables the policy.

## Analytics

Not applicable: this policy contains no analytics or event-tracking call.

## Privacy

Not applicable: this policy handles only a model name string and numeric
memory figures (bytes, percentages) — no credential, token, or personal
data — and performs no storage or transmission of its own.

## Logging

Not applicable: this policy makes no logging call of its own. A warn-tier
condition it computes is logged by its caller, the inference guard, as
documented in that component's own recipe, not by this one.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/AIPluginKit/ModelFitPolicy.swift`, alongside
  its test target `ModelFitPolicyTests.swift` and its consumers
  `LocalInferenceGuard.swift` and the macOS `ModelChooserContent`/
  `ModelChooserViewController`. It uses only `Foundation`'s `Double`,
  `String(format:locale:)`, and `Locale` (fixed to `en_US_POSIX` for the GB
  string) — nothing here is SwiftUI-specific; any host consumes
  `ModelFitPolicy` identically. `MemoryPressureLevel` is a
  `String`-raw-valued, `Sendable`, `Equatable` `enum`; `Tier` and `Verdict`
  are `Equatable`, `Sendable` `enum`s (`Verdict`'s refusal cases carry an
  associated `String` reason); `FitInfo` is an `Equatable`, `Sendable`
  `struct`. `ModelFitPolicy` itself is a case-less `enum` — an
  uninstantiable namespace — declaring no `Sendable`, `actor`, or
  `@MainActor` isolation of its own, so every `static` member is callable
  synchronously, with no `await`, from a `@MainActor` context or from
  inside any other actor's method; the test suite verifies both call sites
  directly.
- **Compose**: Model `Tier`/`MemoryPressureLevel` as Kotlin `enum class`es
  and `Verdict` as a `sealed interface` with `Allow`, `Block(reason: String)`,
  and `Deferred(reason: String)` implementations (Kotlin has no bare
  associated-value enum case, so a sealed hierarchy is the standard
  substitute). `FitInfo` becomes a `data class`. Use
  `String.format(Locale.ROOT, "%.1f GB", bytes / 1_000_000_000.0)` in place
  of the GB-string formatter's `en_US_POSIX` locale, and
  `Math.round(pct).toInt()` for the RAM-percentage computation (Kotlin's
  `Math.round` rounds half-up for positive values, matching Swift's
  `.rounded()` for the non-negative inputs this policy receives).
- **React/Web**: Model `Tier` and `MemoryPressureLevel` as TypeScript string
  union types and `Verdict` as a discriminated union
  (`{ kind: "allow" } | { kind: "block"; reason: string } | { kind: "deferred"; reason: string }`).
  Use `(bytes / 1_000_000_000).toFixed(1) + " GB"` in place of the GB-string
  formatter (`toFixed` is locale-independent, unlike `Intl.NumberFormat`,
  matching the source's deliberate use of a fixed locale rather than the
  caller's current one), and `Math.round(pct)` for the RAM-percentage
  computation.
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
  GB-string analogue (`InvariantCulture` is .NET's equivalent of the
  source's fixed `en_US_POSIX` locale) and
  `Math.Round(pct, MidpointRounding.AwayFromZero)` for the RAM-percentage
  computation, since .NET's default `MidpointRounding.ToEven` would
  silently diverge from Swift's `Double.rounded()` (which rounds half away
  from zero) at exact `.5` percentage boundaries.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/ModelFitPolicy.swift` |

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

**Decision**: In the Swift implementation, `ModelFitPolicy` declares no
`Sendable` conformance of its own, unlike `MemoryPressureLevel`, `Tier`,
`Verdict`, and `FitInfo`, which each are.
**Rationale**: A case-less enum used purely as a namespace for `static`
members has no instances that could ever cross an isolation boundary, so
`Sendable` conformance is not meaningful for it; the four nested/sibling
types that do carry values across boundaries — as parameters or return
values of `ModelFitPolicy`'s functions — are exactly the ones marked
`Sendable`. This is a Swift-specific decision: it applies wherever the
policy is expressed as a namespace of static members in a language with an
explicit cross-isolation-safety marker; a port that models the policy as a
plain module of functions (Compose, React/Web) or a static class (WinUI 3)
has no equivalent conformance to omit or declare.
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
| 1.0.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/models/local/. |
