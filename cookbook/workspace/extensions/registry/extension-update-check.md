---
id: d4be0c36-834c-41aa-af89-478eaf660e0f
title: Extension Update Check
domain: agentictoolkit://cookbook/workspace/extensions/registry/extension-update-check
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Concurrently asks an Open VSX registry whether each installed extension has
  a newer, actually-installable version, without one failed lookup failing the rest.
platforms:
- swift
- macos
tags:
- extensions
- update-check
- openvsx-registry
- semantic-versioning
depends-on: []
related:
- agentictoolkit://cookbook/workspace/extensions/manifest/extension-manifest
references:
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionUpdateCheck.swift (apple)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/ExtensionUpdateCheckTests.swift
  (apple)
approved-by: ''
approved-date: ''
---

# Extension Update Check

## Overview

The update check answers whether one installed extension — or a whole list of them — has a newer version this host could actually run. It holds a registry client and the host's declared semantic version, and it offers two operations: checking a single installed extension, which answers for that one extension, and checking a list, which answers for every extension in the list by running one per-extension lookup concurrently and folding the results into an update report. The contract's defining rule is that a newer version is reported only when installing it would succeed: each candidate is run through the same installability gate the installer uses, and a newer version that fails it is treated as no update at all, not as an update the caller must separately refuse.

## Behavioral Requirements

- **default-client**: Checking a single installed extension MUST default its registry-client parameter to a fresh instance of the default registry client when the caller supplies none.
- **default-host-version**: Checking a single installed extension MUST default its host-version parameter to the host's own declared version when the caller supplies none.
- **publisher-required**: Checking a single installed extension MUST throw a no-publisher error naming the installed extension's identifier when the installed extension's manifest publisher is absent or the empty string, before making any registry request.
- **registry-lookup-by-manifest-fields**: Checking a single installed extension MUST request the registry's detail record using the manifest's publisher and name fields verbatim, rather than splitting the extension's case-folded identifier string back apart, because a publisher name containing a "." would split at the wrong place, and the identifier's case-folding is this host's own convention, not the registry's.
- **latest-version-requested**: Checking a single installed extension MUST request the registry's detail record with no version specified, so the registry returns the latest published version rather than a specific one.
- **versions-must-both-parse**: Checking a single installed extension MUST throw a versions-not-comparable error, carrying both the installed and published version strings, when either the installed version or the published version fails to parse as a semantic version.
- **no-downgrade-offered**: Checking a single installed extension MUST answer "no update" when the parsed published version is not strictly greater than the parsed installed version — covering both an equal version and a published version older than what is installed.
- **installability-gate**: Checking a single installed extension MUST answer "no update", and MUST NOT report an update, when the candidate's installability verdict against this host's version is anything other than installable, even though the published version is strictly newer than the installed one.
- **update-value-shape**: When a candidate is strictly newer and installable, checking a single installed extension MUST return an update record whose identifier is the installed extension's identifier, whose installed-version is the installed manifest's raw version string (not the parsed semantic version), and whose latest field is the full detail record the registry returned.
- **concurrent-per-extension-lookup**: Checking a list of installed extensions MUST run exactly one per-extension lookup for each element of the list, and MUST run every element's lookup concurrently rather than sequentially.
- **per-lookup-failure-isolation**: Checking a list of installed extensions MUST NOT fail, throw, or omit results for the extensions whose lookup succeeded when one or more other extensions' lookups fail; a failed lookup MUST be represented as an entry in the returned report's not-checkable list rather than aborting the whole call.
- **check-never-throws**: Checking a list of installed extensions MUST itself never throw; every error a single-extension check can raise, and any other error a registry request can raise, MUST be caught internally and converted into a not-checkable entry rather than propagated to the caller.
- **updates-sorted-by-identifier**: Checking a list of installed extensions MUST return its updates list sorted ascending by identifier using ordinary string ordering, regardless of the order in which the concurrent lookups complete.
- **unavailable-sorted-by-identifier**: Checking a list of installed extensions MUST return its not-checkable list sorted ascending by identifier using ordinary string ordering, regardless of the order in which the concurrent lookups complete.
- **empty-input-empty-report**: Checking a list of installed extensions MUST return a report with an empty updates list and an empty not-checkable list when the input list is empty.
- **error-classification-not-published**: Resolving one extension's outcome MUST classify a caught error as "not published" when, and only when, the registry answered with an HTTP 404 status.
- **error-classification-no-publisher**: Resolving one extension's outcome MUST classify a caught error as "no publisher" when the error is the no-publisher error.
- **error-classification-version-not-comparable**: Resolving one extension's outcome MUST classify a caught error as "versions not comparable" when the error is the versions-not-comparable error.
- **error-classification-default-unreachable**: Resolving one extension's outcome MUST classify every caught error that is not one of the three cases above — including every other registry-client failure and any error of a type this component does not otherwise recognize — as "registry unreachable".
- **failure-logged-at-debug**: Resolving one extension's outcome MUST log a debug-level message naming the failed extension's identifier and a description of the error, for every caught error, before returning the not-checkable outcome.
- **report-carries-both-arrays**: The update report MUST expose both an updates list and a not-checkable list as separate lists on every result, so that "nothing to update" and "some extensions could not be asked about" remain distinguishable to a caller.
- **value-type-equatability**: The update record, the not-checkable entry, its reason value, and the update report MUST each support value equality comparison, and MUST each be safe to share across concurrent tasks.
- **error-type-equatability**: The update-check error type MUST support value equality comparison and MUST be safe to share across concurrent tasks, with exactly two cases: no-publisher (carrying an identifier) and versions-not-comparable (carrying the installed and published version strings).
- **concurrent-safe-outcome-type**: The internal per-extension outcome value used while checking a list MUST be safe to share across concurrent tasks, since it is produced inside a concurrently-executing lookup and read back afterward.

