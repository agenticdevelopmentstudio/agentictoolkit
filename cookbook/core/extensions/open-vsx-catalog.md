---
id: 1bbc9593-4064-4e79-8bce-08b3cf00c13d
title: OpenVSXCatalog
domain: agentictoolkit://cookbook/core/extensions/open-vsx-catalog
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Codable models of Open VSX search and detail responses, with URL-shaped fields
  kept as strings and a pure installability verdict.
platforms:
- swift
- macos
tags:
- extensions
- open-vsx
- catalog
- decoding
- installability
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/Core/Extensions/OpenVSXCatalog.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/OpenVSXCatalogTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/VSCodeEngineRange.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SemanticVersion.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# OpenVSXCatalog

## Overview

`OpenVSXCatalog.swift` (`packages/apple/AgenticToolkit/Core/Extensions/OpenVSXCatalog.swift`,
inside the macOS-only `AgenticToolkitCore` framework target per `project.yml`)
is the `Codable` model of what the Open VSX registry's HTTP API returns: one
summary row from `GET /api/-/search` (`OpenVSXSearchEntry`), one page of that
search (`OpenVSXSearchPage`), and the full record for one version of one
extension from `GET /api/<namespace>/<name>` or `.../<version>`
(`OpenVSXExtensionDetail`). It has no visual surface, performs no network
request itself, and is not the code that fetches these responses — that is
`OpenVSXClient.swift`, out of this recipe's scope. Its defining discipline is
that every URL-shaped registry field decodes as `String`, never `URL`, so
that one entry with a malformed icon link never sinks the decode of the page
it appeared on; computed accessors parse each URL lazily, where it is used, so
a bad string costs exactly the accessor that reads it. The file's second job
is `OpenVSXExtensionDetail.installability(forHostVersion:)`, a pure function
from already-decoded metadata to a named `OpenVSXInstallability` verdict —
whether a given registry version could be installed into this host at all,
decided before any bytes are downloaded.

## Behavioral Requirements

- **url-shaped-fields-decoded-as-string**: `OpenVSXSearchEntry.files`,
  `OpenVSXExtensionDetail.downloads`, and `OpenVSXExtensionDetail.files` MUST
  decode as `[String: String]?`, never as a dictionary of `URL`, so a value
  that cannot parse as a URL costs only the computed accessor that reads it
  and never the decode of the entry or the page containing it.
- **search-entry-identifier-case-folded**: `OpenVSXSearchEntry.identifier`
  MUST return `` "\(namespace).\(name)".lowercased() ``.
- **search-entry-icon-url-resolves-independently**:
  `OpenVSXSearchEntry.iconURL` MUST return the parsed `URL` when
  `files["icon"]` is present and parseable, and MUST return `nil`, never
  throw, when the key is absent or the string is unparseable.
- **search-page-total-size-is-whole-result-set**:
  `OpenVSXSearchPage.totalSize` MUST report the size of the entire result set
  the query matched, not the number of elements in that page's `extensions`
  array, so a caller can decide whether to request another `offset`.
- **search-page-array-decode-is-all-or-nothing**:
  `OpenVSXSearchPage.extensions` MUST decode via `Decodable`'s synthesized
  array decoding, which MUST throw for the whole page when any one element is
  missing a required field (`namespace`, `name`, or `version`) or gives it
  the wrong JSON type — this file implements no per-element recovery for
  `OpenVSXSearchEntry` the way it does for a single URL-shaped field (48-52; contrast with **url-shaped-fields-decoded-as-string**).
- **extension-detail-identifier-case-folded**:
  `OpenVSXExtensionDetail.identifier` MUST return
  `` "\(namespace).\(name)".lowercased() `` and, for the same `namespace` and
  `name`, MUST equal `OpenVSXSearchEntry.identifier`, so a search row and a
  detail record for the same extension join without either side re-deriving
  the case-folding rule (see **search-entry-identifier-case-folded**).
