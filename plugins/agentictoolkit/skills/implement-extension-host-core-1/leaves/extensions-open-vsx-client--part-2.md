<!-- leaf: implement-extension-host-core-1/extensions-open-vsx-client--part-2 · source: extension-host-core-extensions-open-vsx-client.md -->

# OpenVSXClient — continued (part 2)

**Rules** (cite as `implement-extension-host-core-1/extensions-open-vsx-client--part-2#<slug>`):

- `default-registry` MUST
- `self-hosted-registry-override` MAY
- `default-page-size` MUST
- `default-artifact-ceiling` MUST
- `default-metadata-ceiling` MUST
- `stateless-value-type` MUST
- `session-configuration-reuse` MUST
- `search-default-query` MUST
- `search-query-trimmed` MUST
- `search-query-omitted-when-blank` MUST
- `search-pagination-params` MUST
- `search-single-row-per-extension` MUST
- `search-sort-order` MUST
- `search-malformed-registry-url` MUST
- `search-result-shape` MUST
- `detail-latest-by-default` MUST
- `detail-identity-validated` MUST
- `detail-result-shape` MUST
- `artifact-scheme-and-host-required` MUST
- `artifact-scheme-check-is-case-insensitive` MUST
- `artifact-host-scheme-not-pinned` MUST
- `artifact-bounded-read` MUST
- `status-outranks-size-ceiling` MUST
- `artifact-non-http-response-refused` MUST
- `artifact-status-range` MUST
- `text-trims-whitespace` MUST
- `text-requires-utf8` MUST
- `metadata-bounded-read` MUST
- `artifact-and-metadata-ceilings-are-distinct` MUST
- `status-checked-before-decode` MUST
- `metadata-decode-failure` MUST
- `sendable-isolation` MUST
- `independent-concurrent-calls` MUST

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
