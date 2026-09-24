---
id: bc4c4fe9-aa33-47a7-94d2-fb688e70caec
title: OpenVSXClient
domain: agentictoolkit://recipes/extension-host-core-extensions-open-vsx-client
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "Read-only, stateless Sendable client for the Open VSX registry: paged
  search, per-version detail, and bounded artifact/text downloads."
platforms:
- swift
- macos
tags:
- extension-host
- open-vsx
- networking
- registry-client
depends-on: []
related:
- agentictoolkit://recipes/extension-host-core-extensions-extension-identity-component
references:
- packages/apple/AgenticToolkit/Core/Extensions/OpenVSXClient.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Networking/BoundedBodyLoader.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionIdentityComponent.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/OpenVSXCatalog.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# OpenVSXClient

## Overview

`OpenVSXClient` is a stateless, `Sendable` `struct` that reads the Open VSX
extension registry over HTTPS: one page of catalog search results, the full
metadata record for one extension version, and the raw bytes or trimmed text
of a registry-named artifact (a `.vsix`, its detached `.sigzip` signature
archive, its `.sha256` digest, or its public key). It is read-only by
construction — there is no publish, review, or account surface on this type,
and nothing it sends to the registry beyond the request itself could be
attributed to a user (source: doc comment on `OpenVSXClient`).
It holds no cache: every call re-fetches from the registry, because a
memoizing client would hand an update check a stale "latest version" when
being current is the whole point of the check (doc comment).

Callers reach it to browse and vet an extension before installing it — the
doc comment on `detail` names `ExtensionUpdateCheck`, which feeds a
sideloaded extension's manifest `publisher` field in as `namespace`, and the
doc comment on the private `requireSafeComponent` helper names `VSIXInstaller`
as the sibling caller that applies the same identity guard to the same kind
of manifest field before building an install directory name. `OpenVSXClient` itself never touches the filesystem and
never installs anything; it only hands back registry-published bytes and
metadata, safely, to whichever caller does.

All line references below are to
`packages/apple/AgenticToolkit/Core/Extensions/OpenVSXClient.swift` unless
another file is named.

## Behavioral Requirements

- **default-registry**: `OpenVSXClient.openVSXRegistry` MUST equal
  `https://open-vsx.org/api`, and `init`'s `registryBase` parameter MUST
  default to it when the caller supplies none.
- **self-hosted-registry-override**: A caller MAY supply a `registryBase`
  other than the default, addressing a self-hosted Open VSX-compatible
  registry that serves the same API shape at a different host (doc comment; `init`).
- **default-page-size**: `OpenVSXClient.defaultPageSize` MUST equal `50`, and
  `search`'s `size` parameter MUST default to it.
- **default-artifact-ceiling**: `OpenVSXClient.defaultMaximumArtifactBytes`
  MUST equal `536,870,912` (`512 * 1024 * 1024`) bytes, and `init`'s
  `maximumArtifactBytes` parameter MUST default to it.
- **default-metadata-ceiling**: `OpenVSXClient.defaultMaximumMetadataBytes`
  MUST equal `8,388,608` (`8 * 1024 * 1024`) bytes, and `init`'s
  `maximumMetadataBytes` parameter MUST default to it.
- **stateless-value-type**: `OpenVSXClient` MUST be declared as a `Sendable`
  `struct` holding only `registryBase`, `loader`, `maximumArtifactBytes`, and
  `maximumMetadataBytes`, all assigned once in `init` and never mutated
  afterward; no result of `search`, `detail`, `data`, or `text` MUST be
  cached or memoized by this type.
- **session-configuration-reuse**: `init` MUST construct its internal
  `BoundedBodyLoader` from `session.configuration` rather than from `session`
  itself, so that an injected `URLSessionConfiguration.protocolClasses` (the
  mechanism every test in this component stands the registry up with) still
  applies to requests this client makes.
- **search-default-query**: `search`'s `query` parameter MUST default to the
  empty string, and an empty or all-whitespace query MUST be treated as the
  browse case, not an error — the request MUST be sent with the whole
  catalog implied rather than refused (doc comment).
- **search-query-trimmed**: `search` MUST trim `query` of leading and
  trailing whitespace and newline characters with
  `trimmingCharacters(in: .whitespacesAndNewlines)` before deciding whether
  to send it, and MUST send the trimmed value, never the original, as the
  `query` URL query item (test `queryIsTrimmed`).
- **search-query-omitted-when-blank**: `search` MUST omit the `query` URL
  query item entirely when the trimmed query is empty, rather than sending an
  empty `query=` parameter (test `emptyQueryOmitsTheItem`).
- **search-pagination-params**: `search` MUST send `size`, `offset`,
  `sortBy`, and a fixed `sortOrder` of `"desc"` as URL query items on every
  call, using the caller-supplied `offset` and `size` verbatim and
  `sortBy.rawValue` for `sortBy` (test `searchSendsTheQuery`).
- **search-single-row-per-extension**: `search` MUST send
  `includeAllVersions=false` as a fixed URL query item on every call, so the
  result contains one row per extension rather than one row per published
  version of a single extension (test `searchSendsTheQuery`).
- **search-sort-order**: `search`'s `sortBy` parameter MUST default to
  `SortOrder.downloadCount` and MUST accept `.relevance`, `.rating`, or
  `.timestamp` as alternatives, each sent as the `String` raw value declared
  on `SortOrder`.
- **search-malformed-registry-url**: `search` MUST throw
  `OpenVSXError.malformedRegistryURL(registryBase)`, without making a
  request, when `URLComponents` cannot compose a request URL from
  `registryBase` and the assembled query items.
