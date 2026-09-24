---
id: d4be0c36-834c-41aa-af89-478eaf660e0f
title: ExtensionUpdateCheck
domain: agentictoolkit://recipes/extension-host-core-extensions-extension-update-check
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
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
- agentictoolkit://recipes/extension-host-core-extensions-extension-manifest
references:
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionUpdateCheck.swift (apple)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/ExtensionUpdateCheckTests.swift
  (apple)
approved-by: ''
approved-date: ''
---

# ExtensionUpdateCheck

## Overview

`ExtensionUpdateCheck` is a stateless `Sendable` struct that answers whether
one installed extension — or a whole list of them — has a newer version this
host could actually run. It holds an `OpenVSXClient` and the host's declared
`SemanticVersion`, and its two public operations are `update(for:)`, which
answers for one `LoadedExtension`, and `check(_:)`, which answers for a list
by running one `update(for:)` lookup per extension concurrently and folding
the results into an `ExtensionUpdateReport` (source:
`packages/apple/AgenticToolkit/Core/Extensions/ExtensionUpdateCheck.swift`
lines 19–97). The contract's defining rule, stated in the type's own doc
comment (lines 9–18), is that a newer version is reported only when
installing it would succeed: each candidate is run through the same
`OpenVSXExtensionDetail.installability(forHostVersion:)` gate the installer
uses, and a newer version that fails it is treated as no update at all, not
as an update the caller must separately refuse.

## Behavioral Requirements

- **default-client**: `ExtensionUpdateCheck.init` MUST default its `client`
  parameter to `OpenVSXClient()` when the caller supplies none (lines 24–26).
- **default-host-version**: `ExtensionUpdateCheck.init` MUST default its
  `hostVersion` parameter to `ExtensionRegistry.declaredVSCodeVersion` when
  the caller supplies none (line 26).
- **publisher-required**: `update(for:)` MUST throw
  `ExtensionUpdateError.noPublisher(installed.identifier)` when
  `installed.manifest.publisher` is `nil` or the empty string, before making
  any registry request (lines 975–977).
- **registry-lookup-by-manifest-fields**: `update(for:)` MUST request the
  registry's detail record by calling
  `client.detail(namespace: installed.manifest.publisher, name: installed.manifest.name)`,
  using the manifest's `publisher` and `name` fields verbatim rather than
  splitting `installed.identifier` (the case-folded `publisher.name` string)
  back apart, because a publisher name containing a `.` would split at the
  wrong place and the identifier's case-folding is this host's convention,
  not the registry's (lines 970–978).
- **latest-version-requested**: `update(for:)` MUST call `client.detail`
  with no `version` argument, so the registry returns the latest published
  version rather than a specific one (line 978).
- **versions-must-both-parse**: `update(for:)` MUST throw
  `ExtensionUpdateError.versionNotComparable(installed: installed.manifest.version, published: latest.version)`
  when `SemanticVersion(installed.manifest.version)` is `nil`, when
  `latest.semanticVersion` is `nil`, or both (lines 980–988).
- **no-downgrade-offered**: `update(for:)` MUST return `nil` when the parsed
  published version is not strictly greater than the parsed installed
  version — covering both an equal version and a published version that is
  older than what is installed (lines 989 and the doc comment on
  `ExtensionUpdateError.versionNotComparable`, lines 982–985).
- **installability-gate**: `update(for:)` MUST return `nil`, and MUST NOT
  return an `ExtensionUpdate`, when
  `latest.installability(forHostVersion: hostVersion)` is not `.installable`,
  even though the published version is strictly newer than the installed one
  (lines 991–994).
- **update-value-shape**: When a candidate is strictly newer and installable,
  `update(for:)` MUST return an `ExtensionUpdate` whose `identifier` is
  `installed.identifier`, whose `installedVersion` is
  `installed.manifest.version` (the raw string, not the parsed
  `SemanticVersion`), and whose `latest` is the full `OpenVSXExtensionDetail`
  the registry returned (lines 995–998).
