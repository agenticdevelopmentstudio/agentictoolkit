<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-model-fit-policy--part-2 · source: ai-plugin-runtime-ai-plugin-kit-model-fit-policy.md -->

# ModelFitPolicy — continued (part 2)

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