- **search-result-shape**: On success, `search` MUST decode and return an
  `OpenVSXSearchPage` carrying `offset`, `totalSize`, and the `extensions`
  array of `OpenVSXSearchEntry` rows (`OpenVSXCatalog.swift`; test `searchDecodes`).
- **detail-latest-by-default**: `detail(namespace:name:version:)` MUST
  address the latest published version of the extension when `version` is
  `nil`, and MUST address exactly the named version, appended as an
  additional path component, when `version` is non-`nil` (test `detailAddressesTheVersion`).
- **detail-identity-validated**: `detail` MUST validate `namespace`, `name`,
  and (when present) `version` with `requireSafeComponent` before composing
  the request URL, and MUST throw `OpenVSXError.unsafeIdentity(field:value:)`
  without making a request when any of the three is unsafe by
  `ExtensionIdentityComponent.isSafe`'s rule (278–282; tests
  `detailRefusesATraversingNamespace`, `detailRefusesATraversingNameAndVersion`).
- **detail-result-shape**: On success, `detail` MUST decode and return an
  `OpenVSXExtensionDetail` for the addressed namespace, name, and version
  (test `detailAcceptsOrdinaryNames`).
- **artifact-scheme-and-host-required**: `data(at:)` MUST throw
  `OpenVSXError.artifactNotFetchable(url:scheme:)`, without making a request,
  when `url`'s scheme — compared case-insensitively — is not `"https"`, or
  when `url` has no non-empty host (284–289; tests
  `fileArtifactURLIsRefused`, `plainHTTPArtifactURLIsRefused`,
  `aDataURLIsRefused`, `aHostlessURLIsRefused`,
  `anUppercaseFileSchemeIsRefused`).
- **artifact-scheme-check-is-case-insensitive**: The scheme comparison in
  `requireFetchable` MUST lowercase `url.scheme` before testing membership in
  `fetchableSchemes`, so an uppercase `HTTPS:` URL MUST be fetched and an
  uppercase `FILE:` URL MUST still be refused (tests
  `anUppercaseHTTPSSchemeIsFetched`, `anUppercaseFileSchemeIsRefused`).
- **artifact-host-scheme-not-pinned**: `requireFetchable` MUST check only the
  URL scheme and the presence of a host, never the host's identity — an
  `https` artifact URL on a host other than `registryBase`'s host MUST still
  be fetched, since a self-hosted registry commonly serves artifacts from a
  separate CDN host (doc comment; test
  `httpsArtifactOnAnotherHostIsFetched`).
- **artifact-bounded-read**: `data(at:)` MUST read the response body only up
  to `maximumArtifactBytes` and MUST throw
  `OpenVSXError.artifactTooLarge(url:limit:)` once that ceiling is passed,
  whether the excess is detected from a `Content-Length` the response
  declared before any byte is read, or from the running byte count as chunks
  arrive — an understated `Content-Length` MUST NOT allow an oversized body
  past the ceiling (`BoundedBodyLoader.swift`; tests `dataRefusesAnOversizeArtifact`,
  `aClaimedLengthPastTheCapIsRefused`, `anUnderstatedLengthIsNotBelieved`,
  `aBodyOfExactlyTheCapIsAccepted`, `aBodyOneByteOverTheCapIsRefused`).
- **status-outranks-size-ceiling**: When a response both fails the HTTP
  status check and exceeds its ceiling, `body` MUST report the HTTP status
  failure (`OpenVSXError.requestFailed`), never the size failure — the status
  is checked on the failure response before the too-large error is thrown,
  for both the artifact ceiling and the metadata ceiling (tests `anErrorStatusOutranksTheCeiling`, `aMissingArtifactIsReportedAsMissing`).
- **artifact-non-http-response-refused**: `data(at:)` MUST throw
  `OpenVSXError.responseNotHTTP(url)` when the underlying `URLResponse` is
  not an `HTTPURLResponse`, rather than treating it as a successful read
  (test `nonHTTPResponseIsRefused`).
- **artifact-status-range**: `data(at:)` MUST throw
  `OpenVSXError.requestFailed(url:status:)` when the HTTP status code is
  outside `200..<300` (test `artifactFailureNamesTheURL`).
- **text-trims-whitespace**: `text(at:)` MUST call `data(at:)` for the same
  `url`, decode the result as UTF-8, and return it trimmed of leading and
  trailing whitespace and newline characters with
  `trimmingCharacters(in: .whitespacesAndNewlines)` (test
  `textIsTrimmed`).
- **text-requires-utf8**: `text(at:)` MUST throw
  `OpenVSXError.artifactNotText(url)`, without altering or truncating the
  bytes, when the downloaded data cannot be decoded as UTF-8 (test `nonTextArtifactIsRefused`).
- **metadata-bounded-read**: `search` and `detail` MUST read their HTTP
  response body only up to `maximumMetadataBytes`, through the same
  `body`/`BoundedBodyLoader` mechanism `data(at:)` uses, and MUST throw
  `OpenVSXError.responseTooLarge(url:limit:)` once that ceiling is passed —
  whether by a declared `Content-Length` or by the running byte count
  (tests `anOversizeSearchAnswerIsRefused`,
  `anOversizeDetailAnswerIsRefused`, `aClaimedMetadataLengthPastTheCapIsRefused`,
  `anOrdinaryAnswerIsStillDecoded`).
- **artifact-and-metadata-ceilings-are-distinct**: `defaultMaximumArtifactBytes`
  and `defaultMaximumMetadataBytes` MUST be different values, three orders of
  magnitude apart, because a search page or a detail record is at most a few
  kilobytes while a `.vsix` may legitimately run to hundreds of megabytes
  (doc comment; test `theTwoCeilingsAreDistinct`).
