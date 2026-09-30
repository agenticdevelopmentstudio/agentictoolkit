<!-- leaf: implement-status-web-src-lib-1/issue-sources--part-2 · source: status-web-src-lib-issue-sources.md -->

# Issue Sources — continued (part 2)

## Platform Notes

- **SwiftUI**: Port the union as `enum IssueSource: String, CaseIterable, Codable, Sendable` with cases `dns`, `http`, `glitchtip`, `vercel`, `cloudflarePages = "cloudflare-pages"`, `railway`, `crunchy`, declared in canonical order so `allCases` replaces `ISSUE_SOURCES`. Put the label on the enum as a `var label: String` computed with an exhaustive `switch`, so a new case fails to compile until it has a label. `IssueSource(rawValue:)` replaces `isIssueSource`, returning `nil` instead of `false`, case-sensitive like the source. Declare `static let stuckDeployInterval: Duration = .seconds(1800)`.
- **Compose**: Use `enum class IssueSource(val wire: String, val label: String)` with `entries` for the ordered list, and implement the guard as `IssueSource.entries.firstOrNull { it.wire == s }`. Do not use `enumValueOf` as the guard; it throws on a miss and matches the Kotlin constant name, not the wire string. With kotlinx.serialization, annotate `CLOUDFLARE_PAGES` with `@SerialName("cloudflare-pages")`. Declare `const val STUCK_DEPLOY_MS = 30 * 60 * 1000L`.
- **React/Web**: This is the source: `src/lib/issue-sources.ts`, with its test in `src/lib/issue-sources.test.ts`. The union is written by hand rather than derived from `ISSUE_SOURCES`, so the `Record<IssueSource, string>` type guarantees label coverage but nothing guarantees the order array is complete. The `as readonly string[]` cast widens the array so `includes` accepts any string. The server twin is `status-server/src/monitor/issue-sources.ts`, which adds the judgment functions and `platformHealthSource`.
- **AppKit / UIKit**: Use the same Swift enum as the SwiftUI port, in a shared framework target since nothing is UI-bound. Build the source filter from `IssueSource.allCases` as `NSButton` checkboxes or `UIMenu` toggle actions, using `label` for the title.
- **WinUI 3**: Port as a C# `public enum IssueSource { Dns, Http, GlitchTip, Vercel, CloudflarePages, Railway, Crunchy }`, declared in canonical order so `Enum.GetValues<IssueSource>()` replaces `ISSUE_SOURCES`. `System.Text.Json` needs explicit wire names: put `[JsonStringEnumMemberName("cloudflare-pages")]` (and the lowercase names) on each member with a `JsonStringEnumConverter`, or keep a `static readonly IReadOnlyList<string> Wire` and translate by hand. Keep labels in a `static readonly FrozenDictionary<IssueSource, string> Labels`, or in a `switch` expression that the compiler's exhaustiveness warning covers. The guard becomes `static bool TryParse(string s, out IssueSource source)` that compares wire strings with `StringComparison.Ordinal`; do not use `Enum.TryParse` with `ignoreCase`, which would accept `"DNS"`. For the filter UI, bind an `ItemsRepeater` or `ListView` of `CheckBox` items to `Enum.GetValues<IssueSource>()`, with `Content` bound to the label; the list is immutable, so no `ObservableCollection` is needed. Declare `public static readonly TimeSpan StuckDeploy = TimeSpan.FromMinutes(30);`. Everything is synchronous, with no `Task`.

## Design Decisions

**Decision**: Mirror the server's vocabulary by hand instead of sharing a module.
**Rationale**: Both files' doc comments name each other and promise "same union, same labels, same order". The client indexes `SOURCE_LABEL[row.source]`, so agreement is what keeps labels from rendering `undefined`. No shared package, generator or parity test exists, so agreement rests on editing both files together.
**Approved**: pending

**Decision**: Keep `glitchtip` as its own source rather than folding it into `http`.
**Rationale**: The doc comment says the other sources answer reachability while GlitchTip answers whether the site is throwing, and a site can be up on every probe with an error Problem open.
**Approved**: pending

**Decision**: Keep `STUCK_DEPLOY_MS` on the client even though no client code derives stuck Problems from it.
**Rationale**: The doc comment calls it a "mirror of the server threshold" and records the owner call of 2026-07-10 that an in-flight `building` row is activity, never a Problem. The constant stays as documentation of the backend's rule; the stuck verdict itself comes from the server.
**Approved**: pending

**Decision**: Add `isIssueSource` on the client only.
**Rationale**: Its doc comment says it lets a caller "filter/index by it without an unchecked `as IssueSource` cast". `row-model.ts` explains that `Row.source` is a plain string that can fall back to an activity `kind`, and the guard turns the fallback into a real branch.
**Approved**: pending

**Decision**: The platform-unreachable debounce stays out of this module.
**Rationale**: The closing note says the server's `applyPlatformIssues` and the `platform_health_state` table own the streak and threshold and publish a `platform-health|<source>` Problem, which the client renders as given.
**Approved**: pending
