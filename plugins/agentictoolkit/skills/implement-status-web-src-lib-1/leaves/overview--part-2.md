<!-- leaf: implement-status-web-src-lib-1/overview--part-2 · source: status-web-src-lib-overview.md -->

# Overview Projections — continued (part 2)

## Localization

`headlineFor` returns hardcoded, uppercase English strings with no localization layer: `"ALL SYSTEMS OPERATIONAL"`, `"1 SERVICE NEEDS ATTENTION"`, `"{count} SERVICES NEED ATTENTION"`, `"1 PROBLEM"`, `"{count} PROBLEMS"`. Pluralization is a binary `count === 1` test. `activityWindowLabel` returns the English unit suffixes `h` and `d`.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal) | `ALL SYSTEMS OPERATIONAL` | Headline when state is ok |
| (none; literal) | `1 SERVICE NEEDS ATTENTION` | Headline, warn, one problem |
| (none; literal) | `{count} SERVICES NEED ATTENTION` | Headline, warn, other counts |
| (none; literal) | `1 PROBLEM` | Headline, down, one problem |
| (none; literal) | `{count} PROBLEMS` | Headline, down, other counts |
| (none; literal) | `{n}h` / `{n}d` | Activity window caption |

## Platform Notes

- **SwiftUI**: Port as free functions or a caseless `enum OverviewProjection`. Model `IndicatorState` as `enum IndicatorState: String { case ok, warn, down }` and `Indicator` as a `Sendable` struct. `INDICATOR_STATE` becomes a `switch` over a wire `enum BoardIndicator`, which the compiler checks for exhaustiveness. For `deployCounts`, parse `at` with `ISO8601DateFormatter` (fractional seconds); it returns `nil` rather than NaN, so decide explicitly whether a `nil` row is counted (the source counts it). Use `String(localized:)` with a plural variant if the headline is localized.
- **Compose**: Use a Kotlin `object` with an `enum class IndicatorState` and a `data class Indicator`. `INDICATOR_STATE` becomes an exhaustive `when`. `Instant.parse` throws instead of returning NaN, so wrap it to preserve the "count on unparseable" behavior. Plurals map to `pluralStringResource` if localized.
- **React/Web**: This is the source: `src/lib/overview.ts`, tested by `src/lib/overview.test.ts` and `src/lib/board-types-parity.test.ts` (the latter imports the server's `indicatorFor` from `@agentic-toolkit/status-server/activity`). Behavior leans on JavaScript specifics: `Date.parse` returning `NaN`, `NaN` comparisons being `false`, and `== null` matching both `null` and `undefined`.
- **AppKit / UIKit**: Same pure Swift port as SwiftUI, placed in a shared framework target; nothing is UI-bound.
- **WinUI 3**: Port as a `public static class OverviewProjection` in C#. `IndicatorState` becomes `public enum IndicatorState { Ok, Warn, Down }` (serialise lower-case with `JsonStringEnumConverter` and `JsonNamingPolicy.CamelCase` if it crosses `System.Text.Json`); `Indicator` becomes a `public readonly record struct Indicator(IndicatorState State, int Count)`. `INDICATOR_STATE` becomes a switch expression over a `BoardIndicator` enum, or a `FrozenDictionary<BoardIndicator, IndicatorState>`. `deployCounts` loops a `IReadOnlyList<ActivityRow>` and parses `at` with `DateTimeOffset.TryParse(..., CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)`; a `false` result has no NaN analogue, so count the row explicitly to match the source. `activityWindowLabel` uses `Math.Round(x, MidpointRounding.AwayFromZero)` because JavaScript `Math.round` rounds .5 up while .NET defaults to banker's rounding. `isRealEnvDeployRow` uses `string.IsNullOrEmpty(environment)` and an ordinal `platform == "vercel"`. Headline strings go in `.resw` resources through `ResourceLoader` if localized. The view model binding the headline raises `INotifyPropertyChanged`; the functions stay synchronous, with no `Task`.

## Design Decisions

**Decision**: The client mirrors the server's indicator rule instead of computing its own.
**Rationale**: The doc comment calls `indicatorFromProblems` a rendering projection, "not a second opinion about what a problem is". It exists only because a filtered pane needs the rule over a subset; `board-types-parity.test.ts` pins it to the server's `indicatorFor` so it cannot drift again.
**Approved**: pending

**Decision**: `INDICATOR_STATE` is the single wire-to-sign translation.
**Rationale**: One typed `Record<BoardIndicator, IndicatorState>` is exhaustive at compile time, and a key test catches a member removed from both union and map together.
**Approved**: pending

**Decision**: Derive the window caption from the board's own bounds instead of hardcoding "24h".
**Rationale**: The server owns `ACTIVITY_WINDOW_MS`; a hardcoded caption would keep stating the old figure after a server change, "a label that lies without anything failing". Days are used only for whole-day windows of 48h or more, so 47h is never rounded to a window nobody configured.
**Approved**: pending

**Decision**: Tally deploy counts on the client.
**Rationale**: The doc comment allows it because the counts are a tally of rows the server already judged: `step` and `tone` arrive on the wire and the window start is the board's `activityFromMs`.
**Approved**: pending

**Decision**: One `headlineFor` shared by the hero sign and the top-bar pill.
**Rationale**: Sharing the function makes it impossible for the two surfaces to word the same state differently.
**Approved**: pending

**Decision**: Treat Vercel deploys with no environment target as preview builds and exclude them.
**Rationale**: Vercel previews report `environment=null`; they are CI artifacts, and counting a failed preview as "deploy failed" under the project's prod/staging label was a real false positive. The duplicated server copy is described under real-env-server-agreement.
**Approved**: pending