- **status-checked-before-decode**: `search` and `detail` MUST check the HTTP
  status of the response and throw `OpenVSXError.requestFailed(url:status:)`
  for a non-2xx status before attempting to decode the body as JSON — a
  404's or 500's error document MUST be reported as its status, never handed
  to `JSONDecoder` (300–306; doc comment; tests
  `notFoundIsAStatusFailure`, `serverErrorIsReported`).
- **metadata-decode-failure**: `search` and `detail` MUST throw
  `OpenVSXError.undecodableResponse(url:underlying:)`, carrying the
  underlying `DecodingError` rendered with `String(describing:)`, when the
  bounded response body is empty, is valid JSON of the wrong shape, or is
  truncated mid-token (tests `undecodableResponse`,
  `anEmptyBodyIsUndecodable`, `theWrongShapeIsUndecodable`,
  `aTruncatedBodyIsUndecodable`).
- **sendable-isolation**: `OpenVSXClient` MUST be declared `Sendable` and
  MUST be usable concurrently, without additional synchronization, from any
  thread or actor, because every stored property (`registryBase`, `loader`,
  the two `Int` ceilings) is immutable after `init` and `BoundedBodyLoader`
  is itself declared `Sendable` (`BoundedBodyLoader.swift`).
- **independent-concurrent-calls**: Concurrent calls to `search`, `detail`,
  `data`, or `text` on the same `OpenVSXClient` value MUST run independently:
  each call starts its own `URLSessionDataTask`, and `BoundedBodyLoader`'s
  internal `State` keys every transfer by that task's `taskIdentifier` behind
  one lock, so one call's outcome MUST NOT depend on the order or overlap of
  any other concurrent call (`BoundedBodyLoader.swift`).
- **cancellation-stops-the-transfer**: Cancelling the `Task` that awaits
  `search`, `detail`, `data`, or `text` MUST cancel the underlying
  `URLSessionDataTask` via `withTaskCancellationHandler`'s `onCancel`, rather
  than continuing to accumulate a response body no one will read
  (`BoundedBodyLoader.swift`).
- **network-failure-propagates-untyped**: `body` MUST NOT catch any error
  from `loader.body(at:limit:)` other than `BoundedBodyLoader.Failure.tooLarge`
  — a session-level failure that arrives before or during the transfer (host
  unreachable, TLS failure, timeout, or the cancellation above) MUST
  propagate to the caller of `search`, `detail`, `data`, or `text` as its
  original error type (for example a `URLError`), not wrapped in
  `OpenVSXError`.
- **logging-conformance-declared-unused**: `OpenVSXClient` MUST conform to
  `Loggable`, declaring `public static nonisolated let logger = makeLogger()`
  scoped by that protocol's default to category `"OpenVSXClient"`, but no
  method on `OpenVSXClient` calls `logger` — every failure surfaces to the
  caller as a thrown `OpenVSXError` case instead of a log line (`Loggable.swift`).
- **error-cases-carry-the-failing-url**: Every case of `OpenVSXError` except
  `unsafeIdentity` MUST carry the `URL` the failure happened at, so a report
  is actionable when `registryBase` is a configurable, possibly self-hosted,
  value (doc comment).

## Appearance

Not applicable — this is a stateless, read-only registry client, not a
visual component.

## States

Not applicable — this is a stateless, read-only registry client, not a
visual component.

## Accessibility

