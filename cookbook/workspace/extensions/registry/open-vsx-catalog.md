---
id: 1bbc9593-4064-4e79-8bce-08b3cf00c13d
title: Open VSX Catalog
domain: agentictoolkit://cookbook/workspace/extensions/registry/open-vsx-catalog
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Decoded models of Open VSX search and detail responses, with URL-shaped fields
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

# Open VSX Catalog

## Overview

The catalog is the decoded model of what the Open VSX registry's HTTP API
returns: one summary row from `GET /api/-/search` (a search entry), one page
of that search (a search page), and the full record for one version of one
extension from `GET /api/<namespace>/<name>` or `.../<version>` (an
extension detail). It has no visual surface, performs no network request
itself, and is not the code that fetches these responses — that is the
registry client, out of this recipe's scope. Its defining discipline is that
every URL-shaped registry field decodes as a plain string, never as a parsed
URL, so that one entry with a malformed icon link never sinks the decode of
the page it appeared on; computed accessors parse each URL lazily, where it
is used, so a bad string costs exactly the accessor that reads it. The
catalog's second job is the installability verdict: a pure function from
already-decoded metadata to a named verdict — whether a given registry
version could be installed into this host at all, decided before any bytes
are downloaded.

## Behavioral Requirements

- **url-shaped-fields-decoded-as-string**: A search entry's `files`, and an
  extension detail's `downloads` and `files`, MUST decode as an optional
  string-to-string mapping, never as a mapping of parsed URLs, so a value
  that cannot parse as a URL costs only the computed accessor that reads it
  and never the decode of the entry or the page containing it.
- **search-entry-identifier-case-folded**: A search entry's identifier MUST
  return its namespace and name joined by a `.` and lowercased.
- **search-entry-icon-url-resolves-independently**: A search entry's icon
  URL MUST return the parsed URL when its `files["icon"]` value is present
  and parseable, and MUST return nothing, never fail, when the key is absent
  or the string is unparseable.
- **search-page-total-size-is-whole-result-set**: A search page's total
  size MUST report the size of the entire result set the query matched, not
  the number of elements in that page's extension list, so a caller can
  decide whether to request another offset.
- **search-page-array-decode-is-all-or-nothing**: A search page's extension
  list MUST decode as a single unit that fails for the whole page when any
  one element is missing a required field (namespace, name, or version) or
  gives it the wrong type — this concept implements no per-element recovery
  the way it does for a single URL-shaped field (contrast with
  **url-shaped-fields-decoded-as-string**).
- **extension-detail-identifier-case-folded**: An extension detail's
  identifier MUST return its namespace and name joined by a `.` and
  lowercased, and, for the same namespace and name, MUST equal the search
  entry's identifier, so a search row and a detail record for the same
  extension join without either side re-deriving the case-folding rule (see
  **search-entry-identifier-case-folded**).
- **license-field-carries-absence**: An extension detail's license MUST
  decode to nothing when the `license` key is absent, and MUST preserve
  whatever string the registry sent verbatim — including an empty string —
  when the key is present, with no normalization between the two.
- **semantic-version-nil-on-non-semver**: An extension detail's parsed
  semantic version MUST return nothing, never fail or substitute a default,
  when its `version` field does not parse as a semantic version.
- **engine-range-nil-when-absent-or-unparseable**: An extension detail's
  engine range MUST return nothing both when `engines` is absent or has no
  `vscode` key, and when the `vscode` value is present but does not parse as
  an engine range, drawing no distinction between those two cases at this
  property; the distinction between "not gated" and "unreadable" is drawn
  only by the installability verdict.
- **universal-download-is-the-only-download-url-exposed**: An extension
  detail's universal download URL MUST return the parsed URL for
  `downloads["universal"]` only, and MUST return nothing when that key is
  absent, even when `downloads` holds one or more other platform-keyed
  entries.
- **file-urls-resolve-per-named-key**: The digest, signature, public-key,
  license-text, readme, and icon URLs on an extension detail MUST each
  resolve independently through a shared file-URL lookup reading `files[key]`,
  and MUST each return nothing on its own — with no effect on any other
  accessor — when its own key is absent or its value is unparseable.
- **web-extension-kind-is-advisory-only**: Whether an extension declares the
  web extension kind MUST report whether the registry's `extensionKind`
  array contains the string `"web"`, and the installability verdict MUST NOT
  read `extensionKind` or this flag at all when computing its verdict.
- **installability-checks-platform-before-download-existence**: The
  installability verdict MUST return "platform-specific" (naming the
  platform) when `targetPlatform` is present and not equal to the literal
  string `"universal"`, and MUST perform this check before checking whether
  a universal download exists.