- **license-field-carries-absence**: `OpenVSXExtensionDetail.license` MUST
  decode to `nil` when the `license` key is absent, and MUST preserve
  whatever string the registry sent verbatim — including an empty string —
  when the key is present, with no normalization between the two.
- **semantic-version-nil-on-non-semver**:
  `OpenVSXExtensionDetail.semanticVersion` MUST return `nil`, never throw or
  substitute a default, when `version` does not parse as `SemanticVersion`.
- **engine-range-nil-when-absent-or-unparseable**:
  `OpenVSXExtensionDetail.engineRange` MUST return `nil` both when `engines`
  is absent or has no `vscode` key, and when the `vscode` value is present
  but does not parse as `VSCodeEngineRange`, drawing no distinction between
  those two cases at this property; the distinction between "not gated" and
  "unreadable" is drawn only by `installability(forHostVersion:)`.
- **universal-download-is-the-only-download-url-exposed**:
  `OpenVSXExtensionDetail.universalDownloadURL` MUST return the parsed URL
  for `downloads["universal"]` only, and MUST return `nil` when that key is
  absent, even when `downloads` holds one or more other platform-keyed
  entries.
- **file-urls-resolve-per-named-key**: `sha256URL`, `signatureURL`,
  `publicKeyURL`, `licenseTextURL`, `readmeURL`, and `iconURL` on
  `OpenVSXExtensionDetail` MUST each resolve independently through the
  shared `fileURL(_:)` helper reading `files[key]`, and MUST each return
  `nil` on its own — with no effect on any other accessor — when its own key
  is absent or its value is unparseable.
- **web-extension-kind-is-advisory-only**: `declaresWebExtensionKind` MUST
  report whether the registry's `extensionKind` array contains the string
  `"web"`, and `installability(forHostVersion:)` MUST NOT read
  `extensionKind` or `declaresWebExtensionKind` at all when computing its
  verdict.
- **installability-checks-platform-before-download-existence**:
  `installability(forHostVersion:)` MUST return `.platformSpecific(platform)`
  when `targetPlatform` is present and not equal to the literal string
  `"universal"`, and MUST perform this check before checking whether a
  universal download exists.
- **installability-requires-a-universal-download**:
  `installability(forHostVersion:)` MUST return `.noUniversalBuild` when
  `universalDownloadURL` is `nil`, checked after the platform check and
  before any engine check.
- **installability-engine-gate-skipped-when-absent-or-empty**:
  `installability(forHostVersion:)` MUST treat a `nil` `engines["vscode"]`
  and an empty-string `engines["vscode"]` identically: both MUST skip the
  engine check entirely rather than being treated as an unparseable range.
- **installability-engine-range-unreadable-carries-raw-string**:
  `installability(forHostVersion:)` MUST return
  `.engineRangeUnreadable(declared)`, carrying the exact `engines["vscode"]`
  string, when that string is non-empty and does not parse as
  `VSCodeEngineRange`.
- **installability-engine-incompatible-carries-parsed-range**:
  `installability(forHostVersion:)` MUST return `.engineIncompatible(range)`,
  carrying the parsed `VSCodeEngineRange`, when the range parses but
  `range.accepts(host)` is `false`.
- **installability-default-is-installable**:
  `installability(forHostVersion:)` MUST return `.installable` when the
  platform check, the download-existence check, and the engine check (when
  applicable) all pass.
- **installability-is-pure-and-synchronous**:
  `installability(forHostVersion:)` MUST compute its result solely from
  `self`'s already-decoded fields and the `host` argument, MUST return
  synchronously, and MUST NOT perform file, network, or process access.
- **is-installable-reflects-only-the-installable-case**:
  `OpenVSXInstallability.isInstallable` MUST return `true` if and only if the
  value equals `.installable`, and MUST return `false` for every other case.
- **installability-refusal-cases-are-named-not-freeform**:
  `OpenVSXInstallability` MUST expose one distinct case per refusal reason
  (`engineIncompatible`, `engineRangeUnreadable`, `platformSpecific`,
  `noUniversalBuild`) rather than a `Bool` paired with a freeform message, so
  a caller can distinguish and separately present each reason without
  parsing prose.