Not applicable — this is a stateless, read-only registry client, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| open-vsx-client-001 | search-pagination-params, search-single-row-per-extension, search-sort-order | `search("vim", offset: 100, size: 25)` | Request URL query items: `size=25`, `offset=100`, `sortBy=downloadCount`, `sortOrder=desc`, `includeAllVersions=false`, `query=vim` (test `searchSendsTheQuery`) |
| open-vsx-client-002 | search-default-query, search-query-omitted-when-blank | `search("")` and `search("   \n ")` | No `query` item appears on either request (test `emptyQueryOmitsTheItem`) |
| open-vsx-client-003 | search-query-trimmed | `search("  dracula  ")` | Request's `query` item value is `"dracula"` (test `queryIsTrimmed`) |
| open-vsx-client-004 | search-result-shape | Registry returns a page with one extension row `vscodevim.vim`, `totalSize: 412` | Returned `OpenVSXSearchPage.totalSize == 412`; `extensions.map(identifier) == ["vscodevim.vim"]` (test `searchDecodes`) |
| open-vsx-client-005 | detail-latest-by-default | `detail(namespace: "vscodevim", name: "vim")` then `detail(namespace: "vscodevim", name: "vim", version: "1.0.0")` | First request path ends `/vscodevim/vim`; second ends `/vscodevim/vim/1.0.0` (test `detailAddressesTheVersion`) |
| open-vsx-client-006 | status-checked-before-decode | `detail(namespace: "acme", name: "nothing")` against a stub returning HTTP 404 | Throws `OpenVSXError.requestFailed(_, status: 404)`, not a decode error (test `notFoundIsAStatusFailure`) |
| open-vsx-client-007 | status-checked-before-decode | `search("anything")` against a stub returning HTTP 503 | Throws `OpenVSXError.requestFailed(_, status: 503)` (test `serverErrorIsReported`) |
| open-vsx-client-008 | metadata-decode-failure | `search("anything")` against a stub returning `"<html>hello</html>"` with status 200 | Throws `OpenVSXError.undecodableResponse(_, underlying:)` with a non-empty `underlying` string (test `undecodableResponse`) |
| open-vsx-client-009 | text-trims-whitespace | `text(at:)` a URL whose body is `"  <64-char hex digest>\n\n"` | Returns the 64-character digest with no surrounding whitespace (test `textIsTrimmed`) |
| open-vsx-client-010 | artifact-bounded-read | `data(at:)` a URL whose body is `Data([0x50, 0x4B, 0x03, 0x04, 0x00, 0xFF])` | Returned `Data` equals the input bytes exactly (test `dataIsUntouched`) |
| open-vsx-client-011 | text-requires-utf8 | `text(at:)` a URL whose body is `Data([0xFF, 0xFE, 0xFD])` | Throws `OpenVSXError.artifactNotText(url)` (test `nonTextArtifactIsRefused`) |
| open-vsx-client-012 | artifact-status-range, error-cases-carry-the-failing-url | `data(at:)` a URL returning HTTP 410 | Throws `OpenVSXError.requestFailed(url, status: 410)` where `url` is the requested URL (test `artifactFailureNamesTheURL`) |
| open-vsx-client-013 | artifact-scheme-and-host-required | `data(at:)` a `file:///…` URL pointing at a real local file | Throws `OpenVSXError.artifactNotFetchable(url, scheme: "file")`; the local file is never read (test `fileArtifactURLIsRefused`) |
| open-vsx-client-014 | artifact-scheme-and-host-required | `data(at:)` an `http://registry.test/api/w.vsix` URL | Throws `OpenVSXError.artifactNotFetchable(url, scheme: "http")`; no request is sent (test `plainHTTPArtifactURLIsRefused`) |
| open-vsx-client-015 | artifact-host-scheme-not-pinned | `data(at:)` an `https://cdn.example/w.vsix` URL, a different host than `registryBase` | Fetch succeeds and returns the stubbed bytes (test `httpsArtifactOnAnotherHostIsFetched`) |
| open-vsx-client-016 | artifact-non-http-response-refused | `data(at:)` a URL whose stub response is not an `HTTPURLResponse` | Throws `OpenVSXError.responseNotHTTP(url)` (test `nonHTTPResponseIsRefused`) |
| open-vsx-client-017 | detail-identity-validated | `detail(namespace: "a/../../admin", name: "python")` | Throws an `OpenVSXError`; `StubbedRegistry.requestedURLs` remains empty (test `detailRefusesATraversingNamespace`) |
| open-vsx-client-018 | detail-identity-validated | `detail(namespace: "acme", name: "../../admin")`, `detail(namespace: "acme", name: "widget", version: "../..")`, `detail(namespace: "acme/evil", name: "widget")` | Each throws an `OpenVSXError`; no request is sent for any of the three (test `detailRefusesATraversingNameAndVersion`) |
| open-vsx-client-019 | detail-identity-validated, detail-result-shape | `detail(namespace: "ms-python", name: "python.vscode", version: "2024.1.0-rc.1")` | Request URL ends `/api/ms-python/python.vscode/2024.1.0-rc.1`; ordinary interior-dot names are accepted, not refused (test `detailAcceptsOrdinaryNames`) |
| open-vsx-client-020 | artifact-bounded-read | `data(at:)` a URL whose body is 4096 bytes of `0x41`, client configured with `maximumArtifactBytes: 64` | Throws `OpenVSXError.artifactTooLarge(url, limit: 64)` (test `dataRefusesAnOversizeArtifact`) |
| open-vsx-client-021 | artifact-bounded-read | Same body, client configured with `maximumArtifactBytes: 4096` | Returns all 4096 bytes (test `dataAcceptsAnArtifactInsideTheCap`) |
| open-vsx-client-022 | artifact-bounded-read | `data(at:)` a URL whose body is 10 bytes but whose declared `Content-Length` claims `1 << 30`, ceiling `1000` | Throws `OpenVSXError.artifactTooLarge(url, limit: 1000)` without reading the (small) body to the end (test `aClaimedLengthPastTheCapIsRefused`) |
| open-vsx-client-023 | artifact-bounded-read | `data(at:)` a URL whose body is 4096 bytes but whose declared `Content-Length` claims `1`, ceiling `1000` | Throws `OpenVSXError.artifactTooLarge(url, limit: 1000)` — the understated header is not believed (test `anUnderstatedLengthIsNotBelieved`) |
| open-vsx-client-024 | metadata-bounded-read | `search("vim")` against a 64 KB non-JSON body, `maximumMetadataBytes: 1024` | Throws `OpenVSXError.responseTooLarge(_, limit: 1024)`, not an undecodable-response error (test `anOversizeSearchAnswerIsRefused`) |
| open-vsx-client-025 | metadata-bounded-read | `detail(namespace: "ms-python", name: "python")` against the same 64 KB body, `maximumMetadataBytes: 1024` | Throws `OpenVSXError.responseTooLarge` (test `anOversizeDetailAnswerIsRefused`) |
| open-vsx-client-026 | metadata-bounded-read | `search("vim")` against a small JSON body claiming `Content-Length: 1 << 30`, `maximumMetadataBytes: 1024` | Throws an `OpenVSXError` before the (small) body is read to the end (test `aClaimedMetadataLengthPastTheCapIsRefused`) |
| open-vsx-client-027 | metadata-bounded-read | `search("vim")` against the empty-page JSON, `maximumMetadataBytes: 1024` | Decodes normally: `extensions.isEmpty`, `totalSize == 0` (test `anOrdinaryAnswerIsStillDecoded`) |
| open-vsx-client-028 | artifact-and-metadata-ceilings-are-distinct | Compare `OpenVSXClient.defaultMaximumMetadataBytes` and `defaultMaximumArtifactBytes` | `defaultMaximumMetadataBytes < defaultMaximumArtifactBytes` (test `theTwoCeilingsAreDistinct`) |
| open-vsx-client-029 | status-outranks-size-ceiling | `search("vim")` against a 64 KB body behind HTTP 503, `maximumMetadataBytes: 1024` | Throws `OpenVSXError.requestFailed(_, status: 503)`, not `responseTooLarge` (test `anErrorStatusOutranksTheCeiling`) |
| open-vsx-client-030 | status-outranks-size-ceiling | `data(at:)` an 8 KB body behind HTTP 404, `maximumArtifactBytes: 1000` | Throws `OpenVSXError.requestFailed(url, status: 404)`, not `artifactTooLarge` (test `aMissingArtifactIsReportedAsMissing`) |
| open-vsx-client-031 | artifact-bounded-read | `data(at:)` a 512 KB counted (non-repeating) payload, `maximumArtifactBytes: 1 << 20` | Returned `Data` equals the payload byte-for-byte, in order (test `aBodyUnderTheCapArrivesIntact`) |
| open-vsx-client-032 | artifact-bounded-read | `data(at:)` a body of exactly 4096 bytes, `maximumArtifactBytes: 4096` | Returned `Data.count == 4096` (test `aBodyOfExactlyTheCapIsAccepted`) |
| open-vsx-client-033 | artifact-bounded-read | `data(at:)` a body of 4097 bytes, `maximumArtifactBytes: 4096`, no `Content-Length` header sent | Throws `OpenVSXError.artifactTooLarge(url, limit: 4096)` (test `aBodyOneByteOverTheCapIsRefused`) |
| open-vsx-client-034 | artifact-scheme-and-host-required | `data(at:)` a `data:text/plain;base64,…` URL | Throws `OpenVSXError.artifactNotFetchable(url, scheme: "data")`; no request is sent (test `aDataURLIsRefused`) |
| open-vsx-client-035 | artifact-scheme-check-is-case-insensitive | `data(at:)` an `HTTPS://registry.test/shouted.vsix` URL | Fetch succeeds and returns the stubbed body (test `anUppercaseHTTPSSchemeIsFetched`) |
| open-vsx-client-036 | artifact-scheme-check-is-case-insensitive | `data(at:)` a `FILE:///etc/passwd` URL | Throws `OpenVSXError.artifactNotFetchable(url, scheme: "file")`; no request is sent (test `anUppercaseFileSchemeIsRefused`) |
| open-vsx-client-037 | artifact-scheme-and-host-required | `data(at:)` an `https:///lonely.vsix` URL (no host) | Throws `OpenVSXError.artifactNotFetchable(url, scheme: "https")`; no request is sent (test `aHostlessURLIsRefused`) |
| open-vsx-client-038 | metadata-decode-failure | `search("vim")` against an empty-string body with status 200 | Throws `OpenVSXError.undecodableResponse(url, underlying:)` naming the `/-/search` path, with non-empty `underlying` (test `anEmptyBodyIsUndecodable`) |
| open-vsx-client-039 | metadata-decode-failure | `search("vim")` against the JSON body `"[1, 2, 3]"` | Throws an `OpenVSXError` (wrong shape, valid JSON) (test `theWrongShapeIsUndecodable`) |
| open-vsx-client-040 | metadata-decode-failure | `search("vim")` against a body truncated mid-token (`{ "offset": 0, "totalSize": 2, "exten`) | Throws an `OpenVSXError` (test `aTruncatedBodyIsUndecodable`) |
| open-vsx-client-041 | default-registry, default-page-size, default-artifact-ceiling, default-metadata-ceiling | `OpenVSXClient()` constructed with no arguments | Its effective configuration equals `registryBase: https://open-vsx.org/api`, `maximumArtifactBytes: 536870912`, `maximumMetadataBytes: 8388608`, and `search()`'s default `size` is `50` |

