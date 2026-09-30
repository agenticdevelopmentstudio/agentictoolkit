<!-- leaf: implement-extension-host-core-1/extensions-extension-update-check--part-2 · source: extension-host-core-extensions-extension-update-check.md -->

# ExtensionUpdateCheck — continued (part 2)

## Platform Notes

- **SwiftUI**: The source itself:
  `packages/apple/AgenticToolkit/Core/Extensions/ExtensionUpdateCheck.swift`,
  part of the macOS-only `AgenticToolkitCore` framework target. It has no
  SwiftUI dependency — `ExtensionUpdateCheck` is plain `Foundation`/`OSLog`
  code. A SwiftUI settings screen listing available updates would call
  `check(_:)` from a `Task`, typically inside an `@Observable` view model
  that republishes the resulting `ExtensionUpdateReport` for the view to
  render, since `ExtensionUpdateCheck` itself has no observation mechanism
  and is a plain value type constructed fresh (or held) by that view model.
- **Compose**: Model `ExtensionUpdateCheck` as a Kotlin class holding an
  `OpenVSXClient`-equivalent and a `SemanticVersion`-equivalent host version,
  exposing `suspend fun check(installed: List<LoadedExtension>): ExtensionUpdateReport`
  and `suspend fun update(installed: LoadedExtension): ExtensionUpdate?`.
  Use `coroutineScope { installed.map { async { outcome(it) } }.awaitAll() }`
  in place of `withTaskGroup`, then `sortedBy { it.identifier }` on both
  result lists — Kotlin's `sortedBy` is a stable sort, the same property the
  Swift port relies on for a deterministic duplicate-identifier order. Model
  `ExtensionUpdateError` as a `sealed class` with `NoPublisher` and
  `VersionNotComparable` subtypes, and classify caught exceptions the same
  way `reason(for:)` does, with an `else` branch mapping to
  `RegistryUnreachable`.
- **React/Web**: Port to an async function pair,
  `async function checkForUpdates(installed: LoadedExtension[]): Promise<ExtensionUpdateReport>`
  and `async function updateFor(installed: LoadedExtension): Promise<ExtensionUpdate | null>`,
  using `Promise.allSettled` over one `outcomeFor(extension)` promise per
  installed extension (never `Promise.all`, since one rejection must not
  fail the batch), then sorting both result arrays by `identifier` with
  `Array.prototype.sort` — stable since ES2019, giving the same
  duplicate-identifier behavior as the Swift stable sort. Represent
  `ExtensionUpdateError` as a discriminated union
  (`{ kind: "no-publisher"; identifier: string } | { kind: "version-not-comparable"; installed: string; published: string }`)
  and classify a caught fetch failure by inspecting the HTTP status (404 vs.
  anything else) the same way `reason(for:)` does.
- **AppKit / UIKit**: No divergence from the SwiftUI bullet above — the
  source is framework-agnostic `Foundation`/`OSLog` code called identically
  from an AppKit-hosted caller. `AgenticToolkitCore` targets only macOS
  today; an iOS caller would first need the framework made available to an
  iOS target, but `ExtensionUpdateCheck` itself needs no AppKit/UIKit-specific
  change.
