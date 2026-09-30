<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-model-fit-policy · source: ai-plugin-runtime-ai-plugin-kit-model-fit-policy.md -->

**Rules** (cite as `implement-ai-plugin-2/runtime-ai-plugin-kit-model-fit-policy#<slug>`):

- `memory-pressure-cases` MUST
- `tier-cases` MUST
- `verdict-cases` MUST
- `fit-info-shape` MUST
- `namespace-isolation` MUST
- `resident-overhead-multiplier` MUST
- `estimated-bytes` MUST
- `default-thresholds` MUST
- `threshold-setting-keys` MUST
- `tier-unknown-size` MUST
- `tier-zero-ram` MUST
- `tier-classification` MUST
- `tier-threshold-defaults` MUST
- `pressure-verdict-normal` MUST
- `pressure-verdict-elevated` MUST
- `verdict-pressure-precedence` MUST
- `verdict-required-thresholds` MUST
- `verdict-allow-non-block-tier` MUST
- `verdict-block-reason-format` MUST
- `footprint-description-format` MUST
- `fit-info-unknown` MUST
- `fit-info-ok-text` MUST
- `fit-info-warn-text` MUST
- `fit-info-block-text` MUST
- `picker-label-unknown` MUST
- `picker-label-known` MUST
- `gb-string-format` MUST
- `ram-pct-computation` MUST
- `ram-pct-zero-ram` MUST

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