- **installability-requires-a-universal-download**: The installability
  verdict MUST return "no universal build" when the universal download URL
  is absent, checked after the platform check and before any engine check.
- **installability-engine-gate-skipped-when-absent-or-empty**: The
  installability verdict MUST treat an absent `engines["vscode"]` and an
  empty-string `engines["vscode"]` identically: both MUST skip the engine
  check entirely rather than being treated as an unparseable range.
- **installability-engine-range-unreadable-carries-raw-string**: The
  installability verdict MUST return "engine range unreadable," carrying the
  exact `engines["vscode"]` string, when that string is non-empty and does
  not parse as an engine range.
- **installability-engine-incompatible-carries-parsed-range**: The
  installability verdict MUST return "engine incompatible," carrying the
  parsed engine range, when the range parses but does not accept the host
  version.
- **installability-default-is-installable**: The installability verdict
  MUST return "installable" when the platform check, the download-existence
  check, and the engine check (when applicable) all pass.
- **installability-is-pure-and-synchronous**: The installability verdict
  MUST compute its result solely from the extension detail's already-decoded
  fields and the supplied host version, MUST return synchronously, and MUST
  NOT perform file, network, or process access.
- **is-installable-reflects-only-the-installable-case**: The "is
  installable" flag derived from the verdict MUST return true if and only if
  the verdict is "installable," and MUST return false for every other case.
- **installability-refusal-cases-are-named-not-freeform**: The
  installability verdict MUST expose one distinct case per refusal reason
  (engine incompatible, engine range unreadable, platform-specific, no
  universal build) rather than a flag paired with a freeform message, so a
  caller can distinguish and separately present each reason without parsing
  prose.
- **catalog-types-are-safe-for-concurrent-use**: The search entry, search
  page, extension detail, and installability verdict MUST each be a
  concurrency-safe value that supports equality comparison, with no
  confinement to a single execution context, and decoding MUST be a
  synchronous, side-effect-free function of the input handed to it, so a
  decoded value MAY be passed freely across concurrent contexts and MAY be
  decoded concurrently by independent callers with no external coordination.

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
| open-vsx-catalog-001 | url-shaped-fields-decoded-as-string, search-entry-icon-url-resolves-independently | A search page with two entries, the second's `files.icon` set to the unparseable string `http://[bad` | Page decodes; the extension count is 2; the first entry's icon URL resolves; the second entry's icon URL is absent and its identifier is `"acme.broken"` |
| open-vsx-catalog-002 | search-entry-identifier-case-folded, extension-detail-identifier-case-folded | `namespace: "Dracula-Theme"`, `name: "Theme-Dracula"` decoded as both a search entry and an extension detail | Both produce identifier `"dracula-theme.theme-dracula"` |
| open-vsx-catalog-003 | url-shaped-fields-decoded-as-string | `{ "namespace": "acme", "name": "none", "version": "1.0.0" }` (no `files` key) vs. the same with `"files": {}` | First: `files` is absent, and the digest, signature, public-key, and license-text URLs are all absent; second: `files` is an empty mapping |
| open-vsx-catalog-004 | file-urls-resolve-per-named-key | `files` populated with `download`, `sha256`, `signature`, `publicKey`, `license`, `readme`, and `icon` keys | Each of the digest, signature, public-key, license-text, readme, and icon URLs resolves to the matching filename |
| open-vsx-catalog-005 | web-extension-kind-is-advisory-only, engine-range-nil-when-absent-or-unparseable | `engines.vscode: "^1.74.0"`, `extensionKind: ["ui", "web"]` vs. `extensionKind: ["workspace"]` | First: the engine range accepts the host and the web-extension-kind flag is true; second: the flag is false |
| open-vsx-catalog-006 | semantic-version-nil-on-non-semver | `version: "not-a-version"` decoded as an extension detail | The parsed semantic version is absent |
| open-vsx-catalog-007 | search-page-total-size-is-whole-result-set | `{ "offset": 20, "totalSize": 137, "extensions": [] }` | Total size is 137 while the extension list has 0 elements, demonstrating total size names the whole result set, not this page |
| open-vsx-catalog-008 | search-page-array-decode-is-all-or-nothing | `{ "offset": 0, "totalSize": 1, "extensions": [{ "name": "x", "version": "1.0.0" }] }` (entry missing `namespace`) | Decoding the page fails entirely; no entries are recovered |
| open-vsx-catalog-009 | universal-download-is-the-only-download-url-exposed | `downloads: { "darwin-arm64": "https://open-vsx.org/w-arm64.vsix" }` (no `universal` key) | The universal download URL is absent, even though `downloads` is non-empty ("no universal build") |
| open-vsx-catalog-010 | installability-default-is-installable, is-installable-reflects-only-the-installable-case | A detail with a universal download and `engines.vscode: "^1.74.0"`, checked against host `1.138.0` | The installability verdict is "installable"; the is-installable flag is true |
| open-vsx-catalog-011 | installability-engine-incompatible-carries-parsed-range, is-installable-reflects-only-the-installable-case | `engines.vscode: "^1.200.0"`, host `1.138.0` | "engine incompatible," carrying a range that rejects `1.138.0` and accepts `1.200.0`; the is-installable flag is false |
| open-vsx-catalog-012 | installability-engine-range-unreadable-carries-raw-string | `engines.vscode: ">= 1.74.0"` (interior whitespace), host `1.138.0` | "engine range unreadable," carrying `">= 1.74.0"` |
| open-vsx-catalog-013 | installability-engine-gate-skipped-when-absent-or-empty | `engines.vscode: ""` vs. `engines` key entirely absent, both with a universal download, host `1.138.0` | Both yield "installable" |
| open-vsx-catalog-014 | installability-checks-platform-before-download-existence | `targetPlatform: "darwin-arm64"`, `engines.vscode: "^1.74.0"`, host `1.138.0` | "platform-specific," naming `"darwin-arm64"` — not an engine-related verdict, even though the engine range would also fail |
| open-vsx-catalog-015 | installability-checks-platform-before-download-existence | `targetPlatform: "universal"`, universal download present | "installable" — an explicit `"universal"` `targetPlatform` is not treated as platform-specific |
| open-vsx-catalog-016 | installability-requires-a-universal-download | No `downloads` key at all | "no universal build"; the universal download URL is absent |
| open-vsx-catalog-017 | catalog-types-are-safe-for-concurrent-use | Two independent decodes of identical bytes, run concurrently | Results compare equal; both values are freely safe to share across concurrent contexts |