- **WinUI 3**: Port to a plain class,
  `internal sealed class ExtensionUpdateCheck`, constructed with an
  `OpenVsxClient` (wrapping `System.Net.Http.HttpClient` the way the source's
  `OpenVSXClient` wraps `URLSession`) and a `Version`-equivalent
  `hostVersion` — .NET's built-in `Version` type compares
  `major`/`minor`/`build`/`revision` the way `SemanticVersion` compares
  `major`/`minor`/`patch`, though its parser is more permissive than the
  source's `SemanticVersion.init?`, so the port should still reject any
  string with a prerelease or build-metadata suffix explicitly to preserve
  `versions-must-both-parse`. Implement `CheckAsync(IEnumerable<LoadedExtension>)`
  with `await Task.WhenAll(installed.Select(e => OutcomeForAsync(e)))`, where
  each `OutcomeForAsync` call already catches its own exceptions (mirroring
  `outcome(for:)`, never letting one candidate's `HttpRequestException` fault
  the `Task.WhenAll`), then order both result lists with
  `.OrderBy(x => x.Identifier, StringComparer.Ordinal)` — `Ordinal`, not a
  culture-aware comparer, to match the source's plain `String` `<` operator.
  Classify failures with a status-code check against `HttpStatusCode.NotFound`
  for `.notPublished` and every other failure (non-2xx, `TaskCanceledException`
  on timeout, `HttpRequestException` on no connectivity) into
  `RegistryUnreachable`, using `System.Text.Json` (`JsonSerializer`) in place
  of `JSONDecoder` for the registry's detail response and `Microsoft.Extensions.Logging`'s
  `ILogger.LogDebug` in place of `Logger.debug` for the one log line.

## Design Decisions

**Decision**: Gate every candidate through
`OpenVSXExtensionDetail.installability(forHostVersion:)` — the same check
the installer applies — before treating a newer published version as an
update, rather than reporting any version increase as an update.
**Rationale**: The registry publishes versions that raise `engines.vscode`
past what this host declares, and versions built for one native platform;
offering either as an update produces a button whose only outcome is a
refusal on install, so a version that fails installability is treated as
the end of that extension's updates for now rather than a broken offer
(source doc comment on `ExtensionUpdateCheck`, annotated
`*(principle-of-least-astonishment)*`; tests `newerButIncompatibleIsNotOffered`,
`newerPlatformSpecificIsNotOffered`).
**Approved**: pending

**Decision**: Address the registry by the manifest's `publisher` and `name`
fields directly, never by splitting `installed.identifier` (the case-folded
`"publisher.name"` string) back apart on its dot.
**Rationale**: A publisher name that itself contains a `.` — the source's
own example is `"my.company"` — would split at the wrong place under naive
re-splitting, and the identifier's case-folding is this host's own
convention for matching, not the registry's addressing scheme (inline
comment; test `lookupUsesThePublisherVerbatim`).
**Approved**: pending

**Decision**: Treat an unparseable version string on either side as a
thrown `versionNotComparable` error, never as "not an update" decided by
raw string inequality.
**Rationale**: Comparing version strings lexically would happily present a
downgrade as an update whenever string ordering and semantic ordering
disagree; refusing to decide is safer than deciding wrong, so the source
raises a distinct, typed error instead of silently falling through to "no
update" (inline comment; test `incomparableVersionsThrow`).
**Approved**: pending

**Decision**: Run every extension's registry lookup concurrently via
`withTaskGroup`, and restore a deterministic order afterward by explicitly
sorting both result arrays by identifier, rather than relying on any
ordering the task group provides or checking sequentially.
**Rationale**: The check is entirely network latency, and a user with
twenty extensions installed should not wait twenty sequential round trips;
running them together is strictly faster with no added risk, but task
completion order alone would reshuffle a panel's rows between two runs that
found the same answers, so the explicit `sorted` calls are what make the
result reproducible rather than the concurrency itself (doc comment; test `resultsAreSorted`).
**Approved**: pending

**Decision**: Report a lookup that could not be answered (`notCheckable`)
beside the updates rather than treating "found nothing" and "could not ask"
as the same outcome, and further split the reason a 404 gives from every
other kind of failure.
**Rationale**: An extension installed by hand and never published 404s
every single time; folding that into "up to date" would silently hide a
genuinely unknown extension, and folding it into every other failure mode
would tell a user whose network is down that most of their extensions do
not exist. The two questions a reader can act on differently —
"this was never published" versus "the registry did not answer" — are kept
apart for that reason (doc comments; tests
`oneUnknownExtensionDoesNotFailTheCheck` and
`aFailingRegistryIsUnreachableRatherThanUnknown`).
**Approved**: pending