## Edge Cases

- **Null and empty input**: `search`'s `query` MUST default to `""` and be
  treated as the browse case, not an error (`search-default-query`). An
  empty `namespace` or `name` passed to `detail` MUST be refused by
  `ExtensionIdentityComponent.isSafe`'s empty-value rule and reported as
  `OpenVSXError.unsafeIdentity(field:value:)`, never sent as a request
  (`detail-identity-validated`; `ExtensionIdentityComponent.swift`'s
  `empty-value-refused` rule).
- **Boundary values**: A body of exactly `maximumArtifactBytes` MUST be
  accepted in full; a body one byte over MUST be refused with
  `artifactTooLarge` even with no `Content-Length` header present to trigger
  an early refusal (tests `aBodyOfExactlyTheCapIsAccepted`,
  `aBodyOneByteOverTheCapIsRefused`). The two published ceilings,
  `defaultMaximumArtifactBytes` and `defaultMaximumMetadataBytes`, MUST
  remain distinct values three orders of magnitude apart
  (`artifact-and-metadata-ceilings-are-distinct`).
- **Concurrent access**: Concurrent calls to any of `search`, `detail`,
  `data`, or `text` on the same `OpenVSXClient` value MUST each run against
  their own `URLSessionDataTask`, tracked by `BoundedBodyLoader`'s internal
  `State` keyed on `taskIdentifier` behind one lock, so no call's outcome
  MUST depend on another concurrent call's timing or ordering
  (`independent-concurrent-calls`).