## Appearance

Not applicable — this is a non-UI logic component (a registry lookup and
report-assembly concept), not a visual component.

## States

Not applicable — this is a non-UI logic component. The only runtime states
are the per-extension outcomes captured under Behavioral Requirements
(update, up-to-date, not-checkable), not a visual-state machine.

## Accessibility

Not applicable — this is a non-UI logic component with no rendered surface,
role, label, or focus target of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| extension-update-001 | no-downgrade-offered, update-value-shape | Installed `acme.widget` at `1.0.0`; registry answers `2.0.0` (universal, `engines.vscode: ^1.74.0`) | Checking this extension returns an update record with identifier `"acme.widget"`, installed-version `"1.0.0"`, latest-version `"2.0.0"` |
| extension-update-002 | no-downgrade-offered | Installed `acme.widget` at `1.0.0`; registry answers `1.0.0` | Checking this extension returns no update |
| extension-update-003 | no-downgrade-offered | Installed `acme.widget` at `1.0.0`; registry answers `0.9.0` | Checking this extension returns no update |
| extension-update-004 | registry-lookup-by-manifest-fields | Installed with `publisher: "my.company"` at `1.0.0`; registry stubbed at path `/my.company/widget` answering `namespace: "my.company"`, `2.0.0` | Checking this extension returns latest-version `"2.0.0"`, and the request path ends with `/my.company/widget`, not a path split on the interior dot |
| extension-update-005 | installability-gate | Installed `acme.widget` at `1.0.0`; registry answers `2.0.0` with `engines.vscode: "^1.200.0"` (past the host's declared `1.138.0`) | Checking this extension returns no update even though `2.0.0 > 1.0.0` |
| extension-update-006 | installability-gate | Installed `acme.widget` at `1.0.0`; registry answers `2.0.0` with `targetPlatform: "darwin-arm64"` | Checking this extension returns no update |
| extension-update-007 | publisher-required | Installed with no publisher, name `"widget"` | Checking this extension throws the no-publisher error naming `"widget"` |
| extension-update-008 | versions-must-both-parse | Installed `acme.widget` at `1.0.0`; registry answers version `"nightly-build"` | Checking this extension throws the versions-not-comparable error, carrying `"1.0.0"` and `"nightly-build"` |
| extension-update-009 | per-lookup-failure-isolation, error-classification-not-published, updates-sorted-by-identifier | Checking a list of `[current@1.0.0→registry 1.0.0, stale@2.0.0→registry 3.0.0, private@0.1.0→registry unstubbed/404]` | The updates list contains only `"acme.stale"`, with latest-version `"3.0.0"`; the not-checkable list contains `"acme.private"` with reason "not published" |
| extension-update-010 | error-classification-default-unreachable | Checking a list of `[acme.widget@1.0.0]`; registry answers status `503` | The updates list is empty; the not-checkable list contains `"acme.widget"` with reason "registry unreachable" |
| extension-update-011 | error-classification-no-publisher | Checking a list of one installed extension with no publisher | The not-checkable list's reason is "no publisher" |
| extension-update-012 | error-classification-version-not-comparable | Checking a list of one installed extension with version `"nightly"`; registry answers `2.0.0` | The not-checkable list contains `"acme.widget"` with reason "versions not comparable" |
| extension-update-013 | unavailable-sorted-by-identifier | Checking a list of two installed extensions with no publisher, named `"zebra"` and `"alpha"` | The not-checkable list's identifiers are ordered `["alpha", "zebra"]` |
| extension-update-014 | updates-sorted-by-identifier, concurrent-per-extension-lookup | Checking a list of `[zebra, alpha, middle]`, each installed at `1.0.0`, each registry stub answering `2.0.0` | The updates list's identifiers are ordered `["acme.alpha", "acme.middle", "acme.zebra"]` regardless of which lookup completes first |
| extension-update-015 | empty-input-empty-report | Checking an empty list | Both the updates list and the not-checkable list are empty |

## Edge Cases

- **Empty installed list**: checking an empty list MUST return a report with
  both lists empty; this is not an error condition. MUST behave this way.
- **Publisher is absent**: checking a single installed extension MUST throw
  the no-publisher error before making any request; when checking a list
  this surfaces as a "no publisher" not-checkable entry rather than a
  thrown error. MUST behave this way.
- **Publisher is the empty string**: treated identically to an absent
  publisher — a manifest whose publisher decoded as the empty string MUST
  also throw the no-publisher error. MUST behave this way.
- **Installed or published version string does not parse** (for example
  `"nightly-build"`, a prerelease suffix such as `"1.0.0-rc.1"`, or any
  string that fails to parse as a plain `major.minor.patch` version): MUST
  throw the versions-not-comparable error rather than compare on string
  inequality — version parsing accepts only a bare `major.minor.patch` form
  with no prerelease or build-metadata grammar, so any such string reaches
  this path as unparseable, not as a special case this concept itself
  distinguishes. MUST behave this way.
- **Published version equal to or older than installed**: MUST answer "no
  update" — not an error, and specifically not an offered downgrade, since
  the registry can legitimately be behind a self-hosted mirror mid-sync.
  MUST behave this way.
- **Published version is newer but fails the installability gate**
  (engine-incompatible, platform-specific, no-universal-build, or
  engine-range-unreadable): MUST answer "no update", identical to the "no
  update" outcome for an equal or older version — a caller cannot
  distinguish "already current" from "a newer, uninstallable build exists"
  from the return value alone. MUST behave this way.
- **Registry answers 404**: classified as "not published", the expected
  outcome for a sideloaded, unpublished, or private extension — this MUST
  NOT fail the enclosing batch check.
- **Registry answers any other non-2xx status, or the request fails to
  reach the registry at all** (a malformed registry URL, an undecodable
  response body, a transport-level failure such as no network connectivity
  or a request timeout, or a cancelled request surfacing as a thrown
  error): all of these MUST classify as "registry unreachable", the same
  reason a `503` produces — only "no such extension" (404) is distinguished
  from "no usable answer" (every other failure); the causes of "no usable
  answer" are not further distinguished.
- **Concurrent lookups, and their completion order**: checking a list MUST
  run every extension's lookup concurrently, and the outcome lists MUST be
  independent of which lookup completes first — this is guaranteed by an
  explicit sort applied after every result has been collected, not by any
  ordering the concurrency mechanism itself provides.
- **Duplicate entries in the installed list sharing the same identifier**:
  not addressed as a distinct case — checking a list adds one lookup per
  list element with no de-duplication by identifier, so two entries for the
  same extension produce two independent lookups and, in general, two
  entries in the resulting updates or not-checkable list. Because the sort
  applied afterward is stable, the relative order between two entries
  sharing an identifier is whichever order the concurrent lookups happened
  to complete in, which is not deterministic across runs.
- **A dependency (the registry) is unavailable for the whole call, not just
  one extension**: no distinct code path exists for "the registry as a
  whole is down" versus "this one lookup failed" — every extension whose
  lookup reaches the registry and gets no usable answer is reported
  individually as "registry unreachable" in the not-checkable list; there
  is no fail-fast short-circuit that stops issuing further lookups once one
  has failed this way.
- **Offline / disconnected state**: not a state this component detects or
  reports as such — a lost connection during a lookup surfaces as a
  transport error from the registry client, classified identically to a
  reachable-but-failing registry; this component has no separate concept of
  "offline".

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| registry client | the registry client used for lookups | a default client pointed at the public Open VSX registry (`https://open-vsx.org/api`) | The client the check issues lookups through; injectable so tests can point it at a stub registry. |
| host version | a semantic version | the host's declared VS Code version (`1.138.0`) | The host version passed to the installability gate for every candidate; a caller who wants to check against a different declared version supplies it here. |
| installed extensions | a list of installed-extension records | — (required parameter of the batch check) | The extensions to check, one lookup per element; supplying an empty list is valid and yields an empty report. |

## Deep Linking

Not applicable: this concept defines no URL, route, or scheme of its own —
it is a lookup-and-report concept with no navigable destination.

## Localization

Not applicable: no user-facing string is produced. The one string literal
built for a log message ("No update answer for ...") is a hardcoded English
debug-log message, not a user-facing string — it is never shown in any UI.

## Accessibility Options

Not applicable: this is a non-visual, backend logic component with no
rendered UI to respond to Reduce Motion, Increase Contrast, or Differentiate
Without Color.

## Feature Flags

Not applicable: no feature-flag check is declared; checking a list and
checking a single extension always run the same fixed logic unconditionally.

## Analytics

Not applicable: no event-emission or telemetry call of any kind is made;
every result is returned directly to the caller as typed data, never
recorded as an analytics event.

## Privacy

- **Data collected**: None persisted by this component. Per lookup,
  checking a single installed extension reads the fields the caller's
  installed-extension record already holds in memory — publisher, name, and
  version — and does not read or retain anything beyond those.
- **Storage**: Not applicable — this concept and the registry client it
  uses are documented as stateless and hold no cache; nothing is written to
  disk by this component.
- **Transmission**: Each single-extension check discloses the installed
  extension's publisher (as the registry namespace) and name to whichever
  registry the client addresses — the public registry unless a caller
  configured a different base — by placing them in the request path. The
  installed version string is read locally for comparison but is never sent
  to the registry; only namespace and name appear in the outgoing request.
- **Retention**: Not applicable — no data from this component is retained
  beyond the single check call; the registry client itself caches nothing
  between calls.

## Logging

Subsystem: the host's logging subsystem | Category: the update check's own category

| Event | Level | Message |
|-------|-------|---------|
| A single-extension check throws inside outcome resolution, for any reason (no publisher, incomparable versions, or any registry-client failure) | debug | `No update answer for <identifier>: <description of error>` |

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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/ExtensionUpdateCheck.swift` |

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

**Decision** (Swift implementation): Run every extension's registry lookup
concurrently via `withTaskGroup`, and restore a deterministic order
afterward by explicitly sorting both result arrays by identifier, rather
than relying on any ordering the task group provides or checking
sequentially.
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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |

`separation-of-concerns` passes: `ExtensionUpdateCheck` owns only the
update-versus-not decision (version comparison, installability gating, and
per-extension failure classification); the URL-safety check on `publisher`
and `name` before they are spliced into a request path is delegated to
`OpenVSXClient.requireSafeComponent`, and the raw HTTP fetch and JSON decode
are delegated to `OpenVSXClient`/`BoundedBodyLoader` — this type never opens
a socket or builds a `URL` itself (`registry-lookup-by-manifest-fields`,
Overview). `graceful-degradation` passes: `check(_:)` is documented and
tested to isolate one extension's lookup failure from every other
extension's result, degrading a single failed lookup to one `notCheckable`
entry rather than failing the whole call (`per-lookup-failure-isolation`,
`check-never-throws`; test `oneUnknownExtensionDoesNotFailTheCheck`).
`explicit-error-handling` passes: every failure path is a named, typed case
— `ExtensionUpdateError.noPublisher`/`.versionNotComparable` thrown from
`update(for:)`, and `ExtensionUpdateUnavailable.Reason`'s four cases
classifying what `outcome(for:)` catches — with no unlabeled `catch {}`
that discards the error without recording a reason
(`error-classification-not-published` through
`error-classification-default-unreachable`, `failure-logged-at-debug`).
`unit-test-coverage` passes: `ExtensionUpdateCheckTests.swift` runs fifteen
`@Test` functions covering the update-found path, both no-update paths
(equal and older version), both installability-refusal paths tested
directly (engine-incompatible, platform-specific), both thrown-error paths,
the whole-list `check(_:)` behavior including one failure not sinking the
batch, all four `Reason` classifications, sort order under both concurrent
and empty input, and the dotted-publisher addressing case.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/registry/. |