- **concurrent-per-extension-lookup**: `check(_:)` MUST run exactly one
  `outcome(for:)` lookup per element of `installed`, and MUST run every
  element's lookup concurrently rather than sequentially, using a
  `withTaskGroup` over one child task per extension (lines 947–951).
- **per-lookup-failure-isolation**: `check(_:)` MUST NOT fail, throw, or omit
  results for the extensions whose lookup succeeded when one or more other
  extensions' lookups fail; a failed lookup MUST be represented as an entry
  in the returned report's `notCheckable` array rather than aborting the
  whole call (lines 1001–1015, `outcome(for:)`'s internal `catch`).
- **check-never-throws**: `check(_:)` MUST be a non-throwing `async` function;
  every error `update(for:)` can raise, and any other error a registry
  request can raise, MUST be caught inside `outcome(for:)` and converted into
  an `ExtensionUpdateUnavailable` entry rather than propagated to `check(_:)`'s
  caller (line 947 signature; lines 1001–1015).
- **updates-sorted-by-identifier**: `check(_:)` MUST return
  `ExtensionUpdateReport.updates` sorted ascending by `identifier` using
  `String`'s default `<` operator, regardless of the order in which the
  concurrent lookups complete (lines 952, 954–957, 962).
- **unavailable-sorted-by-identifier**: `check(_:)` MUST return
  `ExtensionUpdateReport.notCheckable` sorted ascending by `identifier` using
  `String`'s default `<` operator, regardless of the order in which the
  concurrent lookups complete (lines 953, 954–957, 963).
- **empty-input-empty-report**: `check(_:)` MUST return an
  `ExtensionUpdateReport` with an empty `updates` array and an empty
  `notCheckable` array when `installed` is an empty array (lines 947–965; no
  branch runs when the task group is given no tasks to add).
- **error-classification-not-published**: `outcome(for:)` MUST classify a
  caught error as `ExtensionUpdateUnavailable.Reason.notPublished` when, and
  only when, the error is `OpenVSXError.requestFailed(_, status: 404)`
  (lines 1029, 1036–1037).
- **error-classification-no-publisher**: `outcome(for:)` MUST classify a
  caught error as `.noPublisher` when the error is
  `ExtensionUpdateError.noPublisher` (line 1033).
- **error-classification-version-not-comparable**: `outcome(for:)` MUST
  classify a caught error as `.versionNotComparable` when the error is
  `ExtensionUpdateError.versionNotComparable` (line 1034).
- **error-classification-default-unreachable**: `outcome(for:)` MUST
  classify every caught error that is not one of the three cases above —
  including every other `OpenVSXError` case (`requestFailed` with a status
  other than 404, `malformedRegistryURL`, `undecodableResponse`,
  `artifactNotFetchable`, `artifactTooLarge`, `unsafeIdentity`,
  `responseNotHTTP`, `responseTooLarge`) and any error of a type this
  component does not otherwise recognize — as
  `.registryUnreachable` (lines 1038–1040, `default: return .registryUnreachable`).
- **failure-logged-at-debug**: `outcome(for:)` MUST log a `debug`-level
  message naming the failed extension's `identifier` and
  `String(describing: error)` for every caught error, before returning the
  `.notCheckable` outcome (lines 1006–1010).
- **report-carries-both-arrays**: `ExtensionUpdateReport` MUST expose both
  `updates: [ExtensionUpdate]` and `notCheckable: [ExtensionUpdateUnavailable]`
  as separate arrays on every `check(_:)` result, so that "nothing to update"
  and "some extensions could not be asked about" remain distinguishable to a
  caller (lines 1109–1122, doc comment lines 1109–1113).
- **value-type-equatability**: `ExtensionUpdate`, `ExtensionUpdateUnavailable`,
  `ExtensionUpdateUnavailable.Reason`, and `ExtensionUpdateReport` MUST each
  conform to `Equatable` and `Sendable` (lines 1055, 1076, 1078, 1114).
- **error-type-equatability**: `ExtensionUpdateError` MUST conform to `Error`,
  `Sendable`, and `Equatable`, with exactly two cases, `noPublisher(String)`
  and `versionNotComparable(installed: String, published: String)`
  (lines 1124–1129).
- **non-sendable-lookup-result-type**: the private `ExtensionUpdateOutcome`
  enum used inside `check(_:)`'s task group MUST conform to `Sendable`, since
  it is the type parameter of `withTaskGroup(of:)` and is produced inside a
  concurrently-executing child task (line 947, line 1043).

## Appearance

Not applicable — this is a non-UI logic component (a registry lookup and
report-assembly type), not a visual component.

## States

Not applicable — this is a non-UI logic component. The only runtime states
are the per-extension outcomes captured under Behavioral Requirements
(`update`, `upToDate`, `notCheckable`), not a visual-state machine.

## Accessibility

Not applicable — this is a non-UI logic component with no rendered surface,
role, label, or focus target of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| extension-update-001 | no-downgrade-offered, update-value-shape | Installed `acme.widget` at `1.0.0`; registry answers `2.0.0` (universal, `engines.vscode: ^1.74.0`) | `update(for:)` returns an `ExtensionUpdate` with `identifier == "acme.widget"`, `installedVersion == "1.0.0"`, `latestVersion == "2.0.0"` (test `newerVersionIsAnUpdate`) |
| extension-update-002 | no-downgrade-offered | Installed `acme.widget` at `1.0.0`; registry answers `1.0.0` | `update(for:)` returns `nil` (test `sameVersionIsNotAnUpdate`) |
| extension-update-003 | no-downgrade-offered | Installed `acme.widget` at `1.0.0`; registry answers `0.9.0` | `update(for:)` returns `nil` (test `olderPublishedVersionIsNotAnUpdate`) |
| extension-update-004 | registry-lookup-by-manifest-fields | Installed with `publisher: "my.company"` at `1.0.0`; registry stubbed at path `/my.company/widget` answering `namespace: "my.company"`, `2.0.0` | `update(for:)` returns `latestVersion == "2.0.0"`, and the request path ends with `/my.company/widget`, not a path split on the interior dot (test `lookupUsesThePublisherVerbatim`) |
| extension-update-005 | installability-gate | Installed `acme.widget` at `1.0.0`; registry answers `2.0.0` with `engines.vscode: "^1.200.0"` (past the host's declared `1.138.0`) | `update(for:)` returns `nil` even though `2.0.0 > 1.0.0` (test `newerButIncompatibleIsNotOffered`) |
| extension-update-006 | installability-gate | Installed `acme.widget` at `1.0.0`; registry answers `2.0.0` with `targetPlatform: "darwin-arm64"` | `update(for:)` returns `nil` (test `newerPlatformSpecificIsNotOffered`) |
| extension-update-007 | publisher-required | Installed with `publisher: nil`, name `"widget"` | `update(for:)` throws `ExtensionUpdateError.noPublisher("widget")` (test `noPublisherThrows`) |
| extension-update-008 | versions-must-both-parse | Installed `acme.widget` at `1.0.0`; registry answers version `"nightly-build"` | `update(for:)` throws `ExtensionUpdateError.versionNotComparable(installed: "1.0.0", published: "nightly-build")` (test `incomparableVersionsThrow`) |
| extension-update-009 | per-lookup-failure-isolation, error-classification-not-published, updates-sorted-by-identifier | `check([current@1.0.0→registry 1.0.0, stale@2.0.0→registry 3.0.0, private@0.1.0→registry unstubbed/404])` | `report.updates.map(\.identifier) == ["acme.stale"]`, `report.updates.first?.latestVersion == "3.0.0"`, `report.notCheckable == [.init(identifier: "acme.private", reason: .notPublished)]` (test `oneUnknownExtensionDoesNotFailTheCheck`) |
| extension-update-010 | error-classification-default-unreachable | `check([acme.widget@1.0.0])`; registry answers status `503` | `report.updates.isEmpty`; `report.notCheckable == [.init(identifier: "acme.widget", reason: .registryUnreachable)]` (test `aFailingRegistryIsUnreachableRatherThanUnknown`) |
| extension-update-011 | error-classification-no-publisher | `check([installed(publisher: nil)])` | `report.notCheckable.map(\.reason) == [.noPublisher]` (test `aManifestWithNoPublisherSaysSo`) |
| extension-update-012 | error-classification-version-not-comparable | `check([installed(version: "nightly")])`; registry answers `2.0.0` | `report.notCheckable == [.init(identifier: "acme.widget", reason: .versionNotComparable)]` (test `anIncomparableVersionSaysSo`) |
| extension-update-013 | unavailable-sorted-by-identifier | `check([installed(name: "zebra", publisher: nil), installed(name: "alpha", publisher: nil)])` | `report.notCheckable.map(\.identifier) == ["alpha", "zebra"]` (test `theUnavailableAreSorted`) |
| extension-update-014 | updates-sorted-by-identifier, concurrent-per-extension-lookup | `check([zebra, alpha, middle])`, each installed at `1.0.0`, each registry stub answering `2.0.0` | `report.updates.map(\.identifier) == ["acme.alpha", "acme.middle", "acme.zebra"]` regardless of stub-answer arrival order (test `resultsAreSorted`) |
| extension-update-015 | empty-input-empty-report | `check([])` | `report.updates.isEmpty && report.notCheckable.isEmpty` (test `emptyInputIsEmptyReport`) |

## Edge Cases

- **Empty `installed` array**: `check([])` MUST return a report with both
  arrays empty; this is not an error condition (MUST, traced to
  `emptyInputIsEmptyReport`; requirement `empty-input-empty-report`).
- **Publisher is `nil`**: `update(for:)` MUST throw `.noPublisher` before
  making any request; in `check(_:)` this surfaces as a `.noPublisher`
  `notCheckable` entry rather than a thrown error (MUST, traced to
  `noPublisherThrows` and `aManifestWithNoPublisherSaysSo`).
- **Publisher is the empty string**: treated identically to `nil` — the guard
  is `!publisher.isEmpty`, so a manifest that decoded `publisher` as `""`
  MUST also throw `.noPublisher` (MUST, traced to line 975).
- **Installed or published version string does not parse as
  `major[.minor[.patch]]`** (e.g. `"nightly-build"`, a prerelease suffix such
  as `"1.0.0-rc.1"`, or any string `SemanticVersion.init?` rejects): MUST
  throw `.versionNotComparable` rather than compare on string inequality
  (MUST, traced to `incomparableVersionsThrow`; `SemanticVersion.init?` is
  documented, in `SemanticVersion.swift`, as parsing only bare
  `major.minor.patch` with no prerelease or build-metadata grammar, so any
  such string reaches this path as an unparseable version, not a special
  case `ExtensionUpdateCheck` itself distinguishes).
- **Published version equal to or older than installed**: MUST return `nil`
  from `update(for:)` — not an error, and specifically not an offered
  downgrade, since the registry can legitimately be behind a self-hosted
  mirror mid-sync (MUST, traced to `sameVersionIsNotAnUpdate` and
  `olderPublishedVersionIsNotAnUpdate`).
- **Published version is newer but fails the installability gate**
  (`engineIncompatible`, `platformSpecific`, `noUniversalBuild`, or
  `engineRangeUnreadable`): MUST return `nil` from `update(for:)`, identical
  to the "no update" outcome for an equal or older version — a caller cannot
  distinguish "already current" from "a newer, uninstallable build exists"
  from the return value of `update(for:)` alone (MUST, traced to
  `newerButIncompatibleIsNotOffered` and `newerPlatformSpecificIsNotOffered`
  for two of the four `OpenVSXInstallability` non-`.installable` cases; the
  other two, `.noUniversalBuild` and `.engineRangeUnreadable`, are gated by
  the same `guard installability == .installable else { return nil }` at
  line 991 but have no dedicated test in
  `ExtensionUpdateCheckTests.swift`).
- **Registry answers 404**: classified as `.notPublished`, the expected
  outcome for a sideloaded, unpublished, or private extension — this MUST
  NOT fail the enclosing `check(_:)` call (MUST, traced to
  `oneUnknownExtensionDoesNotFailTheCheck`).
- **Registry answers any other non-2xx status, or the request fails to
  reach the registry at all** (a malformed registry URL, an undecodable
  response body, a transport-level failure such as no network connectivity
  or a request timeout, or `URLSession`/structured-concurrency task
  cancellation surfacing as a thrown error): all of these MUST classify as
  `.registryUnreachable`, the same reason a `503` produces — the source
  distinguishes only "no such extension" (404) from "no usable answer" (every
  other failure), and does not further distinguish among the causes of "no
  usable answer" (MUST, traced to `aFailingRegistryIsUnreachableRatherThanUnknown`
  and the `default:` branch at lines 1038–1039).
- **Concurrent lookups, and their completion order**: `check(_:)` MUST run
  every extension's lookup concurrently via `withTaskGroup`, and the outcome
  arrays MUST be independent of which task completes first — this is
  guaranteed by the explicit `sorted` calls after the `for await` loop
  collects every result, not by any ordering the task group itself provides
  (MUST, traced to `resultsAreSorted`, which stubs three registry answers
  and asserts the identifier order of the result regardless of arrival
  order).
- **Duplicate entries in `installed` sharing the same identifier**: not
  addressed by the source as a distinct case — `check(_:)` adds one task per
  array element with no de-duplication by `identifier`, so two entries for
  the same extension produce two independent lookups and, in general, two
  entries in the resulting `updates` or `notCheckable` array. Because
  `sorted(by:)` in Swift is a stable sort, the relative order between two
  entries that share an identical `identifier` after sorting is whichever
  order the concurrent lookups happened to complete in, which is not
  deterministic across runs (fact, traced to the absence of any
  identifier-grouping step in `check(_:)`, lines 947–965).
- **A dependency (the registry) is unavailable for the whole call, not just
  one extension**: no distinct code path exists for "the registry as a
  whole is down" versus "this one lookup failed" — every extension whose
  lookup reaches the registry and gets no usable answer is reported
  individually as `.registryUnreachable` in `notCheckable`; there is no
  fail-fast short-circuit that stops issuing further lookups once one has
  failed this way (fact, traced to `outcome(for:)`'s per-task `catch`, lines
  1001–1015, which is scoped to one extension with no shared state across
  tasks).
- **Offline / disconnected state**: not a state this component detects or
  reports as such — a lost connection during a lookup throws a transport
  error from `OpenVSXClient`, which `outcome(for:)`'s `default:` branch
  classifies as `.registryUnreachable`, identically to a reachable-but-failing
  registry (fact, traced to the same `default:` branch, lines 1038–1039;
  `ExtensionUpdateCheck` has no separate concept of "offline").

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `client` | `OpenVSXClient` | `OpenVSXClient()` (the public Open VSX registry at `https://open-vsx.org/api`) | The registry client `update(for:)` and `check(_:)` issue lookups through; injected so tests can point it at a stub registry (lines 24–25). |
| `hostVersion` | `SemanticVersion` | `ExtensionRegistry.declaredVSCodeVersion` (`1.138.0`) | The host version passed to `OpenVSXExtensionDetail.installability(forHostVersion:)` for every candidate; a caller who wants to check against a different declared version supplies it here (line 26). |
| `installed` | `[LoadedExtension]` | — (required parameter of `check(_:)`) | The extensions to check, one lookup per element; supplying `[]` is valid and yields an empty report (line 947). |

## Deep Linking

Not applicable: the source defines no URL, route, or scheme of its own — it
is a lookup-and-report type with no navigable destination (traced to the
full body of `ExtensionUpdateCheck.swift`, which declares no `URL` route or
scheme type).

## Localization

Not applicable: the source contains no user-facing string. The one string
literal built for display purposes, `"No update answer for \(...): \(...)"`
(line 108), is a hardcoded English debug-log message, not a user-facing
string — it is never shown in any UI (traced to the full body of the source
file, which returns only typed values — `ExtensionUpdate`,
`ExtensionUpdateUnavailable`, `ExtensionUpdateReport`, or a thrown
`ExtensionUpdateError` case — to its caller).

## Accessibility Options

Not applicable: this is a non-visual, backend logic component with no
rendered UI to respond to Reduce Motion, Increase Contrast, or Differentiate
Without Color (traced to the source, which contains no UI code of any kind).

## Feature Flags

Not applicable: the source declares no feature-flag check; `check(_:)` and
`update(for:)` always run the same fixed logic unconditionally (traced to
the full body of the source file, which contains no flag or configuration
lookup).

## Analytics

Not applicable: the source contains no event-emission or telemetry call of
any kind; every result is returned directly to the caller as typed data,
never recorded as an analytics event (traced to the full body of the source
file).

## Privacy

- **Data collected**: None persisted by this component. Per lookup,
  `update(for:)` reads the fields the caller's `LoadedExtension.manifest`
  already holds in memory — `publisher`, `name`, and `version` — and does
  not read or retain anything beyond those (lines 975, 978, 980).
- **Storage**: Not applicable — `ExtensionUpdateCheck` and `OpenVSXClient`
  are documented as stateless and hold no cache (source doc comment on
  `OpenVSXClient`: "Stateless and `Sendable`... keeps no cache"); nothing is
  written to disk by this component.
- **Transmission**: Each `update(for:)` call discloses the installed
  extension's `publisher` (as the registry `namespace`) and `name` to
  whichever registry `client` addresses — the public
  `https://open-vsx.org/api` unless a caller configured a different
  `registryBase` — by placing them in the request path of
  `client.detail(namespace:name:)` (line 978). The installed `version`
  string is read locally for comparison but is never sent to the registry;
  only `namespace` and `name` appear in the outgoing request.
- **Retention**: Not applicable — no data from this component is retained
  beyond the single `update(for:)` or `check(_:)` call; `OpenVSXClient`
  itself caches nothing between calls.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (falls back to `"nil"` if unset, via
the shared `Loggable` protocol) | Category: `ExtensionUpdateCheck`

| Event | Level | Message |
|-------|-------|---------|
| `update(for:)` throws inside `outcome(for:)`, for any reason (no publisher, incomparable versions, or any `OpenVSXClient` failure) | debug | `No update answer for <identifier>: <String(describing: error)>` |

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
(source doc comment on `ExtensionUpdateCheck`, lines 9–18, annotated
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
comment at lines 970–974; test `lookupUsesThePublisherVerbatim`).
**Approved**: pending

**Decision**: Treat an unparseable version string on either side as a
thrown `versionNotComparable` error, never as "not an update" decided by
raw string inequality.
**Rationale**: Comparing version strings lexically would happily present a
downgrade as an update whenever string ordering and semantic ordering
disagree; refusing to decide is safer than deciding wrong, so the source
raises a distinct, typed error instead of silently falling through to "no
update" (inline comment at lines 982–986; test `incomparableVersionsThrow`).
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
result reproducible rather than the concurrency itself (doc comment at
lines 32–38; test `resultsAreSorted`).
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
apart for that reason (doc comments at lines 1017–1028 and 1109–1113; tests
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