- **Error states (dependency unavailable)**: A non-2xx HTTP status from the
  registry MUST be reported as `OpenVSXError.requestFailed(url:status:)`
  before any attempt to decode the body, for both metadata reads and
  artifact reads (`status-checked-before-decode`,
  `status-outranks-size-ceiling`). A session-level failure that arrives
  before or during the transfer — DNS failure, TLS failure, connection
  refused, or a client-imposed timeout — is NOT wrapped in `OpenVSXError`; it
  MUST propagate to the caller as whatever error type `URLSession` produced,
  because `body` only intercepts `BoundedBodyLoader.Failure.tooLarge`
  (`network-failure-propagates-untyped`). This component sets no
  request-specific timeout of its own; the effective timeout is whatever
  `URLSessionConfiguration` the caller's `session` argument carries (source:
  absence of any `timeoutInterval` assignment in `init` or elsewhere in the
  file).
- **Offline / disconnected state**: Connectivity lost mid-transfer, after the
  response headers arrive but before the full body does, MUST surface as the
  underlying `URLSessionDataDelegate.didCompleteWithError` error via the same
  untyped-propagation path described above; any bytes already accumulated
  for that transfer are discarded rather than returned as a partial result —
  `search`, `detail`, `data`, and `text` each return either the complete
  decoded value or a thrown error, never a partial `Data` or `String`
  (`BoundedBodyLoader.swift`;
  `network-failure-propagates-untyped`).
- **Malformed input (path-traversal identity)**: `namespace`, `name`, or
  `version` values containing `/`, `\`, `:`, a leading `.`, or a control
  character — including a bare `/` with no `..` at all — MUST be refused by
  `detail-identity-validated` before any request is composed, since
  `appendingPathComponent` performs no escaping and would otherwise let such
  a value address an endpoint outside the intended one (source comment; tests `detailRefusesATraversingNamespace`,
  `detailRefusesATraversingNameAndVersion`).
- **Malformed input (artifact URL scheme)**: An artifact URL using `file:`,
  `data:`, plain `http:`, or any scheme other than `https`, or an `https`
  URL with no host, MUST be refused by `requireFetchable` before any request
  is made — every artifact URL `data(at:)` and `text(at:)` are given
  originates from the registry's own `files`/`downloads` JSON, so a
  malicious or misconfigured registry answer is the threat this guards
  against, not a typo by the caller (doc comment;
  `artifact-scheme-and-host-required`).
- **Cancellation**: Cancelling the awaiting `Task` MUST cancel the
  in-flight `URLSessionDataTask` rather than let it run to completion
  unobserved (`cancellation-stops-the-transfer`).
- **Registry answers with an oversized error page**: An HTTP error status
  (404, 503, or any non-2xx) accompanied by a body larger than the relevant
  ceiling MUST still be reported as `requestFailed` with that status, never
  as `artifactTooLarge`/`responseTooLarge` — a long error page from a proxy
  or a down registry MUST NOT be misreported as "the answer was too large"
  (`status-outranks-size-ceiling`; tests `anErrorStatusOutranksTheCeiling`,
  `aMissingArtifactIsReportedAsMissing`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `registryBase` | `URL` | `OpenVSXClient.openVSXRegistry` (`https://open-vsx.org/api`) | Base URL of the Open VSX-compatible registry API; overridable to address a self-hosted instance. |
| `session` | `URLSession` | `.shared` | Only its `configuration` is read, to construct the internal `BoundedBodyLoader` — in particular any injected `protocolClasses`. |
| `maximumArtifactBytes` | `Int` | `OpenVSXClient.defaultMaximumArtifactBytes` (536,870,912) | Ceiling on the bytes `data(at:)`/`text(at:)` will read before throwing `artifactTooLarge`. |
| `maximumMetadataBytes` | `Int` | `OpenVSXClient.defaultMaximumMetadataBytes` (8,388,608) | Ceiling on the bytes `search`/`detail` will read before throwing `responseTooLarge`. |
| `query` (`search` parameter) | `String` | `""` | Free-text search term; empty means browse the whole catalog. |
| `offset` (`search` parameter) | `Int` | `0` | Row offset into the result set. |
| `size` (`search` parameter) | `Int` | `OpenVSXClient.defaultPageSize` (50) | Rows requested per page. |
| `sortBy` (`search` parameter) | `SortOrder` | `.downloadCount` | One of `downloadCount`, `relevance`, `rating`, `timestamp`. |
| `version` (`detail` parameter) | `String?` | `nil` | Named version to address; `nil` addresses the latest published version. |

## Deep Linking

Not applicable: `OpenVSXClient` defines no navigable route, screen, or URL
scheme of its own — every URL it touches is either the configurable
`registryBase` API host or an artifact URL the registry itself named in its
own response, never a route this app presents to a person (traced to the
full source, which declares no route or scheme type of any kind).

## Localization

Not applicable: the source declares no user-facing string literal.
`OpenVSXError`'s cases carry structured data — a `URL`, an HTTP status code,
a field name and value — rather than display text, and no method returns or
logs a message meant to be read by a person (traced to the `OpenVSXError`
enum, and to the absence of any display-text literal in
`search`, `detail`, `data`, or `text`).

## Accessibility Options

Not applicable: this is a non-visual networking client with no rendered UI
to respond to Reduce Motion, Increase Contrast, or Differentiate Without
Color (traced to the full source, which contains no UI code of any kind).

## Feature Flags

Not applicable: the source declares no feature-flag or configuration-flag
lookup — every call to `search`, `detail`, `data`, or `text` runs the same
fixed logic unconditionally on every invocation (traced to the absence of
any flag check anywhere in the source).

## Analytics

Not applicable: the source contains no event-emission or telemetry call of
any kind — results are returned and errors are thrown directly to the
caller, with no recorded event (traced to the full body of the source file).

## Privacy

- **Data collected**: The free-text `query` a caller passes to `search`, and
  the `namespace`/`name`/`version` identifiers a caller passes to `detail`,
  are sent to the configured registry as URL query items or path
  components; `OpenVSXClient` itself collects and attaches nothing beyond
  what the caller supplies as arguments.