- **catalog-types-are-sendable-value-types**: `OpenVSXSearchEntry`,
  `OpenVSXSearchPage`, `OpenVSXExtensionDetail`, and `OpenVSXInstallability`
  MUST each be declared `Sendable` and `Equatable` value types with no
  `actor` or `@MainActor` isolation, and decoding MUST be a synchronous,
  side-effect-free function of the `Decoder` handed to it, so a decoded
  value MAY be passed freely across concurrency domains and MAY be decoded
  concurrently by independent callers with no external coordination.

## Appearance

Not applicable — this is a decode-only model of Open VSX registry responses,
not a visual component.

## States

Not applicable — this is a decode-only model of Open VSX registry responses,
not a visual component.

## Accessibility

Not applicable — this is a decode-only model of Open VSX registry responses,
not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| open-vsx-catalog-001 | url-shaped-fields-decoded-as-string, search-entry-icon-url-resolves-independently | A search page with two entries, the second's `files.icon` set to the unparseable string `http://[bad` | Page decodes; `extensions.count == 2`; first entry's `iconURL` resolves; second entry's `iconURL == nil` and `identifier == "acme.broken"` (`searchPageSurvivesAMalformedURL`) |
| open-vsx-catalog-002 | search-entry-identifier-case-folded, extension-detail-identifier-case-folded | `namespace: "Dracula-Theme"`, `name: "Theme-Dracula"` decoded as both `OpenVSXSearchEntry` and `OpenVSXExtensionDetail` | Both produce `identifier == "dracula-theme.theme-dracula"` (`identifierIsCaseFolded`) |
| open-vsx-catalog-003 | url-shaped-fields-decoded-as-string | `{ "namespace": "acme", "name": "none", "version": "1.0.0" }` (no `files` key) vs. the same with `"files": {}` | First: `files == nil`, `sha256URL == nil`, `signatureURL == nil`, `publicKeyURL == nil`, `licenseTextURL == nil`; second: `files == [:]` (`absentFilesIsNotEmpty`) |
| open-vsx-catalog-004 | file-urls-resolve-per-named-key | `files` populated with `download`, `sha256`, `signature`, `publicKey`, `license`, `readme`, and `icon` keys | Each of `sha256URL`, `signatureURL`, `publicKeyURL`, `licenseTextURL`, `readmeURL`, `iconURL` resolves to the matching filename (`artifactURLsResolve`) |
| open-vsx-catalog-005 | web-extension-kind-is-advisory-only, engine-range-nil-when-absent-or-unparseable | `engines.vscode: "^1.74.0"`, `extensionKind: ["ui", "web"]` vs. `extensionKind: ["workspace"]` | First: `engineRange?.accepts(host) == true`, `declaresWebExtensionKind == true`; second: `declaresWebExtensionKind == false` (`declarationsAreReadAsWritten`) |
| open-vsx-catalog-006 | semantic-version-nil-on-non-semver | `version: "not-a-version"` decoded as `OpenVSXExtensionDetail` | `semanticVersion == nil` (derived from `SemanticVersion.init?`, `OpenVSXCatalog.swift`) |
| open-vsx-catalog-007 | search-page-total-size-is-whole-result-set | `{ "offset": 20, "totalSize": 137, "extensions": [] }` | `totalSize == 137` while `extensions.count == 0`, demonstrating `totalSize` names the whole result set, not this page (`OpenVSXCatalog.swift`) |
| open-vsx-catalog-008 | search-page-array-decode-is-all-or-nothing | `{ "offset": 0, "totalSize": 1, "extensions": [{ "name": "x", "version": "1.0.0" }] }` (entry missing `namespace`) | Decoding `OpenVSXSearchPage` throws; no entries are recovered (derived from `Decodable`'s synthesized array decode semantics, `OpenVSXCatalog.swift`) |
| open-vsx-catalog-009 | universal-download-is-the-only-download-url-exposed | `downloads: { "darwin-arm64": "https://open-vsx.org/w-arm64.vsix" }` (no `universal` key) | `universalDownloadURL == nil`, even though `downloads` is non-empty (`OpenVSXCatalog.swift`; `noUniversalBuild`) |
| open-vsx-catalog-010 | installability-default-is-installable, is-installable-reflects-only-the-installable-case | A detail with a universal download and `engines.vscode: "^1.74.0"`, checked against host `1.138.0` | `installability(forHostVersion:) == .installable`; `.isInstallable == true` (`installableCase`) |
| open-vsx-catalog-011 | installability-engine-incompatible-carries-parsed-range, is-installable-reflects-only-the-installable-case | `engines.vscode: "^1.200.0"`, host `1.138.0` | `.engineIncompatible(range)` where `!range.accepts(host)` and `range.accepts(1.200.0)`; `.isInstallable == false` (`engineIncompatible`) |
| open-vsx-catalog-012 | installability-engine-range-unreadable-carries-raw-string | `engines.vscode: ">= 1.74.0"` (interior whitespace), host `1.138.0` | `.engineRangeUnreadable(">= 1.74.0")` (`engineRangeUnreadable`) |
| open-vsx-catalog-013 | installability-engine-gate-skipped-when-absent-or-empty | `engines.vscode: ""` vs. `engines` key entirely absent, both with a universal download, host `1.138.0` | Both yield `.installable` (`emptyEngineIsUngated`) |
| open-vsx-catalog-014 | installability-checks-platform-before-download-existence | `targetPlatform: "darwin-arm64"`, `engines.vscode: "^1.74.0"`, host `1.138.0` | `.platformSpecific("darwin-arm64")`, not an engine-related verdict, even though the engine range would also fail (`platformSpecificRefusesFirst`) |
| open-vsx-catalog-015 | installability-checks-platform-before-download-existence | `targetPlatform: "universal"`, universal download present | `.installable` — an explicit `"universal"` `targetPlatform` is not treated as platform-specific (`universalTargetPlatformIsFine`) |
| open-vsx-catalog-016 | installability-requires-a-universal-download | No `downloads` key at all | `.noUniversalBuild`; `universalDownloadURL == nil` (`noUniversalBuild`) |
| open-vsx-catalog-017 | catalog-types-are-sendable-value-types | Two independent `JSONDecoder().decode(OpenVSXExtensionDetail.self, from:)` calls on identical `Data` | Results compare equal via synthesized `Equatable`; both values freely `Sendable` across concurrency domains |

## Edge Cases

- **Null/empty input**: `{}` decoded as `OpenVSXSearchEntry` or as
  `OpenVSXExtensionDetail` MUST throw, because `namespace`, `name`, and
  `version` are non-optional on both types. A `files`
  key present but empty (`{}`) MUST decode to `[:]`, distinct from an absent
  `files` key, which MUST decode to `nil` (open-vsx-catalog-003).
- **Boundary values**: `engines.vscode` absent and `engines.vscode` present
  as the empty string MUST both be treated as "not gated," yielding
  `.installable` when nothing else refuses (open-vsx-catalog-013); a
  `VSCodeEngineRange` string with a leading `>= ` (a space inside the
  operator, rather than immediately before a digit) MUST instead be treated
  as unreadable, because `VSCodeEngineRange`'s own grammar rejects interior
  whitespace (open-vsx-catalog-012). `URL(string: "")` MUST resolve to `nil`
  under Foundation's own `URL` initializer, so a `downloads["universal"]`
  entry of the empty string MUST behave identically to that key being
  absent — `.noUniversalBuild`.
- **Concurrent access**: `OpenVSXSearchEntry`, `OpenVSXSearchPage`,
  `OpenVSXExtensionDetail`, and `OpenVSXInstallability` are `Sendable`,
  side-effect-free value types touching no shared mutable state; concurrent,
  independent decode or `installability(forHostVersion:)` calls MUST NOT
  require external synchronization (**catalog-types-are-sendable-value-types**).
- **Error states**: A malformed required field (`namespace`, `name`, or
  `version`, on either `OpenVSXSearchEntry` or `OpenVSXExtensionDetail`)
  MUST sink the decode of the entry and, for a page, the whole page
  (open-vsx-catalog-008) — a visible failure. A malformed *optional* field,
  or a URL-shaped string that fails to parse, MUST instead resolve silently
  to `nil` with no diagnostic value recorded anywhere in this file — there
  is no equivalent, in `OpenVSXCatalog.swift`, of the sibling
  `ExtensionManifest.DecodingFailure` record; the caller sees only an
  absence, indistinguishable from the key never having been sent (see
  Design Decisions).
- **Offline/disconnected state**: Not applicable — this file performs no
  network or file I/O of its own; every type here operates purely on the
  `Decoder`, `Data`, or already-decoded fields its caller already obtained,
  with no `URLSession`, `FileManager`, or process call anywhere in
  `OpenVSXCatalog.swift`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| JSON payload | `Data` (via a `Decoder`) | none — required | The sole decode input for `OpenVSXSearchEntry`, `OpenVSXSearchPage`, and `OpenVSXExtensionDetail`; a caller constructs its own `JSONDecoder()` and calls `.decode(_:from:)` — this file defines no custom `keyDecodingStrategy` or `userInfo`. |
| `host` | `SemanticVersion` | none — required | The caller-supplied host version `installability(forHostVersion:)` compares a declared `engines.vscode` range against. |

No environment variable, settings key, or injected dependency exists
anywhere in this file. `Self.universalTargetPlatform` (the literal string
`"universal"`) is a fixed, compile-time constant read by two properties and
one check — it is not runtime configuration a caller can vary.

## Deep Linking

Not applicable: this file defines no URL scheme, universal link, or intent
handling of any kind. Every `URL` it produces (`iconURL`, `sha256URL`,
`universalDownloadURL`, and the rest) is a registry-hosted asset or download
link parsed out of already-decoded JSON, never a link this host's own UI
navigates through a custom scheme.

## Localization

Not applicable: no user-facing string literal appears anywhere in
`OpenVSXCatalog.swift`. Every string this file defines is either a JSON
field key read from the registry's own wire format (`"icon"`, `"sha256"`,
`"signature"`, `"publicKey"`, `"license"`, `"readme"`, `"universal"`, and the
`engines`/`downloads`/`files` keys) or an enum case name used for
programmatic branching (`installable`, `engineIncompatible`,
`engineRangeUnreadable`, `platformSpecific`, `noUniversalBuild`) — none of
it is text this file itself displays.

