<!-- leaf: implement-status-web-src-lib-2/status-sublabel--part-2 · source: status-web-src-lib-status-sublabel.md -->

# Status Sublabel — continued (part 2)

## Platform Notes

- **SwiftUI**: Port as a free function or a static member of a caseless `enum StatusSublabel` that returns `String`. Model `IndicatorState` as `enum IndicatorState: String, Sendable { case ok, warn, down }`. Swift `Dictionary` has no insertion order, so keep the phrase table as an ordered array of `(word: String, format: @Sendable (Int) -> String)` pairs. Group unmapped words with an array plus a `[String: Int]` counter to keep first-seen order (or use `OrderedDictionary` from swift-collections). Join the parts with `joined(separator: " · ")`. Use `String(localized:)` with a stringsdict plural variant if the strings are localized.
- **Compose**: Use a Kotlin top-level function. `linkedMapOf` and `LinkedHashMap` preserve insertion order, which gives both the table order and the first-seen order for unmapped words. `problems.groupingBy { it.statusWord }.eachCount()` returns a `LinkedHashMap` in first-seen order. Join with `joinToString(" · ")`. Plurals map to `pluralStringResource` if localized.
- **React/Web**: This is the source: `src/lib/status-sublabel.ts`, called from `src/components/OverviewTab.tsx` and rendered by `src/components/BigIndicator.tsx`. The ordering depends on two JavaScript guarantees. `Object.entries` returns string (non-integer) keys in insertion order, and `Map` iterates in insertion order. The function deletes each mapped word from the `Map` so that only unmapped words remain for the second loop.
- **AppKit / UIKit**: Use the same pure Swift port as SwiftUI, placed in a shared framework target. Nothing in it is UI-bound.
- **WinUI 3**: Port as `public static string BuildSublabel(IndicatorState state, int healthyCount, int servicesLength, IReadOnlyList<Row> problems)` in a `public static class StatusSublabel`, with `public enum IndicatorState { Ok, Warn, Down }`. `Dictionary<string, int>` does not guarantee enumeration order, so keep the phrase table as a `static readonly (string Word, Func<int, string> Format)[]` array. Count groups with a `Dictionary<string, int>` (ordinal comparer, matching JavaScript's case-sensitive keys) and keep a `List<string>` of first-seen words for the unmapped tail. Join with `string.Join(" · ", parts)`. Format numbers with `CultureInfo.InvariantCulture` or `ToString()` under the invariant culture, so a comma decimal separator cannot appear. If localized, the strings go in `.resw` resources through `ResourceLoader`, with plural handling moved to a helper, because `.resw` has no plural rules. The view model that exposes the sublabel raises `INotifyPropertyChanged` when its inputs change. The function itself stays synchronous, with no `Task`.

## Design Decisions

**Decision**: When the board is operational, print "N/N endpoints healthy" only when every endpoint is healthy, and otherwise print "N endpoints monitored".
**Rationale**: The source comment explains that under an operational board, a non-healthy endpoint is a transient blip (degraded within the window) or an unprobed one, not an incident. A fraction such as "4/5 healthy" beside "ALL SYSTEMS OPERATIONAL" would read as a contradiction.
**Approved**: pending

**Decision**: The breakdown accounts for every problem, and unmapped status words fall through verbatim.
**Rationale**: The doc comment requires the parts to "sum to the indicator count". A status word added elsewhere without a table entry still shows up as `{n} {word}` rather than silently disappearing from the caption.
**Approved**: pending

**Decision**: Some status words are relabelled rather than echoed: `building` becomes "stuck build" and `deployment failed` becomes "stale deploy".
**Rationale**: The source comment says a building row "only reaches Problems when stuck", so "stuck" names the actual condition. The "stale deploy" wording for `deployment failed` is taken directly from `SUBLABEL_PHRASE` and distinguishes it from the `deploy failed` phrase.
**Approved**: pending

**Decision**: One function serves every status caption surface.
**Rationale**: The doc comment says it is shared by the mobile hero and the desktop top-bar pill, so the two surfaces cannot word the same board differently. In the current tree only `OverviewTab` (feeding `BigIndicator`) calls it.
**Approved**: pending