## Edge Cases

- **Null/empty input**: `{}` decoded as a search entry or as an extension
  detail MUST fail, because namespace, name, and version are required on
  both types. A `files` key present but empty (`{}`) MUST decode to an empty
  mapping, distinct from an absent `files` key, which MUST decode to nothing
  (open-vsx-catalog-003).
- **Boundary values**: `engines.vscode` absent and `engines.vscode` present
  as the empty string MUST both be treated as "not gated," yielding
  "installable" when nothing else refuses (open-vsx-catalog-013); an engine
  range string with a leading `>= ` (a space inside the operator, rather
  than immediately before a digit) MUST instead be treated as unreadable,
  because the engine-range grammar rejects interior whitespace
  (open-vsx-catalog-012). Parsing the empty string as a URL MUST resolve to
  nothing, so a `downloads["universal"]` entry of the empty string MUST
  behave identically to that key being absent — "no universal build."
- **Concurrent access**: the search entry, search page, extension detail,
  and installability verdict are concurrency-safe, side-effect-free values
  touching no shared mutable state; concurrent, independent decode or
  installability calls MUST NOT require external synchronization
  (**catalog-types-are-safe-for-concurrent-use**).
- **Error states**: A malformed required field (namespace, name, or
  version, on either a search entry or an extension detail) MUST sink the
  decode of the entry and, for a page, the whole page
  (open-vsx-catalog-008) — a visible failure. A malformed *optional* field,
  or a URL-shaped string that fails to parse, MUST instead resolve silently
  to nothing with no diagnostic value recorded anywhere in this concept —
  there is no equivalent, in this catalog, of the sibling manifest's
  decoding-failure record; the caller sees only an absence, indistinguishable
  from the key never having been sent (see Design Decisions).
- **Offline/disconnected state**: Not applicable — this concept performs no
  network or file I/O of its own; every type here operates purely on
  already-decoded fields or the input its caller already obtained, with no
  network, file-system, or process call anywhere in the catalog.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| JSON payload | bytes decoded via the catalog's decoder | none — required | The sole decode input for a search entry, a search page, and an extension detail; a caller constructs its own decoder and decodes into these types — this concept defines no custom key-decoding strategy or side channel. |
| host | a semantic version | none — required | The caller-supplied host version the installability verdict compares a declared `engines.vscode` range against. |

No environment variable, settings key, or injected dependency exists
anywhere in this concept. The literal string `"universal"` is a fixed,
compile-time constant read by two properties and one check — it is not
runtime configuration a caller can vary.

## Deep Linking