- **Storage**: None. `OpenVSXClient` holds no cache and persists nothing
  between calls — whichever caller receives the decoded `OpenVSXSearchPage`,
  `OpenVSXExtensionDetail`, `Data`, or `String` decides whether to store it
  (doc comment).
- **Transmission**: Every `search`/`detail` request, and every artifact
  fetch that passes `requireFetchable`, leaves the device for `registryBase`
  (`https://open-vsx.org/api` by default, or a caller-configured self-hosted
  host) over `https`; the doc comment states that nothing beyond the request
  itself is sent that the registry could attribute to a user.
- **Retention**: Not applicable — no value returned by this type is retained
  past the call that produced it; the type stores nothing between calls
  (doc comment).

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default) |
Category: `OpenVSXClient`

| Event | Level | Message |
|-------|-------|---------|
| — | — | Not emitted: `OpenVSXClient` conforms to `Loggable` and declares `public static nonisolated let logger = makeLogger()`, but no method in the source calls `logger` — every failure is communicated to the caller as a thrown `OpenVSXError` case instead of a log line. |

## Platform Notes

- **SwiftUI**: Source:
  `packages/apple/AgenticToolkit/Core/Extensions/OpenVSXClient.swift`, its
  return types in `Core/Extensions/OpenVSXCatalog.swift`, its shared bounded
  body reader in `Core/Networking/BoundedBodyLoader.swift`, its identity
  guard in `Core/Extensions/ExtensionIdentityComponent.swift`, and its
  `Loggable` conformance from `Core/Loggable.swift`. The type is plain
  `Foundation` and `OSLog` with no SwiftUI dependency; a SwiftUI-hosted
  settings screen calls `search`, `detail`, `data`, or `text` directly with
  `async`/`await` from a `Task`, and decodes the results into its own
  `@State`/`@Observable` view state — `OpenVSXClient` itself has none.
- **Compose**: On Kotlin/Android, port to a class built on OkHttp or Ktor's
  `HttpClient`, exposing `suspend fun search(...): OpenVSXSearchPage`,
  `suspend fun detail(...): OpenVSXExtensionDetail`,
  `suspend fun data(url: HttpUrl): ByteArray`, and
  `suspend fun text(url: HttpUrl): String`. Decode `OpenVSXSearchPage` and
  `OpenVSXExtensionDetail` with `kotlinx.serialization`; reproduce the
  bounded read by installing a response interceptor or a custom
  `ResponseBody` wrapper that counts bytes as they stream and cancels the
  call past the ceiling, mirroring `BoundedBodyLoader`'s per-chunk check
  rather than trusting `Content-Length` alone. Reuse the ported
  `ExtensionIdentityComponent.isSafe` before appending `namespace`, `name`,
  or `version` to an `HttpUrl.Builder`, and restrict artifact URLs to
  `https` with a non-empty host before calling `OkHttpClient.newCall`.
- **React/Web**: In TypeScript, port to an async client using `fetch`,
  exposing `async function search(...): Promise<OpenVSXSearchPage>`,
  `detail(...)`, `data(url: string): Promise<Uint8Array>`, and
  `text(url: string): Promise<string>`. `fetch` alone cannot be
  size-bounded any more than `URLSession.data(from:)` can, so read the
  response body via its `ReadableStream` reader chunk-by-chunk, summing
  byte counts against the same two ceilings and aborting with an
  `AbortController` once either is passed. Parse JSON with a `try`/`catch`
  around `JSON.parse` mapped to the same tagged-error union `OpenVSXError`
  represents; reuse the ported `isSafe` before building the request URL with
  the `URL` and `URLSearchParams` constructors; restrict artifact URLs to
  `https:` with a non-empty `hostname` before calling `fetch` on them.
- **AppKit / UIKit**: No divergence from the SwiftUI bullet above — the
  source is framework-agnostic `Foundation`/`URLSession` code, callable
  identically from an AppKit-hosted (macOS) or UIKit-hosted (iOS) caller.
  `AgenticToolkitCore`, the framework target that builds this file, is
  configured `platform: macOS` in `packages/apple/AgenticToolkit/project.yml`
  today, so an iOS caller would first need the type made available to an
  iOS target; `OpenVSXClient` itself needs no AppKit/UIKit-specific change
  to run there.
- **WinUI 3**: Port to a class built on `System.Net.Http.HttpClient`,
  exposing `async Task<OpenVSXSearchPage> SearchAsync(...)`,
  `async Task<OpenVSXExtensionDetail> DetailAsync(...)`,
  `async Task<byte[]> DataAsync(Uri url)`, and
  `async Task<string> TextAsync(Uri url)`. Decode `OpenVSXSearchPage` and
  `OpenVSXExtensionDetail` with `System.Text.Json`'s
  `JsonSerializer.DeserializeAsync` against matching record types. Enforce
  the two byte ceilings by requesting with
  `HttpCompletionOption.ResponseHeadersRead`, checking
  `HttpResponseMessage.Content.Headers.ContentLength` against the ceiling
  before reading further, and then reading the body via a manual
  `Stream.ReadAsync` loop that counts bytes and throws once the running
  count passes the ceiling — `HttpClient.GetByteArrayAsync` cannot be
  bounded any more than `URLSession.data(from:)` can, which is why the
  source reads by hand instead of calling it. Check
  `HttpResponseMessage.IsSuccessStatusCode` and read the status code before
  attempting to deserialize, exactly as `checkStatus` does ahead of
  `JSONDecoder`. Port `ExtensionIdentityComponent.IsSafe` and call it on
  `namespace`, `name`, and `version` before building the request `Uri` —
  WinUI has no path-join operator equivalent to `appendingPathComponent`, so
  a caller who skips this guard would have to concatenate path segments by
  hand, making the same traversal risk even easier to introduce by accident.
  Restrict artifact URLs to `Uri.Scheme == "https"` with a non-empty `Uri.Host`
  before calling `HttpClient.GetAsync` on them, mirroring `requireFetchable`.
  Cancellation flows through the ordinary `CancellationToken` passed to each
  `Async` method rather than through `withTaskCancellationHandler`. No
  `ObservableCollection` or `INotifyPropertyChanged` belongs on this type
  itself, since it has no UI-observable state of its own — those apply only
  to whatever ViewModel wraps calls into it.