## Accessibility Options

Not applicable: this file renders no UI and reads no Reduce Motion, Increase
Contrast, or Differentiate-Without-Color signal anywhere — those act on
whatever settings UI a caller later builds from a decoded catalog entry or
an `OpenVSXInstallability` verdict, not on this decode/decision layer.

## Feature Flags

Not applicable: no field, function, or comment in `OpenVSXCatalog.swift`
reads a feature-flag key — every leniency, strictness, and ordering choice
in `installability(forHostVersion:)` is a fixed, compile-time decision,
never a runtime flag.

## Analytics

Not applicable: no file in this component emits a client-side analytics or
telemetry event — `OpenVSXInstallability` is a decision value this file
returns to its caller, not an event it fires (see Logging).

## Privacy

Not applicable: every value this file decodes is registry-published
extension metadata — namespace, name, version, description, download
counts, ratings, declared engine/download/file URLs, and license text —
no credential, token, session identifier, or end-user PII is read, stored,
or transmitted by any type in `OpenVSXCatalog.swift`.

## Logging

Not applicable: no `print`, `os_log`, `Logger`, or `NSLog` call appears
anywhere in `OpenVSXCatalog.swift`. `OpenVSXInstallability` is structured
data this file returns to its caller rather than a log line.

## Platform Notes