Not applicable: this concept defines no URL scheme, universal link, or
intent handling of any kind. Every URL it produces (icon, digest, universal
download, and the rest) is a registry-hosted asset or download link parsed
out of already-decoded JSON, never a link this host's own UI navigates
through a custom scheme.

## Localization

Not applicable: no user-facing string literal appears anywhere in this
concept. Every string it defines is either a JSON field key read from the
registry's own wire format (`"icon"`, `"sha256"`, `"signature"`,
`"publicKey"`, `"license"`, `"readme"`, `"universal"`, and the
`engines`/`downloads`/`files` keys) or a case name used for programmatic
branching (installable, engine-incompatible, engine-range-unreadable,
platform-specific, no-universal-build) — none of it is text this concept
itself displays.

## Accessibility Options

Not applicable: this concept renders no UI and reads no Reduce Motion,
Increase Contrast, or Differentiate-Without-Color signal anywhere — those
act on whatever settings UI a caller later builds from a decoded catalog
entry or an installability verdict, not on this decode/decision layer.

## Feature Flags

Not applicable: no field, function, or comment in this concept reads a
feature-flag key — every leniency, strictness, and ordering choice in the
installability verdict is a fixed, compile-time decision, never a runtime
flag.

## Analytics

Not applicable: no part of this component emits a client-side analytics or
telemetry event — the installability verdict is a decision value this
concept returns to its caller, not an event it fires (see Logging).

## Privacy

Not applicable: every value this concept decodes is registry-published
extension metadata — namespace, name, version, description, download
counts, ratings, declared engine/download/file URLs, and license text —
no credential, token, session identifier, or end-user PII is read, stored,
or transmitted by any part of this catalog.

## Logging

Not applicable: no logging call of any kind appears anywhere in this
concept. The installability verdict is structured data this concept returns
to its caller rather than a log line.

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

**Decision**: URL-shaped fields decode every URL-shaped value as a plain
string, never as a parsed URL, with each computed accessor (icon, digest,
universal download, and the rest) parsing its own key lazily.
**Rationale**: The source's own top-of-file doc comment states the reason
directly: a parsed-URL type's decoding conformance throws on a string it
cannot parse, which would mean one extension with a malformed icon URL
takes down the decode of the whole search page it appeared in. Decoding as
a string and parsing per-accessor means a bad URL costs exactly the
accessor that reads it.
**Approved**: pending

**Decision**: That per-accessor URL isolation does not extend to the search
page's extension list as a whole — a search entry missing a required field
still sinks the entire page's decode, with no per-element recovery of the
kind the extension manifest's lenient decoding implements for its
contribution collections.
**Rationale**: The source's stated protection is scoped to URL-shaped
fields specifically, via computed accessors; the array itself is decoded
through the platform's ordinary synthesized decoding with no custom decode
logic anywhere in the search entry or search page types (Swift/AppKit
implementation). This is a real, narrower guarantee than a reader might
infer from the doc comment's framing around "one row's bad icon URL does
not take the page with it" — that sentence is true only for the icon URL
and its siblings, not for a structurally malformed entry.
**Approved**: pending

**Decision**: The installability verdict checks `targetPlatform` before
checking whether a universal download exists, and checks download existence
before the engine-range gate.
**Rationale**: The source's own doc comment states the check runs "before
the download rather than after, because every refusal here is knowable from
metadata alone and a user who is going to be told 'no' should be told before
several megabytes cross the network." The reference test suite's
platform-first-ordering test pins the platform-first ordering explicitly,
noting a platform-specific build "refuses before the engine is even read" —
this is a tested contract, not incidental code order.
**Approved**: pending

**Decision**: The installability verdict is a concurrency-safe,
equality-comparable value with one named case per refusal reason, rather
than a flag paired with a freeform message string.
**Rationale**: The source's own doc comment names the reason: a settings UI
"has to say which wall an extension hit" — "needs VS Code 1.140" and "ships
a macOS binary" are different situations with different answers — and a
reason assembled as prose at the point of refusal "cannot be tested or
localized." The comment names this explicit-over-implicit.
**Approved**: pending

**Decision**: An extension detail's engine range collapses "no
`engines.vscode` key" and "an `engines.vscode` value that fails to parse"
into the same absent result, even though the installability verdict treats
those two situations differently (ungated vs. "engine range unreadable").
**Rationale**: The property's own doc comment states plainly that "an
extension with no `engines.vscode` is not gated — see the installability
verdict," pointing the reader at the one place that does draw the
distinction. The engine-range accessor is a convenience for callers that
only need the parsed range when one exists; the absent-vs-unreadable
distinction is deliberately implemented once, inside the installability
verdict, rather than duplicated at this property.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/registry/. |