## Design Decisions

**Decision**: Read the response body through a delegate-based
`URLSessionDataTask` (`BoundedBodyLoader`) rather than `session.data(from:)`
or `URLSession.bytes(from:)`.
**Rationale**: `data(from:)` cannot be bounded — by the time it returns,
however much a stranger decided to send is already in memory. `bytes(from:)`
can be bounded but its `AsyncBytes` yields one byte per `await`, measured at
23.8 MB/s against 2.5 GB/s for whole-chunk delivery — a cost this type pays
on every keystroke of a search field, not only on a 512 MB download
(`BoundedBodyLoader.swift` doc comment; source doc comment on
`body`).
**Approved**: pending

**Decision**: Check the HTTP status of a failure response before reporting
a body that exceeded its ceiling as too large.
**Rationale**: A 500 or 404 commonly arrives with an error document larger
than the metadata ceiling; reporting that as "the answer was too large"
sends whoever reads the error looking for a setting to raise, when the
actual situation is a registry outage or a missing extension (source
comment on `body`; tests `anErrorStatusOutranksTheCeiling`,
`aMissingArtifactIsReportedAsMissing`).
**Approved**: pending

**Decision**: Give artifact downloads and metadata reads two independent
byte ceilings, three orders of magnitude apart, rather than one shared
number.
**Rationale**: A search page or a detail record is a JSON document
describing an extension, never the extension itself, so 8 MB is generously
above any honest metadata answer; a `.vsix` legitimately reaches hundreds of
megabytes. One number for both would either make the metadata ceiling
decorative or make the download ceiling impossible (source doc comment on
`defaultMaximumMetadataBytes`).
**Approved**: pending

**Decision**: Restrict the scheme and host of an artifact URL
(`requireFetchable`), but never restrict `registryBase` to the same rule.
**Rationale**: `registryBase` is typed by whoever configures the client, not
supplied by a response, so an organisation's decision to run its own
registry over plain HTTP inside its own network is theirs to make. What a
registry *names* in a `files`/`downloads` map is a different thing entirely
— `URLSession` implements the `file:` and `data:` schemes, so an unchecked
artifact URL would let a compromised or misconfigured registry answer make
this client read a local file or an inline payload and hand it back as a
"download" (source comment on `requireFetchable`'s call sites).
**Approved**: pending

**Decision**: Hold no cache; re-fetch on every call.
**Rationale**: A memoizing client would hand a settings panel a stale
"latest version" answer for an update check whose entire purpose is to be
current (doc comment on `OpenVSXClient`).
**Approved**: pending

**Decision**: Construct `BoundedBodyLoader` from the caller's
`session.configuration` rather than from the `session` instance itself.
**Rationale**: The loader needs a session of its own to be the delegate of —
`URLSession` retains its delegate until invalidated, so a loader that were
its own delegate could never deallocate and invalidate itself. Deriving from
the configuration, not the session, is what lets an injected
`protocolClasses` (how every test here stands the registry up) still apply
to the new session (source comment in `init`;
`BoundedBodyLoader.swift` comment).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | partial | Reliability |

`separation-of-concerns` passes because `OpenVSXClient` delegates the two
concerns it does not own: identity safety to
`ExtensionIdentityComponent.isSafe` and bounded body reading to
`BoundedBodyLoader`, keeping its own code to URL composition, status
checking, and decoding (`stateless-value-type`, Overview). `unit-test-coverage`
passes: 27 test functions across `OpenVSXClientTests.swift` and
`OpenVSXClientLimitsTests.swift` exercise every public method's happy path,
every `OpenVSXError` case, both ceilings at their exact boundaries, every
refused URL scheme, and case-insensitive scheme matching.
`explicit-error-handling` passes: every failure mode this type detects
raises a specific, `Equatable` `OpenVSXError` case rather than returning
`nil` or logging and continuing — with the documented exception that a
session-level failure below this type (network unreachable, cancelled)
propagates as its own error type rather than being wrapped, which is stated
plainly as the `network-failure-propagates-untyped` requirement rather than
hidden. `input-sanitization` passes: `requireSafeComponent` refuses a
path-traversing `namespace`/`name`/`version` before any request is composed,
and `requireFetchable` refuses a non-`https` or hostless artifact URL before
any request is made (`detail-identity-validated`,
`artifact-scheme-and-host-required`). `data-integrity` passes: the response
byte count is bounded before any JSON decode is attempted, the HTTP status
is checked before both the ceiling-refusal report and the decode, and a
non-UTF8 artifact is refused by `text(at:)` rather than mangled
(`status-checked-before-decode`, `text-requires-utf8`). `fault-tolerance` is
partial: a single failed request — whether a bad status, an oversized body,
or a session-level network error — is reported immediately with no retry or
backoff of any kind; the source's own framing is that this is a thin,
current-by-construction read of the registry, and retrying a request is
left entirely to whichever caller decides a failure is worth retrying
(doc comment; absence of any retry loop or backoff delay in the
source).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