- **Swift (source)**: This file targets macOS today, via the
  `AgenticToolkitCore` framework target (`project.yml`); nothing in it —
  plain `Codable`/`Sendable` structs and enums over Foundation's
  `JSONDecoder` and `URL` — depends on `AppKit`, `UIKit`, or any other
  platform framework, so the same source would decode identically if the
  target grew an iOS platform tomorrow.
- **React/Web/TypeScript**: A hand-rolled parser or a schema library such as
  `zod`/`io-ts` replaces `Codable`; URL-shaped fields are typed `string` and
  parsed lazily with the global `URL` constructor (or a `try`/`catch`
  wrapper around it) only inside the equivalent of `iconURL`/`sha256URL`,
  never eagerly at the top-level parse, to preserve the
  **url-shaped-fields-decoded-as-string** isolation; `installability` is a
  plain function returning a discriminated union
  (`{ kind: "installable" } | { kind: "engineIncompatible"; range } | ...`)
  rather than a class hierarchy.
- **Compose/Android (Kotlin)**: `kotlinx.serialization` with a `data class`
  per response shape replaces `Codable`; a `sealed interface` with
  `data class`/`data object` cases is the equivalent of
  `OpenVSXInstallability`, and `installability` becomes a plain `fun`
  returning that sealed type — a `when` expression over it, rather than a
  `Boolean`, is how a caller renders each refusal distinctly.
- **WinUI 3 (C#)**: `System.Text.Json` (`JsonSerializer`, `JsonDocument`)
  replaces `Codable`, with URL-shaped registry fields typed `string`
  properties, never `System.Uri`, and parsed on demand inside computed
  properties (`Uri.TryCreate`, never the throwing `Uri` constructor) to
  preserve the same per-accessor isolation. `installability`'s required
  fields — the equivalent of `namespace`, `name`, and `version` failing the
  whole decode — need the C# `required` keyword on those three properties
  (or a custom `JsonConverter<T>` that checks for their presence explicitly)
  because `System.Text.Json` otherwise leaves a missing non-nullable
  `string` property at its default rather than throwing, which would
  silently drop **search-page-array-decode-is-all-or-nothing**'s "throws for
  the whole page" behavior. A `SemanticVersion`-equivalent `readonly record
  struct` and a ported `VSCodeEngineRange` parser stand in for the two
  Swift helper types this file depends on; `OpenVSXInstallability` itself
  becomes a `record`-per-case discriminated union (an `abstract record` base
  with one `sealed record` per case, or a single `record` with an `enum Kind`
  discriminant plus optional payload fields) rather than an
  `ObservableCollection<T>` or `INotifyPropertyChanged` type, since nothing
  in this contract needs mutation notification — the verdict is a one-shot,
  immutable computation.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/OpenVSXCatalog.swift` |

## Design Decisions

**Decision**: `OpenVSXSearchEntry.files`, `OpenVSXExtensionDetail.downloads`,
and `OpenVSXExtensionDetail.files` decode every URL-shaped value as `String`,
never as `URL`, with each computed accessor (`iconURL`, `sha256URL`,
`universalDownloadURL`, and the rest) parsing its own key lazily.
**Rationale**: The source's own top-of-file doc comment states the reason
directly: `URL`'s `Decodable` conformance throws on a string it cannot
parse, which would mean one extension with a malformed icon URL takes down
the decode of the whole search page it appeared in. Decoding as `String`
and parsing per-accessor means a bad URL costs exactly the accessor that
reads it.
**Approved**: pending

**Decision**: That per-accessor URL isolation does not extend to
`OpenVSXSearchPage.extensions` as a whole — a search entry missing a
required field still sinks the entire page's decode, with no per-element
recovery of the kind `ExtensionManifest`'s `LenientDecoding` implements for
`contributes.*` collections.
**Rationale**: The source's stated protection is scoped to URL-shaped
fields specifically, via computed accessors; the array itself is decoded
through `Decodable`'s ordinary synthesis with no custom `init(from:)`
anywhere in `OpenVSXSearchEntry` or `OpenVSXSearchPage`. This is a real,
narrower guarantee than a reader might infer from the doc comment's framing
around "one row's bad icon URL does not take the page with it" — that
sentence is true only for the icon URL and its siblings, not for a
structurally malformed entry.
**Approved**: pending

**Decision**: `installability(forHostVersion:)` checks `targetPlatform`
before checking whether a universal download exists, and checks download
existence before the engine-range gate.
**Rationale**: The source's own doc comment states the check runs "before
the download rather than after, because every refusal here is knowable from
metadata alone and a user who is going to be told 'no' should be told before
several megabytes cross the network." `OpenVSXCatalogTests`'
`platformSpecificRefusesFirst` pins the platform-first ordering explicitly,
noting a platform-specific build "refuses before the engine is even read" —
this is a tested contract, not incidental code order.
**Approved**: pending

**Decision**: `OpenVSXInstallability` is a `Sendable`, `Equatable` enum with
one named case per refusal reason, rather than a `Bool` paired with a
freeform message string.
**Rationale**: The source's own doc comment names the reason: a settings UI
"has to say which wall an extension hit" — "needs VS Code 1.140" and "ships
a macOS binary" are different situations with different answers — and a
reason assembled as prose at the point of refusal "cannot be tested or
localized." The comment names this explicit-over-implicit.
**Approved**: pending

**Decision**: `OpenVSXExtensionDetail.engineRange` collapses "no
`engines.vscode` key" and "an `engines.vscode` value that fails to parse"
into the same `nil`, even though `installability(forHostVersion:)` treats
those two situations differently (ungated vs. `.engineRangeUnreadable`).
**Rationale**: The property's own doc comment states plainly that "an
extension with no `engines.vscode` is not gated — see
`installability(forHostVersion:)`," pointing the reader at the one place
that does draw the distinction. `engineRange` is a convenience accessor for
callers that only need the parsed range when one exists; the
absent-vs-unreadable distinction is deliberately implemented once, inside
`installability(forHostVersion:)`, rather than duplicated at this property.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | partial | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | passed | Internationalization |

`explicit-error-handling` is **partial**: a malformed required field sinks
the whole entry (and, for a page, the whole page) with a visible thrown
error, but a malformed optional or URL-shaped field resolves silently to
`nil` with no diagnostic recorded anywhere in this file — unlike the
sibling `ExtensionManifest.DecodingFailure` mechanism, there is no record a
caller can inspect to learn that a specific field failed to parse.
`fault-tolerance` is **partial** for the same reason from the other
direction: per-field URL isolation exists, but no per-array-element
isolation exists for `OpenVSXSearchPage.extensions` (see Design Decisions).
`data-integrity` **passed**: every field this file decodes is carried
through unmodified (the URL-as-`String` choice is a type projection a
computed accessor reverses on demand, not a data loss), and none of these
types declares `Encodable`, so there is no lossy round-trip to assess.
`idempotent-operations` **passed**: decoding and `installability(forHostVersion:)`
are both pure functions of their inputs; two decodes of byte-identical JSON
produce `Equatable`-equal values (open-vsx-catalog-017).
`separation-of-concerns` **passed**: this file only models and evaluates
registry metadata — it performs no network request, no file I/O, and no
installation step, all of which live in `OpenVSXClient.swift` and
`VSIXInstaller.swift` outside this recipe's scope. `unit-test-coverage`
**passed**: `OpenVSXCatalogTests.swift` exercises decode robustness for
every URL-shaped field, absent-vs-empty `files`, case-folded identifiers,
and every branch of `installability(forHostVersion:)`, including its
check ordering. `input-sanitization` **passed**: every value parsed from
untrusted registry text (`URL.init(string:)`, `SemanticVersion.init?`,
`VSCodeEngineRange.init?`) is parsed defensively and yields `nil` on
failure rather than crashing or trusting the input. `no-hardcoded-strings`
**passed**: this file defines no user-facing display string to flag (see
Localization) — every string literal in it is a JSON protocol key or a
programmatic case name.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
